import { randomBytes, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
const scrypt = promisify(scryptCallback);
const options = { N: 131072, r: 8, p: 1, maxmem: 256 * 1024 * 1024 };

export async function hashPassword(password) {
  if (password.length < 12) throw new Error('Use a password of at least 12 characters');
  const salt = randomBytes(16);
  const key = await scrypt(password, salt, 64, options);
  return `$scrypt$ln=17,r=8,p=1$${salt.toString('base64')}$${key.toString('base64')}`;
}

export async function verifyPassword(password, encoded) {
  const parts = encoded.split('$');
  if (parts.length !== 5 || parts[1] !== 'scrypt' || parts[2] !== 'ln=17,r=8,p=1') return false;
  const expected = Buffer.from(parts[4], 'base64');
  const salt = Buffer.from(parts[3], 'base64');
  if (expected.length !== 64 || salt.length !== 16) return false;
  const actual = await scrypt(password, salt, 64, options);
  return timingSafeEqual(actual, expected);
}

