CREATE SCHEMA app;
REVOKE ALL ON SCHEMA app FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO app_backend, app_agent;

CREATE FUNCTION app.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  NEW.updated_at = clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE FUNCTION app.current_user_id() RETURNS uuid
LANGUAGE sql STABLE SET search_path = pg_catalog AS $$
  SELECT nullif(current_setting('app.user_id', true), '')::uuid;
$$;

CREATE TABLE app.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL CHECK (email = btrim(email) AND length(email) BETWEEN 3 AND 254 AND position('@' in email) > 1),
  password_hash text NOT NULL CHECK (length(password_hash) >= 20),
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 100),
  role text NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  profile jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(profile) = 'object'),
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_unique ON app.users (lower(email));
CREATE INDEX users_role_idx ON app.users (role);

CREATE TABLE app.agent_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  agent_key text NOT NULL DEFAULT 'default' CHECK (length(btrim(agent_key)) BETWEEN 1 AND 100),
  title text NOT NULL DEFAULT '',
  summary text NOT NULL DEFAULT '',
  context jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(context) = 'object'),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, user_id)
);
CREATE INDEX agent_sessions_user_idx ON app.agent_sessions (user_id, agent_key, updated_at DESC);

CREATE TABLE app.agent_messages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  session_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('system', 'user', 'assistant', 'tool')),
  content text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (session_id, user_id) REFERENCES app.agent_sessions(id, user_id) ON DELETE CASCADE
);
CREATE INDEX agent_messages_session_idx ON app.agent_messages (session_id, id);
CREATE INDEX agent_messages_user_idx ON app.agent_messages (user_id);

CREATE TABLE app.agent_memories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  agent_key text NOT NULL DEFAULT 'default' CHECK (length(btrim(agent_key)) BETWEEN 1 AND 100),
  memory_key text NOT NULL CHECK (length(btrim(memory_key)) BETWEEN 1 AND 200),
  kind text NOT NULL DEFAULT 'fact' CHECK (kind IN ('fact', 'preference', 'summary', 'task')),
  content text NOT NULL CHECK (length(btrim(content)) > 0),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  importance smallint NOT NULL DEFAULT 50 CHECK (importance BETWEEN 0 AND 100),
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, agent_key, memory_key)
);
CREATE INDEX agent_memories_recall_idx ON app.agent_memories (user_id, agent_key, importance DESC, updated_at DESC);
CREATE INDEX agent_memories_expiry_idx ON app.agent_memories (expires_at) WHERE expires_at IS NOT NULL;

CREATE TRIGGER users_updated_at BEFORE UPDATE ON app.users FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER sessions_updated_at BEFORE UPDATE ON app.agent_sessions FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER memories_updated_at BEFORE UPDATE ON app.agent_memories FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

ALTER TABLE app.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.users FORCE ROW LEVEL SECURITY;
ALTER TABLE app.agent_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.agent_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE app.agent_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.agent_messages FORCE ROW LEVEL SECURITY;
ALTER TABLE app.agent_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.agent_memories FORCE ROW LEVEL SECURITY;

CREATE POLICY backend_users ON app.users TO app_backend USING (true) WITH CHECK (true);
CREATE POLICY backend_sessions ON app.agent_sessions TO app_backend USING (true) WITH CHECK (true);
CREATE POLICY backend_messages ON app.agent_messages TO app_backend USING (true) WITH CHECK (true);
CREATE POLICY backend_memories ON app.agent_memories TO app_backend USING (true) WITH CHECK (true);
CREATE POLICY agent_user_profile ON app.users FOR SELECT TO app_agent
  USING (id = app.current_user_id() AND status = 'active');
CREATE POLICY agent_sessions_own ON app.agent_sessions TO app_agent
  USING (user_id = app.current_user_id() AND EXISTS (SELECT 1 FROM app.users WHERE id = app.current_user_id()))
  WITH CHECK (user_id = app.current_user_id() AND EXISTS (SELECT 1 FROM app.users WHERE id = app.current_user_id()));
CREATE POLICY agent_messages_own ON app.agent_messages TO app_agent
  USING (user_id = app.current_user_id() AND EXISTS (SELECT 1 FROM app.users WHERE id = app.current_user_id()))
  WITH CHECK (user_id = app.current_user_id() AND EXISTS (SELECT 1 FROM app.users WHERE id = app.current_user_id()));
CREATE POLICY agent_memories_own ON app.agent_memories TO app_agent
  USING (user_id = app.current_user_id() AND EXISTS (SELECT 1 FROM app.users WHERE id = app.current_user_id()))
  WITH CHECK (user_id = app.current_user_id() AND EXISTS (SELECT 1 FROM app.users WHERE id = app.current_user_id()));

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.current_user_id() TO app_backend, app_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_backend;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_backend, app_agent;
GRANT SELECT (id, email, display_name, role, status, profile, created_at, updated_at) ON app.users TO app_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON app.agent_sessions, app.agent_messages, app.agent_memories TO app_agent;

COMMENT ON TABLE app.users IS 'Application users. user/admin are business roles, not PostgreSQL login roles.';
COMMENT ON COLUMN app.users.password_hash IS 'Encoded password hash only; never a plaintext password.';
COMMENT ON COLUMN app.agent_sessions.context IS 'Short-term structured context for one agent conversation.';
COMMENT ON TABLE app.agent_memories IS 'Long-term per-user, per-agent memory; recall must exclude expired rows.';
