import pg from 'pg';
import { readdir, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { readConfig, validateConfig } from './config.mjs';

// Reject inconsistent URLs or keys before changing cluster roles or passwords.
Object.assign(process.env, validateConfig(readConfig()));

const required = (key) => {
  if (!process.env[key]) throw new Error(`Missing ${key}`);
  return process.env[key];
};
const identifier = (s) => '"' + s.replaceAll('"', '""') + '"';
const literal = (s) => "'" + s.replaceAll("'", "''") + "'";
const url = new URL(required('ADMIN_DATABASE_URL'));
const database = decodeURIComponent(url.pathname.slice(1));
if (!/^[a-z][a-z0-9_]{0,62}$/.test(database)) throw new Error('Invalid database name');
const maintenanceURL = new URL(url);
maintenanceURL.pathname = '/postgres';
const admin = new pg.Client({ connectionString: maintenanceURL.toString() });
await admin.connect();
try {
  await admin.query("SELECT pg_advisory_lock(hashtext('project-database-bootstrap'))");
  await admin.query('SET standard_conforming_strings = on');
  if (!(await admin.query('SELECT 1 FROM pg_database WHERE datname=$1', [database])).rowCount) {
    await admin.query(`CREATE DATABASE ${identifier(database)}`);
  }
  // Service roles are cluster-wide: keep one project per local cluster.
  for (const [role, key] of [['app_backend', 'BACKEND_DB_PASSWORD'], ['app_agent', 'AGENT_DB_PASSWORD']]) {
    const password = required(key);
    if (password.length < 24) throw new Error(`${key} must have at least 24 characters`);
    if (!(await admin.query('SELECT 1 FROM pg_roles WHERE rolname=$1', [role])).rowCount) {
      await admin.query(`CREATE ROLE ${identifier(role)} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS`);
    }
    await admin.query(`ALTER ROLE ${identifier(role)} PASSWORD ${literal(password)}`);
  }
  await admin.query(`REVOKE ALL ON DATABASE ${identifier(database)} FROM PUBLIC`);
  await admin.query(`GRANT CONNECT ON DATABASE ${identifier(database)} TO app_backend, app_agent`);
} finally {
  await admin.end();
}

const db = new pg.Client({ connectionString: url.toString() });
await db.connect();
try {
  await db.query("SELECT pg_advisory_lock(hashtext('project-database-migrations'))");
  await db.query('REVOKE CREATE ON SCHEMA public FROM PUBLIC');
  await db.query(`CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now()
  )`);
  const files = (await readdir(new URL('../db/migrations/', import.meta.url))).filter(f => f.endsWith('.sql')).sort();
  for (const file of files) {
    const sql = await readFile(new URL(`../db/migrations/${file}`, import.meta.url), 'utf8');
    const checksum = createHash('sha256').update(sql).digest('hex');
    const previous = await db.query('SELECT checksum FROM public.schema_migrations WHERE version=$1', [file]);
    if (previous.rowCount) {
      if (previous.rows[0].checksum !== checksum) throw new Error(`Applied migration changed: ${file}`);
      console.log(`Already applied: ${file}`);
      continue;
    }
    await db.query('BEGIN');
    try {
      await db.query(sql);
      await db.query('INSERT INTO public.schema_migrations(version, checksum) VALUES ($1,$2)', [file, checksum]);
      await db.query('COMMIT');
      console.log(`Applied: ${file}`);
    } catch (error) {
      await db.query('ROLLBACK');
      throw error;
    }
  }
} finally {
  await db.end();
}
