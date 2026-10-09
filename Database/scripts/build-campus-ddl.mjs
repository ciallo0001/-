import { readFile, writeFile, readdir } from 'node:fs/promises';
const files = (await readdir('db/migrations')).filter(f=>f.endsWith('.sql')).sort().map(f=>'db/migrations/'+f);
const parts = await Promise.all(files.map(file => readFile(file, 'utf8')));
const preface = `-- GENERATED complete campus database design. PostgreSQL 18.
-- Build: node scripts/build-campus-ddl.mjs
-- ONLY execute on a NEW EMPTY database as the postgres migration account.
-- Do not execute on the current app_dev database. Do not run db:init on this design database.
-- Existing cluster service roles are reused without changing passwords or role memberships.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_backend') THEN
    CREATE ROLE app_backend NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_agent') THEN
    CREATE ROLE app_agent NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
END $$;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
`;
await writeFile('db/design/campus-platform.full.sql', preface + parts.map((text,i) => `\n-- SOURCE: ${files[i]}\n${text}`).join('\n') + `
-- Fresh installs require encrypted identity columns; no plaintext backfill is needed.
ALTER TABLE app.users ALTER COLUMN email_ciphertext SET NOT NULL, ALTER COLUMN email_lookup SET NOT NULL;
COMMIT;
`, 'utf8');
console.log('Built complete DDL; original app migrations untouched.');
