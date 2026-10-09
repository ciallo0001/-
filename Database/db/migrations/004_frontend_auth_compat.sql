-- Frontend authentication compatibility.
-- The web client sends an account identifier and expects a Bearer token.
-- Existing email/cookie authentication remains supported by the service.

ALTER TABLE app.users
  ADD COLUMN login_account text;

ALTER TABLE app.users
  DROP CONSTRAINT IF EXISTS users_login_account_check;

ALTER TABLE app.users
  ADD CONSTRAINT users_login_account_check
  CHECK (login_account IS NULL OR (login_account = btrim(login_account)
    AND login_account = lower(login_account)
    AND length(login_account) BETWEEN 3 AND 64
    AND login_account !~ '[[:space:]]'));

CREATE UNIQUE INDEX users_login_account_unique
  ON app.users (login_account)
  WHERE login_account IS NOT NULL;

ALTER TABLE app.users
  DROP CONSTRAINT IF EXISTS users_role_check;

UPDATE app.users SET role = 'guest' WHERE role = 'user';

ALTER TABLE app.users
  ALTER COLUMN role SET DEFAULT 'guest';

ALTER TABLE app.users
  ADD CONSTRAINT users_role_check
  CHECK (role IN ('guest', 'student', 'teacher', 'merchant', 'admin'));

ALTER TABLE app.auth_sessions
  ADD COLUMN client_kind text NOT NULL DEFAULT 'browser'
    CHECK (client_kind IN ('browser', 'bearer'));

CREATE INDEX auth_sessions_bearer_idx
  ON app.auth_sessions (user_id, expires_at)
  WHERE client_kind = 'bearer';

COMMENT ON COLUMN app.users.login_account IS
  'Normalized non-secret account identifier used by API clients; email remains encrypted.';
COMMENT ON COLUMN app.auth_sessions.client_kind IS
  'Session transport: browser cookie or API Bearer token.';
