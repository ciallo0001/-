import { randomBytes } from 'node:crypto';
import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';

if (existsSync('.env')) {
  console.log('.env already exists; kept existing credentials.');
} else {
  const secret = () => randomBytes(24).toString('hex');
  const admin = secret(), backend = secret(), agent = secret();
  const lines = [
    'PGHOST=127.0.0.1', 'PGPORT=5432', 'PGDATABASE=app_dev', 'POSTGRES_USER=postgres',
    `POSTGRES_PASSWORD=${admin}`, `BACKEND_DB_PASSWORD=${backend}`, `AGENT_DB_PASSWORD=${agent}`,
    `ADMIN_DATABASE_URL=postgresql://postgres:${admin}@127.0.0.1:5432/app_dev`,
    `BACKEND_DATABASE_URL=postgresql://app_backend:${backend}@127.0.0.1:5432/app_dev`,
    `AGENT_DATABASE_URL=postgresql://app_agent:${agent}@127.0.0.1:5432/app_dev`,
    'BOOTSTRAP_ADMIN_EMAIL=admin@local.test', '',
  ];
  writeFileSync('.env', lines.join('\n'), { flag: 'wx', mode: 0o600 });
  console.log('Created .env with random development credentials.');
}

// Add new settings without rotating existing database passwords or encryption keys.
const existing = readFileSync('.env', 'utf8');
const settings = {
  DATA_ENCRYPTION_KEY: randomBytes(32).toString('base64'),
  EMAIL_LOOKUP_KEY: randomBytes(32).toString('base64'),
};
const additions = Object.entries(settings).filter(([key]) => !new RegExp(`^${key}=`, 'm').test(existing));
if (additions.length) {
  appendFileSync('.env', '\n' + additions.map(([key, value]) => `${key}=${value}`).join('\n') + '\n');
  console.log('Added missing database encryption settings; existing keys kept.');
}
