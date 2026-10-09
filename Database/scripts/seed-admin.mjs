import pg from 'pg';
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { hashPassword } from './password.mjs';
import { assertDatabaseKeys, emailLookup, encrypt, normalizeEmail } from './protection.mjs';

if (!process.env.BACKEND_DATABASE_URL) throw new Error('Missing BACKEND_DATABASE_URL');
const db = new pg.Client({ connectionString: process.env.BACKEND_DATABASE_URL });
const email = normalizeEmail(process.env.BOOTSTRAP_ADMIN_EMAIL || 'admin@local.test');
await db.connect();
try {
  await assertDatabaseKeys(db);
  await db.query('BEGIN');
  await db.query("SELECT pg_advisory_xact_lock(hashtext('bootstrap-admin'))");
  const existing = await db.query('SELECT id, role FROM app.users WHERE email_lookup=$1', [emailLookup(email)]);
  if (existing.rowCount) {
    if (existing.rows[0].role !== 'admin') throw new Error('Bootstrap email belongs to a non-admin; refusing to elevate it.');
    console.log('Administrator already exists; password unchanged.');
  } else {
    await mkdir('.local', { recursive: true });
    const path = '.local/bootstrap-admin.json';
    let credentials;
    try {
      credentials = JSON.parse(await readFile(path, 'utf8'));
      if (credentials.email !== email) throw new Error('Existing bootstrap credentials use a different email');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      credentials = { email, password: randomBytes(24).toString('base64url') };
      await writeFile(path, JSON.stringify(credentials, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
    }
    const id = randomUUID();
    await db.query(`INSERT INTO app.users(id,email,password_hash,display_name,role,email_ciphertext,email_lookup)
      VALUES ($1,$2,$3,'Administrator','admin',$4,$5)`,
      [id, `${id}@private.invalid`, await hashPassword(credentials.password), encrypt(email, id, 'email'), emailLookup(email)]);
    console.log('Administrator created. Development login saved in .local/bootstrap-admin.json');
  }
  await db.query('COMMIT');
} catch (error) {
  await db.query('ROLLBACK');
  throw error;
} finally {
  await db.end();
}
