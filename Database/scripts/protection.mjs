import { createCipheriv, createDecipheriv, createHmac, randomBytes } from 'node:crypto';

function key(name) {
  const value = Buffer.from(process.env[name] ?? '', 'base64');
  if (value.length !== 32) throw new Error(`${name} must be a base64-encoded 32-byte key`);
  if (process.env.DATA_ENCRYPTION_KEY === process.env.EMAIL_LOOKUP_KEY) throw new Error('Encryption and lookup keys must differ');
  return value;
}
export function normalizeEmail(email) { return email.trim().toLowerCase(); }
export function emailLookup(email) {
  return createHmac('sha256', key('EMAIL_LOOKUP_KEY')).update(normalizeEmail(email)).digest();
}
export function encrypt(value, userId, field) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key('DATA_ENCRYPTION_KEY'), nonce);
  cipher.setAAD(Buffer.from(`app.users:${userId}:${field}`));
  return Buffer.concat([Buffer.from([1]), nonce, cipher.update(value, 'utf8'), cipher.final(), cipher.getAuthTag()]);
}
export function decrypt(data, userId, field) {
  if (!data || data.length < 29 || data[0] !== 1) throw new Error('Unsupported ciphertext');
  const cipher = createDecipheriv('aes-256-gcm', key('DATA_ENCRYPTION_KEY'), data.subarray(1, 13));
  cipher.setAAD(Buffer.from(`app.users:${userId}:${field}`));
  cipher.setAuthTag(data.subarray(-16));
  return Buffer.concat([cipher.update(data.subarray(13, -16)), cipher.final()]).toString('utf8');
}

export async function assertDatabaseKeys(db) {
  const { rows } = await db.query('SELECT encryption_check,lookup_check FROM app.crypto_settings WHERE singleton');
  const marker = 'login-security-key-check-v1';
  if (rows.length !== 1 || decrypt(rows[0].encryption_check, 'config', 'key-check') !== marker
    || !emailLookup(marker).equals(rows[0].lookup_check)) throw new Error('Database encryption keys do not match');
}
