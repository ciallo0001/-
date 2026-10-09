import pg from 'pg';
import { randomUUID } from 'node:crypto';
import { hashPassword } from './password.mjs';
import { emailLookup, encrypt } from './protection.mjs';

if (!process.env.ADMIN_DATABASE_URL) throw new Error('Missing ADMIN_DATABASE_URL');
const account = (process.env.DEMO_STUDENT_ACCOUNT || 's-demo-01').trim().toLowerCase();
const password = process.env.DEMO_STUDENT_PASSWORD || 'Demo@2026-campus';
if (!/^[a-z0-9][a-z0-9._-]{2,63}$/.test(account)) throw new Error('DEMO_STUDENT_ACCOUNT is invalid');
if (password.length < 12 || password.length > 256) throw new Error('DEMO_STUDENT_PASSWORD must be 12..256 characters');

const db = new pg.Client({ connectionString: process.env.ADMIN_DATABASE_URL });
await db.connect();
try {
  await db.query('BEGIN');
  const existing = await db.query('SELECT id, role, status FROM app.users WHERE login_account=$1', [account]);
  let id;
  if (existing.rowCount) {
    if (existing.rows[0].role !== 'student') throw new Error('Existing account is not a student; refusing to change its role.');
    id = existing.rows[0].id;
    console.log(`Student account already exists: ${account}`);
  } else {
    id = randomUUID();
    const email = `${account}@demo.invalid`;
    await db.query(`INSERT INTO app.users
      (id, email, email_ciphertext, email_lookup, login_account, password_hash, display_name, role)
      VALUES ($1,$2,$3,$4,$5,$6,$7,'student')`, [
      id, `${id}@private.invalid`, encrypt(email, id, 'email'), emailLookup(email), account,
      await hashPassword(password), '演示学生',
    ]);
    console.log(`Created local demo student: ${account}`);
  }
  const admin = await db.query("SELECT id FROM app.users WHERE role='admin' AND status='active' ORDER BY created_at LIMIT 1");
  if (admin.rowCount) {
    const studentNo = 'S-DEMO-01';
    const credential = emailLookup(studentNo);
    const realName = encrypt('演示学生', id, 'identity-real-name');
    await db.query(`INSERT INTO app.student_profiles
      (user_id,student_no_ciphertext,student_no_lookup,college,major,grade,class_name)
      VALUES ($1,$2,$3,'示范学院','综合服务',1,'演示班')
      ON CONFLICT (user_id) DO UPDATE SET student_no_ciphertext=EXCLUDED.student_no_ciphertext,
        student_no_lookup=EXCLUDED.student_no_lookup, updated_at=now()`,
      [id, encrypt(studentNo, id, 'student-number'), credential]);
    await db.query(`INSERT INTO app.identity_verifications
      (user_id,identity_type,real_name_ciphertext,credential_lookup,status,provider,verified_by,verified_at)
      VALUES ($1,'student',$2,$3,'verified','manual',$4,now())
      ON CONFLICT (user_id,identity_type) DO UPDATE SET real_name_ciphertext=EXCLUDED.real_name_ciphertext,
        credential_lookup=EXCLUDED.credential_lookup,status='verified',provider='manual',verified_by=EXCLUDED.verified_by,
        verified_at=EXCLUDED.verified_at, updated_at=now()`, [id, realName, credential, admin.rows[0].id]);
  }
  await db.query('COMMIT');
  console.log(`Development password: ${password}`);
} catch (error) {
  await db.query('ROLLBACK').catch(() => {});
  throw error;
} finally {
  await db.end();
}
