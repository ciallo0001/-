import pg from 'pg';
import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { readConfig, validateConfig } from './config.mjs';
import { assertDatabaseKeys } from './protection.mjs';

let failures = 0;
async function check(label, action) {
  try { await action(); console.log(`OK   ${label}`); }
  catch { failures++; console.error(`FAIL ${label}`); }
}
async function using(url, action) {
  const db = new pg.Client({ connectionString: url, connectionTimeoutMillis: 5000, query_timeout: 5000 });
  try { await db.connect(); await action(db); } finally { await db.end(); }
}
try {
  const c = validateConfig(readConfig());
  console.log('OK   configuration (secrets hidden)');
  Object.assign(process.env, c);
  await check('database and migration checksums', () => using(c.ADMIN_DATABASE_URL, async db => {
    const rows = (await db.query('SELECT version,checksum FROM public.schema_migrations')).rows;
    const files = (await readdir('db/migrations')).filter(f => f.endsWith('.sql')).sort();
    if (rows.length !== files.length) throw new Error();
    for (const file of files) {
      const sum = createHash('sha256').update(await readFile(`db/migrations/${file}`)).digest('hex');
      if (!rows.some(row => row.version === file && row.checksum === sum)) throw new Error();
    }
  }));
  await check('backend account and encryption keys', () => using(c.BACKEND_DATABASE_URL, async db => {
    const { rows } = await db.query('SELECT current_user AS name,rolsuper,rolbypassrls,rolcreaterole,rolcreatedb FROM pg_roles WHERE rolname=current_user');
    if (rows[0].name !== 'app_backend' || rows[0].rolsuper || rows[0].rolbypassrls || rows[0].rolcreaterole || rows[0].rolcreatedb) throw new Error();
    await assertDatabaseKeys(db);
    const missing = await db.query('SELECT 1 FROM app.users WHERE email_ciphertext IS NULL OR email_lookup IS NULL LIMIT 1');
    if (missing.rowCount) throw new Error();
  }));
  await check('Agent account, sensitive column restrictions and default isolation', () => using(c.AGENT_DATABASE_URL, async db => {
    const { rows } = await db.query(`SELECT current_user AS name,rolsuper,rolbypassrls,rolcreaterole,rolcreatedb,
      has_column_privilege(current_user,'app.users','password_hash','SELECT') AS password,
      has_column_privilege(current_user,'app.users','email_ciphertext','SELECT') AS email,
      has_table_privilege(current_user,'app.auth_sessions','SELECT') AS sessions
      FROM pg_roles WHERE rolname=current_user`);
    const r = rows[0];
    if (r.name !== 'app_agent' || r.rolsuper || r.rolbypassrls || r.rolcreaterole || r.rolcreatedb || r.password || r.email || r.sessions) throw new Error();
    if ((await db.query('SELECT id FROM app.users LIMIT 1')).rowCount) throw new Error();
  }));
  if (failures) process.exitCode = 1;
} catch (error) { console.error(error.message); process.exitCode = 1; }
