import pg from 'pg';
import { decrypt, emailLookup, encrypt, normalizeEmail } from './protection.mjs';

if (!process.env.ADMIN_DATABASE_URL) throw new Error('Missing ADMIN_DATABASE_URL');
const marker = 'login-security-key-check-v1';
const lookupCheck = emailLookup(marker);
const encryptionCheck = encrypt(marker, 'config', 'key-check');
const db = new pg.Client({ connectionString: process.env.ADMIN_DATABASE_URL });
await db.connect();
try {
  await db.query('BEGIN');
  await db.query("SELECT pg_advisory_xact_lock(hashtext('project-database-migrations'))");
  await db.query('LOCK TABLE app.users IN ACCESS EXCLUSIVE MODE');
  const settings = await db.query('SELECT encryption_check,lookup_check FROM app.crypto_settings');
  if (settings.rowCount) {
    const row = settings.rows[0];
    if (decrypt(row.encryption_check, 'config', 'key-check') !== marker || !lookupCheck.equals(row.lookup_check)) {
      throw new Error('Encryption keys do not match database; restore original keys');
    }
  } else {
    await db.query('INSERT INTO app.crypto_settings(encryption_check,lookup_check) VALUES ($1,$2)', [encryptionCheck, lookupCheck]);
  }
  const users = await db.query('SELECT id,email,email_ciphertext,email_lookup,profile,private_profile_ciphertext FROM app.users');
  let converted = 0;
  for (const user of users.rows) {
    const email = user.email_ciphertext ? decrypt(user.email_ciphertext, user.id, 'email') : normalizeEmail(user.email);
    if (user.email_ciphertext && !emailLookup(email).equals(user.email_lookup)) throw new Error('Email lookup key mismatch');
    const publicProfile = { ...user.profile };
    const privateProfile = user.private_profile_ciphertext
      ? JSON.parse(decrypt(user.private_profile_ciphertext, user.id, 'private-profile')) : {};
    let profileChanged = false;
    for (const field of ['realName', 'phone', 'address']) {
      if (Object.hasOwn(publicProfile, field)) {
        if (!Object.hasOwn(privateProfile, field)) privateProfile[field] = publicProfile[field];
        delete publicProfile[field];
        profileChanged = true;
      }
    }
    if (!user.email_ciphertext || profileChanged) {
      await db.query(`UPDATE app.users SET email=$2,email_ciphertext=$3,email_lookup=$4,profile=$5,
        private_profile_ciphertext=$6 WHERE id=$1`, [user.id, `${user.id}@private.invalid`,
        encrypt(email, user.id, 'email'), emailLookup(email), JSON.stringify(publicProfile),
        encrypt(JSON.stringify(privateProfile), user.id, 'private-profile')]);
      converted++;
    }
  }
  await db.query('ALTER TABLE app.users ALTER COLUMN email_ciphertext SET NOT NULL, ALTER COLUMN email_lookup SET NOT NULL');
  await db.query('COMMIT');
  console.log(`Encrypted ${converted} existing user(s); keys verified and required columns enforced.`);
} catch (error) {
  await db.query('ROLLBACK');
  // PostgreSQL constraint details may contain personal data; do not log raw errors.
  console.error(`Encryption migration failed (${error.code ?? 'key/data validation'}). Transaction rolled back; check keys and data.`);
  process.exitCode = 1;
} finally { await db.end(); }
