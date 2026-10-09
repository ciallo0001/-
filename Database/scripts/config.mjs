import { readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { isIP } from 'node:net';

export const backendKeys = ['BACKEND_DATABASE_URL', 'DATA_ENCRYPTION_KEY', 'EMAIL_LOOKUP_KEY'];
export const agentKeys = ['AGENT_DATABASE_URL'];
export function readConfig() {
  // The development .env is authoritative; do not silently merge another project's environment.
  return parseEnv(readFileSync('.env', 'utf8'));
}
export function validateConfig(c) {
  const errors = [];
  const require = key => { if (!c[key] || /replace_me|replace_with/i.test(c[key])) errors.push(`${key}: missing or placeholder`); };
  for (const key of [...backendKeys, ...agentKeys, 'ADMIN_DATABASE_URL', 'PGHOST', 'PGPORT', 'PGDATABASE', 'POSTGRES_USER', 'POSTGRES_PASSWORD', 'BACKEND_DB_PASSWORD', 'AGENT_DB_PASSWORD', 'BOOTSTRAP_ADMIN_EMAIL']) require(key);
  const local = host => host === 'localhost' || host === '[::1]' || host === '::1' || (isIP(host) === 4 && host.startsWith('127.'));
  if (!/^[a-z][a-z0-9_]{0,62}$/.test(c.PGDATABASE ?? '')) errors.push('PGDATABASE: invalid database name');
  if (!/^\d+$/.test(c.PGPORT ?? '') || +c.PGPORT < 1024 || +c.PGPORT > 65535) errors.push('PGPORT: expected 1024..65535');
  for (const [key, user, password] of [
    ['ADMIN_DATABASE_URL', c.POSTGRES_USER, c.POSTGRES_PASSWORD],
    ['BACKEND_DATABASE_URL', 'app_backend', c.BACKEND_DB_PASSWORD],
    ['AGENT_DATABASE_URL', 'app_agent', c.AGENT_DB_PASSWORD],
  ]) {
    try {
      const u = new URL(c[key]);
      if (!['postgres:', 'postgresql:'].includes(u.protocol) || u.hash) throw new Error();
      if (decodeURIComponent(u.username) !== user || decodeURIComponent(u.password) !== password) errors.push(`${key}: account/password differs from individual settings`);
      if (u.hostname !== c.PGHOST || (u.port || '5432') !== c.PGPORT || decodeURIComponent(u.pathname.slice(1)) !== c.PGDATABASE) errors.push(`${key}: host/port/database differs from PG settings`);
      if (!local(u.hostname) && u.searchParams.get('sslmode') !== 'verify-full') errors.push(`${key}: remote database requires sslmode=verify-full`);
    } catch { errors.push(`${key}: invalid PostgreSQL URL`); }
  }
  for (const key of ['POSTGRES_PASSWORD', 'BACKEND_DB_PASSWORD', 'AGENT_DB_PASSWORD']) if ((c[key]?.length ?? 0) < 24) errors.push(`${key}: expected at least 24 characters`);
  const secrets = ['POSTGRES_PASSWORD', 'BACKEND_DB_PASSWORD', 'AGENT_DB_PASSWORD'].map(k => c[k]);
  if (new Set(secrets).size !== 3) errors.push('Database accounts must use distinct passwords');
  for (const key of ['DATA_ENCRYPTION_KEY', 'EMAIL_LOOKUP_KEY']) {
    const value = c[key] ?? '';
    const decoded = Buffer.from(value, 'base64');
    if (decoded.length !== 32 || decoded.toString('base64') !== value) errors.push(`${key}: expected canonical Base64 for 32 bytes`);
  }
  if (c.DATA_ENCRYPTION_KEY === c.EMAIL_LOOKUP_KEY) errors.push('Encryption and lookup keys must differ');
  if (errors.length) throw new Error(errors.join('\n'));
  return c;
}
