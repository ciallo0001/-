import { spawn } from 'node:child_process';
import { existsSync, createReadStream } from 'node:fs';
import { mkdir, rename, readFile, writeFile } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { resolve, basename } from 'node:path';
import pg from 'pg';
import { readConfig, validateConfig } from './config.mjs';
import { assertDatabaseKeys, decrypt, emailLookup } from './protection.mjs';

const quote = name => '"' + name.replaceAll('"', '""') + '"';
async function checksum(file) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}
function pgTool(name, url, args) {
  const suffix = process.platform === 'win32' ? '.exe' : '';
  const portable = resolve(`.local/pgsql/bin/${name}${suffix}`);
  const binary = existsSync(portable) ? portable : name;
  // Pass credentials only via the child's environment, not process arguments/output.
  const env = { ...process.env, PGPASSWORD: decodeURIComponent(url.password), PGCONNECT_TIMEOUT: '10', PGAPPNAME: 'project-backup' };
  for (const key of Object.keys(env)) if (key.startsWith('PG') && !['PGPASSWORD','PGCONNECT_TIMEOUT','PGAPPNAME'].includes(key)) delete env[key];
  if (url.searchParams.has('sslmode')) env.PGSSLMODE = url.searchParams.get('sslmode');
  if (url.searchParams.has('sslrootcert')) env.PGSSLROOTCERT = url.searchParams.get('sslrootcert');
  return new Promise((done, reject) => {
    const child = spawn(binary, ['--host', url.hostname, '--port', url.port || '5432', '--username', decodeURIComponent(url.username), ...args], { env, stdio: 'ignore', windowsHide: true });
    child.on('error', () => reject(new Error(`${name} unavailable; install PostgreSQL client tools`)));
    child.on('exit', code => code === 0 ? done() : reject(new Error(`${name} failed; check version, permissions, disk and connection (sensitive output suppressed)`)));
  });
}
async function verifyDatabase(url) {
  const db = new pg.Client({ connectionString: url.toString(), connectionTimeoutMillis: 5000 });
  try {
    await db.connect();
    await assertDatabaseKeys(db);
    for (const table of ['users','agent_sessions','agent_messages','agent_memories','auth_sessions']) {
      await db.query(`SELECT 1 FROM app.${table} LIMIT 1`);
    }
    const migrations = await db.query('SELECT version FROM public.schema_migrations ORDER BY version');
    if (!migrations.rowCount) throw new Error('Restored database has no migrations');
    // Walk in bounded batches and verify actual ciphertext, not only the key marker.
    let after = '00000000-0000-0000-0000-000000000000';
    while (true) {
      const batch = await db.query(`SELECT id,email_ciphertext,email_lookup,private_profile_ciphertext
        FROM app.users WHERE id>$1::uuid ORDER BY id LIMIT 200`, [after]);
      if (!batch.rowCount) break;
      for (const user of batch.rows) {
        const email = decrypt(user.email_ciphertext, user.id, 'email');
        if (!emailLookup(email).equals(user.email_lookup)) throw new Error('Restored email index does not match encryption key');
        if (user.private_profile_ciphertext) {
          try { JSON.parse(decrypt(user.private_profile_ciphertext, user.id, 'private-profile')); }
          catch { throw new Error('Private profile failed decryption or format validation'); }
        }
      }
      after = batch.rows.at(-1).id;
    }
    return db;
  } catch (error) { await db.end(); throw error; }
}
async function main() {
  const c = validateConfig(readConfig()); Object.assign(process.env, c);
  const url = new URL(c.ADMIN_DATABASE_URL);
  const action = process.argv[2];
  const options = process.argv.slice(3);
  const get = key => { const i = options.indexOf(key); return i < 0 ? undefined : options[i + 1]; };
  if (action === 'create') {
    if (options.length) throw new Error('Usage: npm run db:backup');
    const db = await verifyDatabase(url); await db.end();
    await mkdir('.local/backups', { recursive: true });
    const stamp = new Date().toISOString().replaceAll(':','-');
    const file = resolve(`.local/backups/${c.PGDATABASE}-${stamp}-${randomUUID().slice(0,8)}.dump`);
    await pgTool('pg_dump', url, ['--dbname', c.PGDATABASE, '--format=custom', '--file', file + '.partial']);
    await rename(file + '.partial', file);
    const manifest = { version: 1, file: basename(file), sha256: await checksum(file), database: c.PGDATABASE, createdAt: new Date().toISOString(), keysIncluded: false };
    await writeFile(file + '.json', JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
    console.log(`Backup created: ${file}`);
    console.log('Encryption keys are NOT included. Keep DATA_ENCRYPTION_KEY and EMAIL_LOOKUP_KEY separately.');
    return;
  }
  if (action !== 'restore' && action !== 'verify') throw new Error('Expected create, restore or verify');
  let file = get('--file');
  if (options.some((value, i) => i % 2 === 0 && !['--file','--database'].includes(value)) || options.length % 2 !== 0) throw new Error('Expected --file <dump> and optionally --database <new-name>');
  if (!file) throw new Error('Provide --file <dump>; no implicit selection of backups');
  file = resolve(file);
  const manifest = JSON.parse(await readFile(file + '.json', 'utf8'));
  if (manifest.version !== 1 || manifest.file !== basename(file) || await checksum(file) !== manifest.sha256) throw new Error('Backup checksum/manifest mismatch');
  const target = action === 'verify' ? 'restore_check_' + randomUUID().replaceAll('-','') : get('--database');
  if (!target || !/^[a-z][a-z0-9_]{0,62}$/.test(target) || [c.PGDATABASE,'postgres','template0','template1'].includes(target)) throw new Error('Restore requires a NEW database name, different from the current database');
  const maintenance = new URL(url); maintenance.pathname = '/postgres';
  const admin = new pg.Client({ connectionString: maintenance.toString(), connectionTimeoutMillis: 5000 });
  let created = false;
  try {
    await admin.connect();
    if ((await admin.query('SELECT 1 FROM pg_database WHERE datname=$1', [target])).rowCount) throw new Error('Target already exists; restore never overwrites a database');
    // Restore requires roles provisioned by this project's db:init on the target cluster.
    if ((await admin.query("SELECT 1 FROM pg_roles WHERE rolname IN ('app_backend','app_agent')")).rowCount !== 2) throw new Error('Provision backend and Agent roles on the target cluster first');
    await admin.query(`CREATE DATABASE ${quote(target)} TEMPLATE template0`); created = true;
    await admin.query(`REVOKE ALL ON DATABASE ${quote(target)} FROM PUBLIC`);
    const restored = new URL(url); restored.pathname = '/' + target;
    await pgTool('pg_restore', restored, ['--dbname', target, '--no-owner', '--exit-on-error', '--single-transaction', file]);
    const db = await verifyDatabase(restored);
    try {
      // A restored backup must not reactivate old browser login tokens.
      await db.query('DELETE FROM app.auth_sessions');
      console.log('Restored schema, encryption keys and tables verified; login sessions invalidated.');
    } finally { await db.end(); }
    if (action === 'restore') {
      await admin.query(`GRANT CONNECT ON DATABASE ${quote(target)} TO app_backend,app_agent`);
      console.log(`Restored to NEW database: ${target}. Original database and .env unchanged.`);
    }
  } finally {
    try {
      // Only verification removes its randomly named database, created in this invocation.
      if (action === 'verify' && created) { await admin.query(`DROP DATABASE ${quote(target)}`); console.log('Temporary restore-check database removed.'); }
    } finally { await admin.end(); }
  }
}
main().catch(error => {
  // Driver messages can contain database details; never print raw connection or SQL errors.
  console.error(error.code ? `Backup/restore failed (${error.code}); original database unchanged.` : error.message);
  process.exitCode = 1;
});
