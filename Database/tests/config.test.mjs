import assert from 'node:assert/strict';
import test from 'node:test';
import { backendKeys, agentKeys, validateConfig } from '../scripts/config.mjs';

const valid = () => ({
  PGHOST:'127.0.0.1',PGPORT:'5432',PGDATABASE:'app_test',POSTGRES_USER:'postgres',
  POSTGRES_PASSWORD:'a'.repeat(48),BACKEND_DB_PASSWORD:'b'.repeat(48),AGENT_DB_PASSWORD:'c'.repeat(48),
  ADMIN_DATABASE_URL:`postgresql://postgres:${'a'.repeat(48)}@127.0.0.1:5432/app_test`,
  BACKEND_DATABASE_URL:`postgresql://app_backend:${'b'.repeat(48)}@127.0.0.1:5432/app_test`,
  AGENT_DATABASE_URL:`postgresql://app_agent:${'c'.repeat(48)}@127.0.0.1:5432/app_test`,
  DATA_ENCRYPTION_KEY:Buffer.alloc(32,1).toString('base64'),EMAIL_LOOKUP_KEY:Buffer.alloc(32,2).toString('base64'),
  BOOTSTRAP_ADMIN_EMAIL:'admin@local.test',
});
test('valid local config and separated runtime keys', () => {
  assert.doesNotThrow(() => validateConfig(valid()));
  assert.deepEqual(agentKeys,['AGENT_DATABASE_URL']);
  assert.ok(!backendKeys.includes('ADMIN_DATABASE_URL') && !backendKeys.includes('AGENT_DATABASE_URL'));
});
test('rejects unsafe or inconsistent settings without leaking values', () => {
  const changes = [
    {PGPORT:'12oops'}, {DATA_ENCRYPTION_KEY:'not-a-key'},
    {PGDATABASE:'another_db'}, {EMAIL_LOOKUP_KEY:Buffer.alloc(32,1).toString('base64')},
    {BACKEND_DATABASE_URL:'postgresql://postgres:TOP_SECRET@127.0.0.1:5432/app_test'},
  ];
  for (const change of changes) {
    assert.throws(() => validateConfig({...valid(),...change}), error => !error.message.includes('TOP_SECRET'));
  }
});
test('requires verified TLS for remote databases', () => {
  const c=valid();c.PGHOST='db.example.test';
  for(const key of ['ADMIN_DATABASE_URL','BACKEND_DATABASE_URL','AGENT_DATABASE_URL']) c[key]=c[key].replace('127.0.0.1','db.example.test');
  assert.throws(()=>validateConfig(c),/verify-full/);
  for(const key of ['ADMIN_DATABASE_URL','BACKEND_DATABASE_URL','AGENT_DATABASE_URL']) c[key]+='?sslmode=verify-full';
  assert.doesNotThrow(()=>validateConfig(c));
});
