import assert from 'node:assert/strict';
import test from 'node:test';
import { hashPassword, verifyPassword } from '../scripts/password.mjs';

test('bootstrap password hashing verifies correct passwords and rejects wrong ones', async () => {
  const password = 'development-secret-123';
  const encoded = await hashPassword(password);
  assert.ok(!encoded.includes(password));
  assert.equal(await verifyPassword(password, encoded), true);
  assert.equal(await verifyPassword('incorrect-password', encoded), false);
  assert.equal(await verifyPassword(password, 'invalid'), false);
  await assert.rejects(hashPassword('short'));
});
