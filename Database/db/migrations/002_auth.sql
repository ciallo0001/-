ALTER TABLE app.users ADD COLUMN email_ciphertext bytea;
ALTER TABLE app.users ADD COLUMN email_lookup bytea;
ALTER TABLE app.users ADD COLUMN private_profile_ciphertext bytea;
ALTER TABLE app.users ADD CONSTRAINT users_email_lookup_length CHECK (octet_length(email_lookup) = 32);
CREATE UNIQUE INDEX users_email_lookup_unique ON app.users(email_lookup);
REVOKE SELECT (email) ON app.users FROM app_agent;

CREATE TABLE app.auth_sessions (
  token_hash bytea PRIMARY KEY CHECK (octet_length(token_hash) = 32),
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  csrf_token text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  CHECK (expires_at > created_at)
);
CREATE INDEX auth_sessions_user_idx ON app.auth_sessions(user_id);
CREATE INDEX auth_sessions_expiry_idx ON app.auth_sessions(expires_at);
ALTER TABLE app.auth_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.auth_sessions FORCE ROW LEVEL SECURITY;
CREATE POLICY backend_auth_sessions ON app.auth_sessions TO app_backend USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON app.auth_sessions TO app_backend;

CREATE TABLE app.crypto_settings (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  encryption_check bytea NOT NULL,
  lookup_check bytea NOT NULL
);
GRANT SELECT ON app.crypto_settings TO app_backend;

COMMENT ON COLUMN app.users.email IS 'Non-sensitive surrogate address. Real email is stored in email_ciphertext.';
COMMENT ON COLUMN app.users.email_lookup IS 'HMAC-SHA256 of normalized email, using a separate secret key.';
COMMENT ON COLUMN app.users.private_profile_ciphertext IS 'AES-256-GCM: version byte, nonce, ciphertext, tag. AAD binds user and field.';
COMMENT ON TABLE app.auth_sessions IS 'Only SHA-256 of the browser session token is stored.';
