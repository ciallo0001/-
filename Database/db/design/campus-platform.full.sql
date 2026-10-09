-- GENERATED complete campus database design. PostgreSQL 18.
-- Build: node scripts/build-campus-ddl.mjs
-- ONLY execute on a NEW EMPTY database as the postgres migration account.
-- Do not execute on the current app_dev database. Do not run db:init on this design database.
-- Existing cluster service roles are reused without changing passwords or role memberships.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_backend') THEN
    CREATE ROLE app_backend NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_agent') THEN
    CREATE ROLE app_agent NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
END $$;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- SOURCE: db/migrations/001_initial.sql
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


-- SOURCE: db/migrations/002_auth.sql
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


-- SOURCE: db/migrations/003_revoke_sessions.sql
CREATE FUNCTION app.revoke_user_sessions() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF NEW.password_hash IS DISTINCT FROM OLD.password_hash
     OR (NEW.status = 'disabled' AND OLD.status IS DISTINCT FROM NEW.status) THEN
    DELETE FROM app.auth_sessions WHERE user_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION app.revoke_user_sessions() FROM PUBLIC;
CREATE TRIGGER users_revoke_sessions AFTER UPDATE OF password_hash, status ON app.users
FOR EACH ROW EXECUTE FUNCTION app.revoke_user_sessions();


-- SOURCE: db/migrations/004_frontend_auth_compat.sql
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


-- SOURCE: db/migrations/005_campus_platform.sql
-- Campus comprehensive service platform schema.
-- Campus business schema applied after the frontend authentication compatibility migration.
-- Requires migrations 001-004. Transaction is controlled by the migration runner.

-- Existing unverified user accounts become guest; do not infer student identity.
-- Visitors browse anonymously or use guest_sessions; unverified accounts use the guest role.
ALTER TABLE app.users DROP CONSTRAINT IF EXISTS users_role_check;
UPDATE app.users SET role = 'guest' WHERE role = 'user';
ALTER TABLE app.users ALTER COLUMN role SET DEFAULT 'guest';
ALTER TABLE app.users ADD CONSTRAINT users_role_check
  CHECK (role IN ('guest', 'student', 'teacher', 'merchant', 'admin'));




CREATE TABLE app.campus_pages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL CHECK (slug = lower(btrim(slug)) AND slug ~ '^[a-z0-9][a-z0-9-]{0,119}$'),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 200),
  summary text NOT NULL DEFAULT '',
  content jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(content) = 'object'),
  audience text NOT NULL DEFAULT 'all' CHECK (audience IN ('all', 'freshman', 'high_school', 'student', 'teacher')),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
  author_id uuid REFERENCES app.users(id) ON DELETE SET NULL,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (slug)
);
CREATE INDEX campus_pages_public_idx ON app.campus_pages(status, published_at DESC) WHERE status = 'published';

CREATE TABLE app.identity_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  identity_type text NOT NULL CHECK (identity_type IN ('student', 'teacher')),
  real_name_ciphertext bytea NOT NULL,
  credential_lookup bytea NOT NULL CHECK (octet_length(credential_lookup) = 32),
  provider text NOT NULL DEFAULT 'manual' CHECK (length(btrim(provider)) BETWEEN 1 AND 80),
  provider_subject_hash bytea CHECK (provider_subject_hash IS NULL OR octet_length(provider_subject_hash) = 32),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'rejected', 'expired')),
  rejection_reason text NOT NULL DEFAULT '',
  verified_by uuid REFERENCES app.users(id) ON DELETE SET NULL,
  verified_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'verified' OR (verified_at IS NOT NULL AND (provider <> 'manual' OR verified_by IS NOT NULL))),
  CHECK (expires_at IS NULL OR (verified_at IS NOT NULL AND expires_at > verified_at)),
  UNIQUE (user_id, identity_type),
  UNIQUE (identity_type, credential_lookup)
);
CREATE INDEX identity_verifications_status_idx ON app.identity_verifications(status, created_at DESC);

CREATE TABLE app.student_profiles (
  user_id uuid PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
  student_no_ciphertext bytea NOT NULL,
  student_no_lookup bytea NOT NULL CHECK (octet_length(student_no_lookup) = 32),
  college text NOT NULL DEFAULT '',
  major text NOT NULL DEFAULT '',
  grade smallint CHECK (grade BETWEEN 1 AND 9),
  class_name text NOT NULL DEFAULT '',
  enrollment_status text NOT NULL DEFAULT 'enrolled' CHECK (enrollment_status IN ('enrolled', 'leave', 'graduated', 'withdrawn')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (student_no_lookup)
);

CREATE TABLE app.teacher_profiles (
  user_id uuid PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
  employee_no_ciphertext bytea NOT NULL,
  employee_no_lookup bytea NOT NULL CHECK (octet_length(employee_no_lookup) = 32),
  college text NOT NULL DEFAULT '',
  title text NOT NULL DEFAULT '',
  employment_status text NOT NULL DEFAULT 'active' CHECK (employment_status IN ('active', 'leave', 'retired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (employee_no_lookup)
);

CREATE TABLE app.academic_terms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE CHECK (code = btrim(code) AND length(code) BETWEEN 2 AND 40),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 100),
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  status text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'active', 'closed')),
  CHECK (ends_on >= starts_on)
);

CREATE TABLE app.courses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE CHECK (code = upper(btrim(code)) AND length(code) BETWEEN 2 AND 40),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 200),
  credits numeric(4,1) NOT NULL DEFAULT 0 CHECK (credits >= 0 AND credits <= 99),
  description text NOT NULL DEFAULT '',
  college text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.class_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  term_id uuid NOT NULL REFERENCES app.academic_terms(id) ON DELETE RESTRICT,
  course_id uuid NOT NULL REFERENCES app.courses(id) ON DELETE RESTRICT,
  section_code text NOT NULL CHECK (length(btrim(section_code)) BETWEEN 1 AND 40),
  capacity integer CHECK (capacity IS NULL OR capacity > 0),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'cancelled')),
  UNIQUE (term_id, course_id, section_code),
  UNIQUE (id, term_id)
);

CREATE TABLE app.section_teachers (
  section_id uuid NOT NULL REFERENCES app.class_sections(id) ON DELETE CASCADE,
  teacher_id uuid NOT NULL REFERENCES app.teacher_profiles(user_id) ON DELETE RESTRICT,
  is_primary boolean NOT NULL DEFAULT false,
  PRIMARY KEY (section_id, teacher_id)
);
CREATE UNIQUE INDEX section_primary_teacher_unique ON app.section_teachers(section_id) WHERE is_primary;

CREATE TABLE app.student_enrollments (
  section_id uuid NOT NULL REFERENCES app.class_sections(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES app.student_profiles(user_id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'enrolled' CHECK (status IN ('enrolled', 'dropped', 'completed')),
  enrolled_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (section_id, student_id)
);

CREATE TABLE app.class_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  section_id uuid NOT NULL REFERENCES app.class_sections(id) ON DELETE CASCADE,
  weekday smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7),
  start_period smallint NOT NULL CHECK (start_period > 0),
  period_count smallint NOT NULL CHECK (period_count > 0),
  week_start smallint NOT NULL DEFAULT 1 CHECK (week_start > 0),
  week_end smallint NOT NULL DEFAULT 20 CHECK (week_end >= week_start),
  location text NOT NULL DEFAULT '',
  week_pattern text NOT NULL DEFAULT 'all' CHECK (week_pattern IN ('all','odd','even')),
  CHECK (start_period + period_count <= 25),
  CHECK (week_end <= 60),
  UNIQUE (section_id, weekday, start_period, week_start, week_end, week_pattern)
);

CREATE TABLE app.exams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  section_id uuid NOT NULL REFERENCES app.class_sections(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 200),
  exam_type text NOT NULL DEFAULT 'final' CHECK (exam_type IN ('quiz', 'midterm', 'final', 'other')),
  starts_at timestamptz NOT NULL,
  location text NOT NULL DEFAULT '',
  total_score numeric(6,2) NOT NULL DEFAULT 100 CHECK (total_score > 0),
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'finished', 'cancelled')),
  UNIQUE (id, section_id)
);

CREATE TABLE app.exam_scores (
  exam_id uuid NOT NULL,
  section_id uuid NOT NULL,
  student_id uuid NOT NULL,
  score numeric(7,2) NOT NULL CHECK (score >= 0),
  grade text NOT NULL DEFAULT '',
  feedback text NOT NULL DEFAULT '',
  published_at timestamptz,
  entered_by uuid REFERENCES app.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (exam_id, student_id),
  FOREIGN KEY (exam_id, section_id) REFERENCES app.exams(id, section_id) ON DELETE CASCADE,
  FOREIGN KEY (section_id, student_id) REFERENCES app.student_enrollments(section_id, student_id) ON DELETE CASCADE
);

CREATE TABLE app.stores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  store_type text NOT NULL CHECK (store_type IN ('campus_store', 'snack_street')),
  description text NOT NULL DEFAULT '',
  location text NOT NULL DEFAULT '',
  owner_id uuid REFERENCES app.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'suspended')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id uuid NOT NULL REFERENCES app.stores(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 200),
  description text NOT NULL DEFAULT '',
  image_url text NOT NULL DEFAULT '',
  price_cents integer NOT NULL CHECK (price_cents >= 0),
  stock_quantity integer NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
  status text NOT NULL DEFAULT 'on_sale' CHECK (status IN ('draft', 'on_sale', 'sold_out', 'off_shelf')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, store_id)
);
CREATE INDEX products_store_public_idx ON app.products(store_id, status) WHERE status = 'on_sale';

CREATE TABLE app.shop_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  store_id uuid NOT NULL REFERENCES app.stores(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'preparing', 'ready', 'completed', 'cancelled', 'refunded')),
  payment_status text NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'paid', 'refunded')),
  total_cents bigint NOT NULL CHECK (total_cents >= 0),
  currency text NOT NULL DEFAULT 'CNY' CHECK (currency = 'CNY'),
  request_key uuid NOT NULL,
  UNIQUE (buyer_id, request_key),
  delivery_address_ciphertext bytea,
  contact_phone_ciphertext bytea,
  note text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, store_id)
);
CREATE INDEX shop_orders_buyer_idx ON app.shop_orders(buyer_id, created_at DESC);
CREATE INDEX shop_orders_store_idx ON app.shop_orders(store_id, created_at DESC);

CREATE TABLE app.shop_order_items (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id uuid NOT NULL,
  store_id uuid NOT NULL,
  product_id uuid NOT NULL,
  product_name_snapshot text NOT NULL,
  unit_price_cents integer NOT NULL CHECK (unit_price_cents >= 0),
  quantity integer NOT NULL CHECK (quantity > 0 AND quantity <= 999),
  FOREIGN KEY (order_id, store_id) REFERENCES app.shop_orders(id, store_id) ON DELETE CASCADE,
  FOREIGN KEY (product_id, store_id) REFERENCES app.products(id, store_id) ON DELETE RESTRICT
);

CREATE TABLE app.errand_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publisher_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  accepted_runner_id uuid REFERENCES app.users(id) ON DELETE RESTRICT,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 160),
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 1 AND 4000),
  pickup_location_ciphertext bytea NOT NULL,
  dropoff_location_ciphertext bytea NOT NULL,
  contact_ciphertext bytea,
  reward_cents integer NOT NULL DEFAULT 0 CHECK (reward_cents >= 0),
  public_area text NOT NULL DEFAULT '',
  request_key uuid NOT NULL,
  UNIQUE (publisher_id, request_key),
  deadline_at timestamptz,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'assigned', 'in_progress', 'completed', 'cancelled', 'expired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (accepted_runner_id IS NULL OR accepted_runner_id <> publisher_id),
  CHECK ((status IN ('assigned','in_progress','completed') AND accepted_runner_id IS NOT NULL) OR (status IN ('open','cancelled','expired') AND accepted_runner_id IS NULL)),
  CHECK (deadline_at IS NULL OR deadline_at > created_at)
);
CREATE INDEX errand_tasks_public_idx ON app.errand_tasks(status, created_at DESC) WHERE status = 'open';
CREATE INDEX errand_tasks_publisher_idx ON app.errand_tasks(publisher_id, created_at DESC);
CREATE INDEX errand_tasks_runner_idx ON app.errand_tasks(accepted_runner_id, created_at DESC);

CREATE TABLE app.errand_offers (
  task_id uuid NOT NULL REFERENCES app.errand_tasks(id) ON DELETE CASCADE,
  runner_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  message text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'withdrawn')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (task_id, runner_id)
);

CREATE TABLE app.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL DEFAULT 'direct' CHECK (kind = 'direct'),
  created_by uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  participant_a uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  participant_b uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  CHECK (participant_a < participant_b),
  CHECK (created_by IN (participant_a, participant_b)),
  UNIQUE (participant_a, participant_b),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.conversation_members (
  conversation_id uuid NOT NULL REFERENCES app.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  last_read_at timestamptz,
  left_at timestamptz,
  PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE app.direct_messages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  conversation_id uuid NOT NULL REFERENCES app.conversations(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  body_ciphertext bytea NOT NULL,
  message_type text NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file')),
  sent_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  client_message_id uuid NOT NULL,
  UNIQUE (sender_id, client_message_id),
  FOREIGN KEY (conversation_id, sender_id) REFERENCES app.conversation_members(conversation_id,user_id) ON DELETE RESTRICT
);
CREATE INDEX direct_messages_conversation_idx ON app.direct_messages(conversation_id, id);

CREATE TABLE app.wall_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  title text NOT NULL DEFAULT '',
  content text NOT NULL CHECK (length(btrim(content)) BETWEEN 1 AND 10000),
  is_anonymous boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'published', 'hidden', 'deleted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX wall_posts_public_idx ON app.wall_posts(status, created_at DESC) WHERE status = 'published';

CREATE TABLE app.wall_comments (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  post_id uuid NOT NULL REFERENCES app.wall_posts(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  content text NOT NULL CHECK (length(btrim(content)) BETWEEN 1 AND 3000),
  is_anonymous boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'published', 'hidden', 'deleted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX wall_comments_post_idx ON app.wall_comments(post_id, created_at);

CREATE TABLE app.wall_reports (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reporter_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  post_id uuid REFERENCES app.wall_posts(id) ON DELETE CASCADE,
  comment_id bigint REFERENCES app.wall_comments(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 1000),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewing', 'resolved', 'rejected')),
  handled_by uuid REFERENCES app.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((post_id IS NOT NULL) <> (comment_id IS NOT NULL))
);

CREATE TABLE app.audit_logs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id uuid REFERENCES app.users(id) ON DELETE SET NULL,
  action text NOT NULL CHECK (length(btrim(action)) BETWEEN 1 AND 120),
  resource_type text NOT NULL CHECK (length(btrim(resource_type)) BETWEEN 1 AND 80),
  resource_id text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  ip_hash bytea,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_actor_idx ON app.audit_logs(actor_id, created_at DESC);
CREATE INDEX audit_logs_resource_idx ON app.audit_logs(resource_type, resource_id, created_at DESC);

-- Verification attempts are append-only evidence, separate from the current identity binding.
CREATE TABLE app.identity_verification_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  requested_role text NOT NULL CHECK (requested_role IN ('student','teacher')),
  provider text NOT NULL,
  provider_request_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('pending','passed','failed','cancelled')),
  verified_subject_hash bytea CHECK (octet_length(verified_subject_hash)=32),
  evidence_reference_ciphertext bytea,
  failure_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  CHECK ((status='pending') = (completed_at IS NULL)),
  UNIQUE (provider,provider_request_id)
);

CREATE TABLE app.store_staff (
  store_id uuid NOT NULL REFERENCES app.stores(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  staff_role text NOT NULL CHECK (staff_role IN ('manager','clerk')),
  active boolean NOT NULL DEFAULT true,
  PRIMARY KEY (store_id,user_id)
);

CREATE TABLE app.order_status_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id uuid NOT NULL REFERENCES app.shop_orders(id) ON DELETE RESTRICT,
  actor_id uuid REFERENCES app.users(id) ON DELETE SET NULL,
  from_status text,
  to_status text NOT NULL CHECK (to_status IN ('pending','confirmed','preparing','ready','completed','cancelled','refunded')),
  reason text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.errand_status_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  task_id uuid NOT NULL REFERENCES app.errand_tasks(id) ON DELETE RESTRICT,
  actor_id uuid REFERENCES app.users(id) ON DELETE SET NULL,
  from_status text,
  to_status text NOT NULL CHECK (to_status IN ('open','assigned','in_progress','completed','cancelled','expired')),
  reason text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- One payment targets exactly one shop order or errand. No card/bank credentials.
CREATE TABLE app.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid REFERENCES app.shop_orders(id) ON DELETE RESTRICT,
  task_id uuid REFERENCES app.errand_tasks(id) ON DELETE RESTRICT,
  payer_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  amount_cents bigint NOT NULL CHECK (amount_cents > 0),
  currency text NOT NULL DEFAULT 'CNY' CHECK (currency='CNY'),
  provider text NOT NULL CHECK (provider IN ('wechat','alipay','offline')),
  provider_transaction_id text,
  request_key uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','succeeded','failed','closed','refunded')),
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((order_id IS NOT NULL) <> (task_id IS NOT NULL)),
  CHECK (status NOT IN ('succeeded','refunded') OR paid_at IS NOT NULL),
  UNIQUE (payer_id,request_key),
  UNIQUE (provider,provider_transaction_id)
);
CREATE UNIQUE INDEX payment_order_paid_unique ON app.payments(order_id) WHERE status IN ('succeeded','refunded');
CREATE UNIQUE INDEX payment_task_paid_unique ON app.payments(task_id) WHERE status IN ('succeeded','refunded');

CREATE TABLE app.payment_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id uuid NOT NULL REFERENCES app.payments(id) ON DELETE RESTRICT,
  provider text NOT NULL,
  event_id text NOT NULL,
  payload_digest bytea NOT NULL CHECK (octet_length(payload_digest)=32),
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  UNIQUE (provider,event_id)
);

CREATE TABLE app.refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES app.payments(id) ON DELETE RESTRICT,
  request_key uuid NOT NULL UNIQUE,
  amount_cents bigint NOT NULL CHECK (amount_cents > 0),
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','succeeded','failed')),
  provider_refund_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  refunded_at timestamptz,
  CHECK (status<>'succeeded' OR refunded_at IS NOT NULL)
);

CREATE TABLE app.user_blocks (
  blocker_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(blocker_id,blocked_id),
  CHECK(blocker_id<>blocked_id)
);
ALTER TABLE app.errand_tasks ADD CONSTRAINT accepted_offer_exists FOREIGN KEY(id,accepted_runner_id)
  REFERENCES app.errand_offers(task_id,runner_id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE app.guest_sessions (
  token_hash bytea PRIMARY KEY CHECK(octet_length(token_hash)=32),
  client_kind text NOT NULL CHECK(client_kind IN ('web','ios','android')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  CHECK(expires_at>created_at)
);
ALTER TABLE app.identity_verifications ADD CONSTRAINT verification_user_pair UNIQUE(id,user_id);
ALTER TABLE app.auth_sessions ADD COLUMN authenticated_identity_id uuid;
ALTER TABLE app.auth_sessions ADD COLUMN identity_authenticated_at timestamptz;
ALTER TABLE app.auth_sessions ADD COLUMN identity_valid_until timestamptz;
ALTER TABLE app.auth_sessions ADD CONSTRAINT auth_verified_owner FOREIGN KEY(authenticated_identity_id,user_id)
  REFERENCES app.identity_verifications(id,user_id) ON DELETE RESTRICT;
ALTER TABLE app.auth_sessions ADD CONSTRAINT auth_identity_proof CHECK(
  (authenticated_identity_id IS NULL AND identity_authenticated_at IS NULL AND identity_valid_until IS NULL)
  OR (authenticated_identity_id IS NOT NULL AND identity_authenticated_at IS NOT NULL AND identity_valid_until IS NOT NULL
      AND identity_valid_until>identity_authenticated_at AND identity_valid_until<=expires_at)
);

CREATE INDEX enrollments_student_idx ON app.student_enrollments(student_id,section_id);
CREATE INDEX section_teachers_user_idx ON app.section_teachers(teacher_id,section_id);
CREATE INDEX scores_student_idx ON app.exam_scores(student_id,exam_id);
CREATE INDEX schedules_section_idx ON app.class_schedules(section_id);
CREATE INDEX exams_section_idx ON app.exams(section_id);
CREATE INDEX order_items_order_idx ON app.shop_order_items(order_id);
CREATE INDEX members_user_idx ON app.conversation_members(user_id,conversation_id);
CREATE INDEX offers_runner_idx ON app.errand_offers(runner_id,task_id);
CREATE UNIQUE INDEX offers_one_accepted_idx ON app.errand_offers(task_id) WHERE status='accepted';
CREATE INDEX payment_order_idx ON app.payments(order_id);
CREATE INDEX payment_task_idx ON app.payments(task_id);
CREATE INDEX refunds_payment_idx ON app.refunds(payment_id);
CREATE INDEX status_order_idx ON app.order_status_events(order_id,id);
CREATE INDEX status_task_idx ON app.errand_status_events(task_id,id);
CREATE INDEX attempts_user_idx ON app.identity_verification_attempts(user_id,created_at DESC);

-- Maintain updated_at consistently for mutable records.
CREATE TRIGGER campus_pages_updated_at BEFORE UPDATE ON app.campus_pages FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER identity_verifications_updated_at BEFORE UPDATE ON app.identity_verifications FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER student_profiles_updated_at BEFORE UPDATE ON app.student_profiles FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER teacher_profiles_updated_at BEFORE UPDATE ON app.teacher_profiles FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER courses_updated_at BEFORE UPDATE ON app.courses FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER stores_updated_at BEFORE UPDATE ON app.stores FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER products_updated_at BEFORE UPDATE ON app.products FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER shop_orders_updated_at BEFORE UPDATE ON app.shop_orders FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER errand_tasks_updated_at BEFORE UPDATE ON app.errand_tasks FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER errand_offers_updated_at BEFORE UPDATE ON app.errand_offers FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER wall_posts_updated_at BEFORE UPDATE ON app.wall_posts FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER wall_comments_updated_at BEFORE UPDATE ON app.wall_comments FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Trusted service supplies only app.user_id from authentication. Role and verification
-- are ALWAYS read from persisted data; client-controlled app.user_role is ignored.
-- These narrowly scoped SECURITY DEFINER helpers must be owned by the migration owner,
-- never app_backend/app_agent. This project uses its postgres migration account.
CREATE FUNCTION app.request_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT u.role FROM app.users u JOIN app.auth_sessions s ON s.user_id=u.id
  WHERE u.id=app.current_user_id() AND u.status='active' AND s.expires_at>now()
    AND s.token_hash=CASE WHEN current_setting('app.session_hash',true) ~ '^[0-9a-f]{64}$'
      THEN decode(current_setting('app.session_hash',true),'hex') ELSE NULL::bytea END;
$$;
CREATE FUNCTION app.request_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT coalesce(app.request_role()='admin',false);
$$;
CREATE FUNCTION app.request_verified() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT EXISTS (SELECT 1 FROM app.users u JOIN app.identity_verifications v ON v.user_id=u.id
    JOIN app.auth_sessions s ON s.user_id=u.id AND s.authenticated_identity_id=v.id
    WHERE u.id=app.current_user_id() AND u.status='active' AND u.role IN ('student','teacher')
    AND v.identity_type=u.role AND v.status='verified' AND v.verified_at<=now()
    AND s.expires_at>now() AND s.identity_authenticated_at<=now() AND s.identity_valid_until>now()
    AND s.token_hash=CASE WHEN current_setting('app.session_hash',true) ~ '^[0-9a-f]{64}$'
      THEN decode(current_setting('app.session_hash',true),'hex') ELSE NULL::bytea END
    AND (v.expires_at IS NULL OR v.expires_at>now()));
$$;
CREATE FUNCTION app.request_enrolled(target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT app.request_verified() AND app.request_role()='student' AND EXISTS (
    SELECT 1 FROM app.student_enrollments WHERE section_id=target
    AND student_id=app.current_user_id() AND status IN ('enrolled','completed'));
$$;
CREATE FUNCTION app.request_teaches(target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT app.request_verified() AND app.request_role()='teacher' AND EXISTS (
    SELECT 1 FROM app.section_teachers WHERE section_id=target AND teacher_id=app.current_user_id());
$$;
CREATE FUNCTION app.request_store_staff(target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT app.request_verified() AND (EXISTS (SELECT 1 FROM app.stores WHERE id=target AND owner_id=app.current_user_id())
    OR EXISTS (SELECT 1 FROM app.store_staff WHERE store_id=target AND user_id=app.current_user_id() AND active));
$$;
CREATE FUNCTION app.request_order(target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT app.request_admin() OR (app.request_verified() AND EXISTS (SELECT 1 FROM app.shop_orders
    WHERE id=target AND (buyer_id=app.current_user_id() OR app.request_store_staff(store_id))));
$$;
CREATE FUNCTION app.request_task(target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT app.request_admin() OR (app.request_verified() AND EXISTS (SELECT 1 FROM app.errand_tasks
    WHERE id=target AND (publisher_id=app.current_user_id() OR accepted_runner_id=app.current_user_id())));
$$;
CREATE FUNCTION app.request_conversation(target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT app.request_verified() AND EXISTS (SELECT 1 FROM app.conversation_members m
    JOIN app.conversations c ON c.id=m.conversation_id WHERE m.conversation_id=target
    AND m.user_id=app.current_user_id() AND m.left_at IS NULL
    AND app.current_user_id() IN (c.participant_a,c.participant_b));
$$;

-- Cross-table consistency belongs in triggers, not CHECK subqueries (unsupported by PostgreSQL).
CREATE FUNCTION app.enforce_campus_identity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE target uuid; actual_role text;
BEGIN
  IF TG_TABLE_NAME='users' THEN target:=NEW.id; ELSE target:=NEW.user_id; END IF;
  SELECT role INTO actual_role FROM app.users WHERE id=target;
  IF EXISTS (SELECT 1 FROM app.identity_verifications WHERE user_id=target AND status='verified' AND identity_type<>actual_role)
    OR (EXISTS (SELECT 1 FROM app.student_profiles WHERE user_id=target) AND actual_role<>'student')
    OR (EXISTS (SELECT 1 FROM app.teacher_profiles WHERE user_id=target) AND actual_role<>'teacher') THEN
    RAISE EXCEPTION 'Campus role and identity/profile mismatch' USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER campus_identity_consistency AFTER INSERT OR UPDATE ON app.identity_verifications
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app.enforce_campus_identity();
CREATE CONSTRAINT TRIGGER student_identity_consistency AFTER INSERT OR UPDATE ON app.student_profiles
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app.enforce_campus_identity();
CREATE CONSTRAINT TRIGGER teacher_identity_consistency AFTER INSERT OR UPDATE ON app.teacher_profiles
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app.enforce_campus_identity();
CREATE CONSTRAINT TRIGGER user_identity_consistency AFTER UPDATE ON app.users
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app.enforce_campus_identity();

CREATE FUNCTION app.enforce_score() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE maximum numeric;
BEGIN
  SELECT total_score INTO maximum FROM app.exams WHERE id=NEW.exam_id FOR SHARE;
  IF NEW.score>maximum THEN RAISE EXCEPTION 'Score exceeds exam maximum' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER score_bound BEFORE INSERT OR UPDATE ON app.exam_scores FOR EACH ROW EXECUTE FUNCTION app.enforce_score();
CREATE FUNCTION app.enforce_exam_maximum() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM app.exam_scores WHERE exam_id=NEW.id AND score>NEW.total_score) THEN
    RAISE EXCEPTION 'Exam maximum below existing score' USING ERRCODE='23514';
  END IF; RETURN NEW;
END $$;
CREATE TRIGGER exam_bound BEFORE UPDATE OF total_score ON app.exams FOR EACH ROW EXECUTE FUNCTION app.enforce_exam_maximum();

CREATE FUNCTION app.enforce_direct_member() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM app.conversations WHERE id=NEW.conversation_id AND NEW.user_id IN (participant_a,participant_b)) THEN
    RAISE EXCEPTION 'User is not one of the two conversation participants' USING ERRCODE='23514';
  END IF; RETURN NEW;
END $$;
CREATE TRIGGER direct_member_pair BEFORE INSERT OR UPDATE ON app.conversation_members FOR EACH ROW EXECUTE FUNCTION app.enforce_direct_member();
CREATE FUNCTION app.lock_conversation_pair() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  IF (NEW.participant_a,NEW.participant_b,NEW.created_by) IS DISTINCT FROM (OLD.participant_a,OLD.participant_b,OLD.created_by) THEN
    RAISE EXCEPTION 'Conversation participants are immutable' USING ERRCODE='23514';
  END IF; RETURN NEW;
END $$;
CREATE TRIGGER direct_pair_immutable BEFORE UPDATE ON app.conversations FOR EACH ROW EXECUTE FUNCTION app.lock_conversation_pair();

CREATE FUNCTION app.guard_message() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM app.conversation_members WHERE conversation_id=NEW.conversation_id AND user_id=NEW.sender_id AND left_at IS NULL) THEN
    RAISE EXCEPTION 'Sender is not an active member' USING ERRCODE='23514';
  END IF;
  IF EXISTS(SELECT 1 FROM app.conversations c JOIN app.user_blocks b
    ON (b.blocker_id=c.participant_a AND b.blocked_id=c.participant_b)
      OR (b.blocker_id=c.participant_b AND b.blocked_id=c.participant_a)
    WHERE c.id=NEW.conversation_id) THEN
    RAISE EXCEPTION 'Messaging is blocked' USING ERRCODE='23514';
  END IF; RETURN NEW;
END $$;
CREATE TRIGGER message_membership BEFORE INSERT ON app.direct_messages FOR EACH ROW EXECUTE FUNCTION app.guard_message();

CREATE FUNCTION app.enforce_errand_assignment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE target uuid; runner uuid; accepted uuid;
BEGIN
  IF TG_TABLE_NAME='errand_tasks' THEN target:=NEW.id;
  ELSIF TG_OP='DELETE' THEN target:=OLD.task_id; ELSE target:=NEW.task_id; END IF;
  SELECT accepted_runner_id INTO runner FROM app.errand_tasks WHERE id=target;
  SELECT runner_id INTO accepted FROM app.errand_offers WHERE task_id=target AND status='accepted';
  IF runner IS DISTINCT FROM accepted THEN
    RAISE EXCEPTION 'Task assignment and accepted offer disagree' USING ERRCODE='23514';
  END IF;
  IF EXISTS(SELECT 1 FROM app.errand_offers o JOIN app.errand_tasks t ON t.id=o.task_id
    WHERE o.task_id=target AND o.runner_id=t.publisher_id) THEN
    RAISE EXCEPTION 'Publisher cannot offer on own task' USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER task_assignment AFTER INSERT OR UPDATE ON app.errand_tasks
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app.enforce_errand_assignment();
CREATE CONSTRAINT TRIGGER offer_assignment AFTER INSERT OR UPDATE OR DELETE ON app.errand_offers
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app.enforce_errand_assignment();

CREATE FUNCTION app.enforce_payment_target() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE expected_user uuid; expected_amount bigint;
BEGIN
  IF NEW.order_id IS NOT NULL THEN
    SELECT buyer_id,total_cents INTO expected_user,expected_amount FROM app.shop_orders WHERE id=NEW.order_id FOR SHARE;
  ELSE
    SELECT publisher_id,reward_cents INTO expected_user,expected_amount FROM app.errand_tasks WHERE id=NEW.task_id FOR SHARE;
  END IF;
  IF expected_user IS NULL OR NEW.payer_id<>expected_user OR NEW.amount_cents<>expected_amount THEN
    RAISE EXCEPTION 'Payment payer or amount does not match target' USING ERRCODE='23514';
  END IF;
  IF TG_OP='UPDATE' AND (NEW.order_id,NEW.task_id,NEW.payer_id,NEW.amount_cents,NEW.provider) IS DISTINCT FROM
    (OLD.order_id,OLD.task_id,OLD.payer_id,OLD.amount_cents,OLD.provider) THEN
    RAISE EXCEPTION 'Payment target is immutable' USING ERRCODE='23514';
  END IF; RETURN NEW;
END $$;
CREATE TRIGGER payment_target BEFORE INSERT OR UPDATE ON app.payments FOR EACH ROW EXECUTE FUNCTION app.enforce_payment_target();
CREATE FUNCTION app.enforce_refund_bound() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE paid bigint; payment_state text; reserved bigint;
BEGIN
  IF TG_OP='UPDATE' AND NEW.payment_id<>OLD.payment_id THEN
    RAISE EXCEPTION 'Refund payment is immutable' USING ERRCODE='23514';
  END IF;
  SELECT amount_cents,status INTO paid,payment_state FROM app.payments WHERE id=NEW.payment_id FOR UPDATE;
  SELECT coalesce(sum(amount_cents),0) INTO reserved FROM app.refunds
    WHERE payment_id=NEW.payment_id AND id<>NEW.id AND status IN ('pending','succeeded');
  IF payment_state NOT IN ('succeeded','refunded') OR
    (NEW.status IN ('pending','succeeded') AND reserved+NEW.amount_cents>paid) THEN
    RAISE EXCEPTION 'Refund requires paid transaction and cannot exceed remaining amount' USING ERRCODE='23514';
  END IF; RETURN NEW;
END $$;
CREATE TRIGGER refund_bound BEFORE INSERT OR UPDATE ON app.refunds FOR EACH ROW EXECUTE FUNCTION app.enforce_refund_bound();

-- New business tables only. Existing login and Agent permissions stay unchanged.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'campus_pages','identity_verifications','identity_verification_attempts','student_profiles','teacher_profiles',
    'academic_terms','courses','class_sections','section_teachers','student_enrollments','class_schedules','exams','exam_scores',
    'stores','store_staff','products','shop_orders','shop_order_items','order_status_events',
    'errand_tasks','errand_offers','errand_status_events','payments','payment_events','refunds',
    'conversations','conversation_members','direct_messages','user_blocks','wall_posts','wall_comments','wall_reports','audit_logs','guest_sessions'
  ] LOOP
    EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('ALTER TABLE app.%I FORCE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON app.%I FROM PUBLIC,app_backend,app_agent',t);
    EXECUTE format('GRANT SELECT ON app.%I TO app_backend',t);
  END LOOP;
END $$;

-- Administrative/catalog mutations, never self-service verification or grading.
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['campus_pages','identity_verifications','student_profiles','teacher_profiles',
    'academic_terms','courses','class_sections','section_teachers','student_enrollments',
    'stores','store_staff','products','shop_orders','shop_order_items','errand_tasks','errand_offers','wall_reports'] LOOP
    EXECUTE format('GRANT INSERT,UPDATE,DELETE ON app.%I TO app_backend',t);
    EXECUTE format('CREATE POLICY admin_insert ON app.%I FOR INSERT TO app_backend WITH CHECK(app.request_admin())',t);
    EXECUTE format('CREATE POLICY admin_update ON app.%I FOR UPDATE TO app_backend USING(app.request_admin()) WITH CHECK(app.request_admin())',t);
    EXECUTE format('CREATE POLICY admin_delete ON app.%I FOR DELETE TO app_backend USING(app.request_admin())',t);
  END LOOP;
END $$;

CREATE POLICY pages_read ON app.campus_pages FOR SELECT TO app_backend USING(app.request_admin() OR (status='published' AND published_at<=now()));
CREATE POLICY verification_read ON app.identity_verifications FOR SELECT TO app_backend USING(app.request_admin() OR (user_id=app.current_user_id() AND app.request_role() IS NOT NULL));
CREATE POLICY verification_attempt_read ON app.identity_verification_attempts FOR SELECT TO app_backend USING(app.request_admin() OR (user_id=app.current_user_id() AND app.request_role() IS NOT NULL));
CREATE POLICY student_read ON app.student_profiles FOR SELECT TO app_backend USING(user_id=app.current_user_id() AND app.request_verified());
CREATE POLICY teacher_read ON app.teacher_profiles FOR SELECT TO app_backend USING(user_id=app.current_user_id() AND app.request_verified());
CREATE POLICY terms_read ON app.academic_terms FOR SELECT TO app_backend USING(app.request_admin() OR app.request_verified());
CREATE POLICY courses_read ON app.courses FOR SELECT TO app_backend USING(app.request_admin() OR app.request_verified());
CREATE POLICY sections_read ON app.class_sections FOR SELECT TO app_backend USING(app.request_admin() OR app.request_enrolled(id) OR app.request_teaches(id));
CREATE POLICY teachers_read ON app.section_teachers FOR SELECT TO app_backend USING(app.request_admin() OR app.request_enrolled(section_id) OR app.request_teaches(section_id));
CREATE POLICY enrollments_read ON app.student_enrollments FOR SELECT TO app_backend USING(app.request_admin() OR (student_id=app.current_user_id() AND app.request_verified()));
CREATE POLICY schedules_read ON app.class_schedules FOR SELECT TO app_backend USING(app.request_enrolled(section_id) OR app.request_teaches(section_id));
CREATE POLICY exams_read ON app.exams FOR SELECT TO app_backend USING(app.request_enrolled(section_id) OR app.request_teaches(section_id));
-- Teachers are deliberately NOT allowed to read student scores by their teacher role.
CREATE POLICY scores_read ON app.exam_scores FOR SELECT TO app_backend USING
  (student_id=app.current_user_id() AND app.request_enrolled(section_id) AND published_at<=now());
CREATE POLICY stores_read ON app.stores FOR SELECT TO app_backend USING(status='open' OR app.request_admin() OR app.request_store_staff(id));
CREATE POLICY staff_read ON app.store_staff FOR SELECT TO app_backend USING(app.request_admin() OR (user_id=app.current_user_id() AND app.request_verified()));
CREATE POLICY products_read ON app.products FOR SELECT TO app_backend USING(app.request_admin() OR app.request_store_staff(store_id) OR
  (status='on_sale' AND EXISTS(SELECT 1 FROM app.stores s WHERE s.id=products.store_id AND s.status='open')));
CREATE POLICY orders_read ON app.shop_orders FOR SELECT TO app_backend USING(app.request_order(id));
CREATE POLICY items_read ON app.shop_order_items FOR SELECT TO app_backend USING(app.request_order(order_id));
CREATE POLICY order_events_read ON app.order_status_events FOR SELECT TO app_backend USING(app.request_order(order_id));
CREATE POLICY tasks_read ON app.errand_tasks FOR SELECT TO app_backend USING(app.request_task(id));
CREATE POLICY offers_read ON app.errand_offers FOR SELECT TO app_backend USING(app.request_admin() OR
  (app.request_verified() AND (runner_id=app.current_user_id() OR EXISTS(SELECT 1 FROM app.errand_tasks t WHERE t.id=errand_offers.task_id AND t.publisher_id=app.current_user_id()))));
CREATE POLICY task_events_read ON app.errand_status_events FOR SELECT TO app_backend USING(app.request_task(task_id));
CREATE POLICY payments_read ON app.payments FOR SELECT TO app_backend USING(app.request_admin() OR (payer_id=app.current_user_id() AND app.request_verified()));
CREATE POLICY payment_events_read ON app.payment_events FOR SELECT TO app_backend USING(app.request_admin());
CREATE POLICY refunds_read ON app.refunds FOR SELECT TO app_backend USING(app.request_admin() OR EXISTS(SELECT 1 FROM app.payments p WHERE p.id=refunds.payment_id AND p.payer_id=app.current_user_id()));
CREATE POLICY conversations_read ON app.conversations FOR SELECT TO app_backend USING(app.request_conversation(id));
CREATE POLICY members_read ON app.conversation_members FOR SELECT TO app_backend USING(app.request_conversation(conversation_id));
CREATE POLICY messages_read ON app.direct_messages FOR SELECT TO app_backend USING(app.request_conversation(conversation_id) AND deleted_at IS NULL);
CREATE POLICY blocks_read ON app.user_blocks FOR SELECT TO app_backend USING(blocker_id=app.current_user_id() AND app.request_verified());
CREATE POLICY posts_private_read ON app.wall_posts FOR SELECT TO app_backend USING(app.request_admin() OR (author_id=app.current_user_id() AND app.request_verified()));
CREATE POLICY comments_private_read ON app.wall_comments FOR SELECT TO app_backend USING(app.request_admin() OR (author_id=app.current_user_id() AND app.request_verified()));
CREATE POLICY reports_read ON app.wall_reports FOR SELECT TO app_backend USING(app.request_admin() OR (reporter_id=app.current_user_id() AND app.request_verified()));
CREATE POLICY audit_read ON app.audit_logs FOR SELECT TO app_backend USING(app.request_admin());

-- Only safe self-service writes can be granted before workflow APIs are implemented.
GRANT INSERT ON app.wall_posts,app.wall_comments,app.wall_reports,app.direct_messages TO app_backend;
CREATE POLICY post_create ON app.wall_posts FOR INSERT TO app_backend WITH CHECK(app.request_verified() AND author_id=app.current_user_id() AND status='pending');
CREATE POLICY report_create ON app.wall_reports FOR INSERT TO app_backend WITH CHECK(app.request_verified() AND reporter_id=app.current_user_id() AND status='open' AND handled_by IS NULL);
CREATE POLICY message_create ON app.direct_messages FOR INSERT TO app_backend WITH CHECK(app.request_conversation(conversation_id) AND sender_id=app.current_user_id() AND deleted_at IS NULL);
GRANT UPDATE(status) ON app.wall_posts,app.wall_comments TO app_backend;
CREATE POLICY post_moderate ON app.wall_posts FOR UPDATE TO app_backend USING(app.request_admin()) WITH CHECK(app.request_admin());
CREATE POLICY comment_moderate ON app.wall_comments FOR UPDATE TO app_backend USING(app.request_admin()) WITH CHECK(app.request_admin());
GRANT INSERT,DELETE ON app.user_blocks TO app_backend;
CREATE POLICY block_insert ON app.user_blocks FOR INSERT TO app_backend WITH CHECK(app.request_verified() AND blocker_id=app.current_user_id());
CREATE POLICY block_delete ON app.user_blocks FOR DELETE TO app_backend USING(app.request_verified() AND blocker_id=app.current_user_id());

-- Owner-executed security-barrier views intentionally expose only explicit public fields.
-- Never use SELECT * or grant public-read policy on raw wall rows: author_id reveals anonymity.
CREATE VIEW app.wall_public_posts WITH (security_barrier=true) AS
 SELECT p.id,p.title,p.content,p.is_anonymous,p.created_at,p.updated_at,
   CASE WHEN p.is_anonymous THEN NULL::uuid ELSE p.author_id END AS author_id,
   CASE WHEN p.is_anonymous THEN '匿名用户' ELSE u.display_name END AS display_name
 FROM app.wall_posts p JOIN app.users u ON u.id=p.author_id WHERE p.status='published';
CREATE VIEW app.wall_public_comments WITH (security_barrier=true) AS
 SELECT c.id,c.post_id,c.content,c.is_anonymous,c.created_at,c.updated_at,
   CASE WHEN c.is_anonymous THEN NULL::uuid ELSE c.author_id END AS author_id,
   CASE WHEN c.is_anonymous THEN '匿名用户' ELSE u.display_name END AS display_name
 FROM app.wall_comments c JOIN app.wall_posts p ON p.id=c.post_id JOIN app.users u ON u.id=c.author_id
 WHERE c.status='published' AND p.status='published';
CREATE VIEW app.errand_open_list WITH (security_barrier=true) AS
 SELECT id,title,public_area,reward_cents,deadline_at,created_at FROM app.errand_tasks
 WHERE status='open' AND (deadline_at IS NULL OR deadline_at>now()) AND app.request_verified();
CREATE VIEW app.campus_public_pages WITH (security_barrier=true) AS
 SELECT id,slug,title,summary,content,audience,published_at FROM app.campus_pages
 WHERE status='published' AND published_at<=now();
CREATE VIEW app.public_stores WITH (security_barrier=true) AS
 SELECT id,name,store_type,description,location FROM app.stores WHERE status='open';
CREATE VIEW app.public_products WITH (security_barrier=true) AS
 SELECT p.id,p.store_id,p.name,p.description,p.image_url,p.price_cents,p.stock_quantity
 FROM app.products p JOIN app.stores s ON s.id=p.store_id WHERE p.status='on_sale' AND s.status='open';

CREATE POLICY comment_create ON app.wall_comments FOR INSERT TO app_backend WITH CHECK(app.request_verified() AND author_id=app.current_user_id() AND status='pending'
  AND EXISTS(SELECT 1 FROM app.wall_public_posts p WHERE p.id=wall_comments.post_id));

GRANT SELECT ON app.wall_public_posts,app.wall_public_comments,app.campus_public_pages,app.public_stores,app.public_products TO app_backend,app_agent;
GRANT SELECT ON app.errand_open_list TO app_backend;
GRANT USAGE ON SEQUENCE app.wall_comments_id_seq,app.wall_reports_id_seq,app.direct_messages_id_seq,app.shop_order_items_id_seq TO app_backend;

-- Payment/verification callbacks and order/errand/chat workflow writes are intentionally
-- NOT granted here; later transactional service APIs must get explicit scoped capabilities.
-- Migration/import jobs may populate them as the migration owner, never the public client.
REVOKE ALL ON FUNCTION app.request_role(),app.request_admin(),app.request_verified(),
 app.request_enrolled(uuid),app.request_teaches(uuid),app.request_store_staff(uuid),app.request_order(uuid),
 app.request_task(uuid),app.request_conversation(uuid),app.enforce_campus_identity(),app.enforce_score(),
 app.enforce_exam_maximum(),app.enforce_direct_member(),app.lock_conversation_pair(),app.guard_message() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.enforce_errand_assignment(),app.enforce_payment_target(),app.enforce_refund_bound() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.request_role(),app.request_admin(),app.request_verified(),
 app.request_enrolled(uuid),app.request_teaches(uuid),app.request_store_staff(uuid),app.request_order(uuid),
 app.request_task(uuid),app.request_conversation(uuid) TO app_backend;

COMMENT ON TABLE app.identity_verifications IS 'Trusted verification result only; not proof of liveness by itself. Provider/manual procedure implemented later.';
COMMENT ON TABLE app.exam_scores IS 'Only the student reads own published scores with current-session identity proof. Teachers/admins have no default grade-reading permission.';
COMMENT ON TABLE app.direct_messages IS 'Application-encrypted body, not end-to-end encryption. Only verified active conversation members may read.';
COMMENT ON TABLE app.wall_posts IS 'Use wall_public_posts for anonymous display; author identity is visible only to owner/moderator through the raw table.';
COMMENT ON TABLE app.audit_logs IS 'Append-only for future trusted audit writer; no runtime mutation grants yet. Avoid sensitive metadata.';



-- SOURCE: db/migrations/006_wall_frontend_fields.sql
-- Fields used by the campus-companion campus wall client.
ALTER TABLE app.wall_posts
  ADD COLUMN category text NOT NULL DEFAULT '校园日常'
    CHECK (length(btrim(category)) BETWEEN 1 AND 80),
  ADD COLUMN location text NOT NULL DEFAULT '' CHECK (length(location) <= 300),
  ADD COLUMN visibility text NOT NULL DEFAULT 'campus'
    CHECK (visibility IN ('campus','friends','private')),
  ADD COLUMN media jsonb NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(media) = 'array');

DROP POLICY comment_create ON app.wall_comments;
DROP VIEW app.wall_public_posts;
CREATE VIEW app.wall_public_posts WITH (security_barrier=true) AS
 SELECT p.id,p.title,p.content,p.category,p.location,p.media,p.is_anonymous,p.created_at,p.updated_at,
   CASE WHEN p.is_anonymous THEN NULL::uuid ELSE p.author_id END AS author_id,
   CASE WHEN p.is_anonymous THEN '匿名用户' ELSE u.display_name END AS display_name
 FROM app.wall_posts p JOIN app.users u ON u.id=p.author_id
 WHERE p.status='published' AND p.visibility='campus';

GRANT SELECT ON app.wall_public_posts TO app_backend, app_agent;

CREATE POLICY comment_create ON app.wall_comments FOR INSERT TO app_backend WITH CHECK(app.request_verified() AND author_id=app.current_user_id() AND status='pending'
  AND EXISTS(SELECT 1 FROM app.wall_public_posts p WHERE p.id=wall_comments.post_id));


-- SOURCE: db/migrations/007_login_identity_lookup.sql
-- Login may bind a verified identity to a new session without exposing
-- encrypted identity fields to the application role.
CREATE FUNCTION app.login_identity_id(target_user uuid, target_role text)
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, app AS $$
  SELECT id
  FROM app.identity_verifications
  WHERE user_id=target_user
    AND identity_type=target_role
    AND status='verified'
    AND verified_at<=now()
    AND (expires_at IS NULL OR expires_at>now())
  ORDER BY verified_at DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION app.login_identity_id(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.login_identity_id(uuid,text) TO app_backend;


-- SOURCE: db/migrations/008_frontend_supporting_data.sql
-- Supporting data objects used by the current frontend handoff.
-- These tables are intentionally separate from the original campus domain
-- tables so later API work can be added without changing existing contracts.

CREATE TABLE app.places (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE CHECK (slug = lower(btrim(slug)) AND slug ~ '^[a-z0-9][a-z0-9-]{0,119}$'),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  category text NOT NULL CHECK (length(btrim(category)) BETWEEN 1 AND 60),
  summary text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  address text NOT NULL DEFAULT '',
  latitude numeric(9,6),
  longitude numeric(9,6),
  cover_url text NOT NULL DEFAULT '',
  gallery jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(gallery) = 'array'),
  opening_hours jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(opening_hours) = 'object'),
  status text NOT NULL DEFAULT 'published' CHECK (status IN ('draft', 'published', 'hidden')),
  created_by uuid REFERENCES app.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX places_public_idx ON app.places(category, updated_at DESC) WHERE status = 'published';

CREATE TABLE app.place_reviews (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  place_id uuid NOT NULL REFERENCES app.places(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  content text NOT NULL DEFAULT '' CHECK (length(content) <= 3000),
  status text NOT NULL DEFAULT 'published' CHECK (status IN ('pending', 'published', 'hidden', 'deleted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (place_id, author_id)
);
CREATE INDEX place_reviews_public_idx ON app.place_reviews(place_id, created_at DESC) WHERE status = 'published';

CREATE TABLE app.post_bookmarks (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  post_id uuid NOT NULL REFERENCES app.wall_posts(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);

CREATE TABLE app.uploads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  object_key text NOT NULL UNIQUE CHECK (length(btrim(object_key)) BETWEEN 1 AND 500),
  public_url text NOT NULL DEFAULT '',
  media_type text NOT NULL CHECK (media_type IN ('image', 'video', 'file')),
  content_type text NOT NULL CHECK (length(btrim(content_type)) BETWEEN 1 AND 120),
  byte_size bigint NOT NULL CHECK (byte_size > 0 AND byte_size <= 52428800),
  status text NOT NULL DEFAULT 'ready' CHECK (status IN ('pending', 'ready', 'blocked', 'deleted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX uploads_owner_idx ON app.uploads(owner_id, created_at DESC);

CREATE TABLE app.activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id uuid REFERENCES app.users(id) ON DELETE SET NULL,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 200),
  summary text NOT NULL DEFAULT '',
  content text NOT NULL DEFAULT '',
  location text NOT NULL DEFAULT '',
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  capacity integer CHECK (capacity IS NULL OR capacity > 0),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'cancelled', 'finished')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at IS NULL OR ends_at >= starts_at)
);
CREATE INDEX activities_public_idx ON app.activities(starts_at) WHERE status = 'published';

CREATE TABLE app.activity_registrations (
  activity_id uuid NOT NULL REFERENCES app.activities(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'registered' CHECK (status IN ('registered', 'cancelled', 'attended')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (activity_id, user_id)
);
CREATE INDEX activity_registrations_user_idx ON app.activity_registrations(user_id, created_at DESC);

CREATE TABLE app.market_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 200),
  description text NOT NULL DEFAULT '',
  price_cents integer NOT NULL CHECK (price_cents >= 0),
  category text NOT NULL DEFAULT '',
  image_urls jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(image_urls) = 'array'),
  contact_ciphertext bytea,
  status text NOT NULL DEFAULT 'available' CHECK (status IN ('draft', 'available', 'reserved', 'sold', 'removed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX market_items_public_idx ON app.market_items(created_at DESC) WHERE status = 'available';

CREATE TABLE app.support_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  topic text NOT NULL CHECK (length(btrim(topic)) BETWEEN 1 AND 120),
  note_ciphertext bytea,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'contacted', 'closed', 'cancelled')),
  assigned_teacher_id uuid REFERENCES app.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX support_requests_student_idx ON app.support_requests(student_id, created_at DESC);

CREATE TABLE app.friend_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  message text NOT NULL DEFAULT '' CHECK (length(message) <= 1000),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (sender_id <> recipient_id),
  UNIQUE (sender_id, recipient_id)
);
CREATE INDEX friend_requests_recipient_idx ON app.friend_requests(recipient_id, status, created_at DESC);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'places','place_reviews','post_bookmarks','uploads','activities',
    'activity_registrations','market_items','support_requests','friend_requests'
  ] LOOP
    EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE app.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON app.%I FROM PUBLIC, app_backend, app_agent', t);
    EXECUTE format('GRANT SELECT ON app.%I TO app_backend', t);
  END LOOP;
END $$;

CREATE POLICY places_read ON app.places FOR SELECT TO app_backend
  USING (status = 'published' OR app.request_admin());
CREATE POLICY place_reviews_read ON app.place_reviews FOR SELECT TO app_backend
  USING (status = 'published' OR app.request_admin() OR author_id = app.current_user_id());
CREATE POLICY bookmark_read ON app.post_bookmarks FOR SELECT TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY upload_read ON app.uploads FOR SELECT TO app_backend
  USING (owner_id = app.current_user_id() AND app.request_verified());
CREATE POLICY activities_read ON app.activities FOR SELECT TO app_backend
  USING (status = 'published' OR app.request_admin() OR organizer_id = app.current_user_id());
CREATE POLICY activity_registration_read ON app.activity_registrations FOR SELECT TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified()
    OR EXISTS (SELECT 1 FROM app.activities a WHERE a.id = activity_id AND a.organizer_id = app.current_user_id()));
CREATE POLICY market_items_read ON app.market_items FOR SELECT TO app_backend
  USING (status = 'available' OR app.request_admin() OR seller_id = app.current_user_id());
CREATE POLICY support_request_read ON app.support_requests FOR SELECT TO app_backend
  USING (app.request_admin() OR student_id = app.current_user_id() OR assigned_teacher_id = app.current_user_id());
CREATE POLICY friend_request_read ON app.friend_requests FOR SELECT TO app_backend
  USING (app.request_verified() AND (sender_id = app.current_user_id() OR recipient_id = app.current_user_id()));

GRANT INSERT ON app.place_reviews, app.post_bookmarks, app.uploads,
  app.activity_registrations, app.market_items, app.support_requests,
  app.friend_requests TO app_backend;
GRANT UPDATE, DELETE ON app.place_reviews, app.post_bookmarks, app.uploads,
  app.activity_registrations, app.market_items, app.support_requests,
  app.friend_requests TO app_backend;

CREATE POLICY review_create ON app.place_reviews FOR INSERT TO app_backend
  WITH CHECK (app.request_verified() AND author_id = app.current_user_id());
CREATE POLICY review_update ON app.place_reviews FOR UPDATE TO app_backend
  USING (app.request_admin() OR (author_id = app.current_user_id() AND app.request_verified()))
  WITH CHECK (app.request_admin() OR (author_id = app.current_user_id() AND app.request_verified()));
CREATE POLICY review_delete ON app.place_reviews FOR DELETE TO app_backend
  USING (app.request_admin() OR (author_id = app.current_user_id() AND app.request_verified()));
CREATE POLICY bookmark_write ON app.post_bookmarks FOR INSERT TO app_backend
  WITH CHECK (app.request_verified() AND user_id = app.current_user_id());
CREATE POLICY bookmark_delete ON app.post_bookmarks FOR DELETE TO app_backend
  USING (app.request_verified() AND user_id = app.current_user_id());
CREATE POLICY upload_write ON app.uploads FOR INSERT TO app_backend
  WITH CHECK (app.request_verified() AND owner_id = app.current_user_id());
CREATE POLICY upload_delete ON app.uploads FOR DELETE TO app_backend
  USING (app.request_verified() AND owner_id = app.current_user_id());
CREATE POLICY registration_write ON app.activity_registrations FOR INSERT TO app_backend
  WITH CHECK (app.request_verified() AND user_id = app.current_user_id()
    AND EXISTS (SELECT 1 FROM app.activities a WHERE a.id = activity_id AND a.status = 'published'));
CREATE POLICY registration_update ON app.activity_registrations FOR UPDATE TO app_backend
  USING (app.request_verified() AND user_id = app.current_user_id())
  WITH CHECK (app.request_verified() AND user_id = app.current_user_id());
CREATE POLICY registration_delete ON app.activity_registrations FOR DELETE TO app_backend
  USING (app.request_verified() AND user_id = app.current_user_id());
CREATE POLICY market_item_write ON app.market_items FOR INSERT TO app_backend
  WITH CHECK (app.request_verified() AND seller_id = app.current_user_id());
CREATE POLICY market_item_update ON app.market_items FOR UPDATE TO app_backend
  USING (app.request_admin() OR (app.request_verified() AND seller_id = app.current_user_id()))
  WITH CHECK (app.request_admin() OR (app.request_verified() AND seller_id = app.current_user_id()));
CREATE POLICY market_item_delete ON app.market_items FOR DELETE TO app_backend
  USING (app.request_admin() OR (app.request_verified() AND seller_id = app.current_user_id()));
CREATE POLICY support_request_write ON app.support_requests FOR INSERT TO app_backend
  WITH CHECK (app.request_verified() AND student_id = app.current_user_id());
CREATE POLICY support_request_update ON app.support_requests FOR UPDATE TO app_backend
  USING (app.request_admin() OR student_id = app.current_user_id())
  WITH CHECK (app.request_admin() OR student_id = app.current_user_id());
CREATE POLICY friend_request_write ON app.friend_requests FOR INSERT TO app_backend
  WITH CHECK (app.request_verified() AND sender_id = app.current_user_id());
CREATE POLICY friend_request_update ON app.friend_requests FOR UPDATE TO app_backend
  USING (app.request_verified() AND (sender_id = app.current_user_id() OR recipient_id = app.current_user_id()))
  WITH CHECK (app.request_verified() AND (sender_id = app.current_user_id() OR recipient_id = app.current_user_id()));

CREATE VIEW app.public_places WITH (security_barrier=true) AS
  SELECT id, slug, name, category, summary, description, address, latitude, longitude,
    cover_url, gallery, opening_hours, updated_at
  FROM app.places WHERE status = 'published';
CREATE VIEW app.public_activities WITH (security_barrier=true) AS
  SELECT id, title, summary, content, location, starts_at, ends_at, capacity, created_at
  FROM app.activities WHERE status = 'published';
CREATE VIEW app.public_market_items WITH (security_barrier=true) AS
  SELECT id, title, description, price_cents, category, image_urls, created_at, updated_at
  FROM app.market_items WHERE status = 'available';
GRANT SELECT ON app.public_places, app.public_activities, app.public_market_items TO app_backend, app_agent;

GRANT USAGE ON SEQUENCE app.place_reviews_id_seq TO app_backend;


-- SOURCE: db/migrations/009_frontend_domain_completion.sql
-- Complete the persistence model used by the current campus-companion frontend.
-- Sensitive care data is deliberately isolated from public campus content.

CREATE TABLE app.wall_post_likes (
  post_id uuid NOT NULL REFERENCES app.wall_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);
CREATE INDEX wall_post_likes_user_idx ON app.wall_post_likes(user_id, created_at DESC);

CREATE TABLE app.wall_post_views (
  post_id uuid NOT NULL REFERENCES app.wall_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  first_viewed_at timestamptz NOT NULL DEFAULT now(),
  last_viewed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);
CREATE INDEX wall_post_views_user_idx ON app.wall_post_views(user_id, last_viewed_at DESC);

CREATE TABLE app.place_bookmarks (
  place_id uuid NOT NULL REFERENCES app.places(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (place_id, user_id)
);
CREATE INDEX place_bookmarks_user_idx ON app.place_bookmarks(user_id, created_at DESC);

CREATE TABLE app.user_preferences (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  preference_key text NOT NULL CHECK (preference_key = btrim(preference_key) AND length(preference_key) BETWEEN 1 AND 80),
  preference_value jsonb NOT NULL CHECK (jsonb_typeof(preference_value) IN ('object','array','string','number','boolean','null')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, preference_key)
);

CREATE TABLE app.friendships (
  user_a uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  user_b uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'removed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz,
  removed_at timestamptz,
  PRIMARY KEY (user_a, user_b),
  CHECK (user_a < user_b),
  CHECK ((status = 'active' AND accepted_at IS NOT NULL AND removed_at IS NULL) OR
    (status = 'removed' AND removed_at IS NOT NULL))
);

CREATE TABLE app.friend_preferences (
  owner_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  friend_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  remark text NOT NULL DEFAULT '' CHECK (length(remark) <= 30),
  pinned boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, friend_id),
  CHECK (owner_id <> friend_id)
);

CREATE TABLE app.market_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid NOT NULL REFERENCES app.market_items(id) ON DELETE RESTRICT,
  buyer_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  seller_id uuid NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
  item_title_snapshot text NOT NULL CHECK (length(btrim(item_title_snapshot)) BETWEEN 1 AND 200),
  unit_price_cents integer NOT NULL CHECK (unit_price_cents >= 0),
  delivery_fee_cents integer NOT NULL DEFAULT 0 CHECK (delivery_fee_cents >= 0),
  total_cents bigint NOT NULL CHECK (total_cents >= 0),
  status text NOT NULL DEFAULT 'pending_payment' CHECK (status IN ('pending_payment','pending_delivery','delivered','completed','cancelled','refund_pending','refunded')),
  delivery_method text NOT NULL CHECK (delivery_method IN ('campus_contactless','courier')),
  delivery_address_ciphertext bytea NOT NULL,
  recipient_ciphertext bytea NOT NULL,
  phone_ciphertext bytea NOT NULL,
  payment_method text NOT NULL CHECK (payment_method IN ('wechat','alipay')),
  request_key uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (buyer_id, request_key),
  CHECK (buyer_id <> seller_id),
  CHECK (total_cents = unit_price_cents + delivery_fee_cents)
);
CREATE INDEX market_orders_buyer_idx ON app.market_orders(buyer_id, created_at DESC);
CREATE INDEX market_orders_seller_idx ON app.market_orders(seller_id, created_at DESC);

CREATE TABLE app.market_order_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id uuid NOT NULL REFERENCES app.market_orders(id) ON DELETE RESTRICT,
  actor_id uuid REFERENCES app.users(id) ON DELETE SET NULL,
  from_status text,
  to_status text NOT NULL CHECK (to_status IN ('pending_payment','pending_delivery','delivered','completed','cancelled','refund_pending','refunded')),
  reason text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.campus_locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE CHECK (slug = lower(btrim(slug)) AND slug ~ '^[a-z0-9][a-z0-9-]{0,119}$'),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  building text NOT NULL DEFAULT '',
  room text NOT NULL DEFAULT '',
  floor smallint CHECK (floor IS NULL OR floor BETWEEN -2 AND 99),
  kind text NOT NULL CHECK (kind IN ('building','room','service','route')),
  route jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(route) = 'object'),
  status text NOT NULL DEFAULT 'published' CHECK (status IN ('draft','published','hidden')),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.campus_notices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notice_type text NOT NULL CHECK (length(btrim(notice_type)) BETWEEN 1 AND 60),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 200),
  detail text NOT NULL DEFAULT '',
  action_label text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'published' CHECK (status IN ('draft','published','closed')),
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid REFERENCES app.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at >= starts_at)
);
CREATE INDEX campus_notices_public_idx ON app.campus_notices(starts_at DESC) WHERE status = 'published';

CREATE TABLE app.notice_subscriptions (
  notice_id uuid NOT NULL REFERENCES app.campus_notices(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (notice_id, user_id)
);

CREATE TABLE app.ai_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  title text NOT NULL DEFAULT '小心',
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived','deleted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ai_conversations_user_idx ON app.ai_conversations(user_id, updated_at DESC);

CREATE TABLE app.ai_messages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  conversation_id uuid NOT NULL REFERENCES app.ai_conversations(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('user','assistant','system')),
  body_ciphertext bytea NOT NULL,
  client_message_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (conversation_id, client_message_id)
);
CREATE INDEX ai_messages_conversation_idx ON app.ai_messages(conversation_id, id);

CREATE TABLE app.care_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES app.student_profiles(user_id) ON DELETE RESTRICT,
  teacher_id uuid NOT NULL REFERENCES app.teacher_profiles(user_id) ON DELETE RESTRICT,
  student_label text NOT NULL CHECK (length(btrim(student_label)) BETWEEN 1 AND 80),
  student_no_masked text NOT NULL DEFAULT '',
  group_label text NOT NULL DEFAULT '',
  risk_level text NOT NULL CHECK (risk_level IN ('high','medium','low')),
  topic text NOT NULL CHECK (length(btrim(topic)) BETWEEN 1 AND 500),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','following','archived')),
  consent_at timestamptz NOT NULL,
  consent_expires_at timestamptz,
  opened_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz,
  CHECK (consent_expires_at IS NULL OR consent_expires_at > consent_at),
  CHECK ((status = 'archived') = (archived_at IS NOT NULL))
);
CREATE INDEX care_cases_teacher_idx ON app.care_cases(teacher_id, status, opened_at DESC);
CREATE INDEX care_cases_student_idx ON app.care_cases(student_id, opened_at DESC);

CREATE TABLE app.wellbeing_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES app.care_cases(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES app.student_profiles(user_id) ON DELETE RESTRICT,
  observed_on date NOT NULL,
  mood smallint CHECK (mood IS NULL OR mood BETWEEN 1 AND 5),
  stress smallint CHECK (stress IS NULL OR stress BETWEEN 1 AND 5),
  note_ciphertext bytea,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (case_id, observed_on)
);

CREATE TABLE app.care_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES app.care_cases(id) ON DELETE CASCADE,
  teacher_id uuid NOT NULL REFERENCES app.teacher_profiles(user_id) ON DELETE RESTRICT,
  method text NOT NULL CHECK (method IN ('in_person','phone','online','follow_up')),
  summary_ciphertext bytea NOT NULL,
  plan_ciphertext bytea NOT NULL,
  next_follow_up_on date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX care_records_case_idx ON app.care_records(case_id, created_at DESC);

CREATE TABLE app.wellbeing_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES app.care_cases(id) ON DELETE CASCADE,
  teacher_id uuid NOT NULL REFERENCES app.teacher_profiles(user_id) ON DELETE RESTRICT,
  period_start date NOT NULL,
  period_end date NOT NULL,
  summary_ciphertext bytea NOT NULL,
  status text NOT NULL DEFAULT 'published' CHECK (status IN ('draft','published','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end >= period_start)
);
CREATE INDEX wellbeing_reports_case_idx ON app.wellbeing_reports(case_id, period_end DESC);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'wall_post_likes','wall_post_views','place_bookmarks','user_preferences',
    'friendships','friend_preferences','market_orders','market_order_events',
    'campus_locations','campus_notices','notice_subscriptions',
    'ai_conversations','ai_messages','care_cases','wellbeing_snapshots',
    'care_records','wellbeing_reports'
  ] LOOP
    EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE app.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON app.%I FROM PUBLIC, app_backend, app_agent', t);
    EXECUTE format('GRANT SELECT ON app.%I TO app_backend', t);
  END LOOP;
END $$;

CREATE POLICY wall_like_read ON app.wall_post_likes FOR SELECT TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY wall_like_write ON app.wall_post_likes FOR INSERT TO app_backend
  WITH CHECK (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY wall_like_delete ON app.wall_post_likes FOR DELETE TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY wall_view_read ON app.wall_post_views FOR SELECT TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY wall_view_write ON app.wall_post_views FOR INSERT TO app_backend
  WITH CHECK (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY wall_view_update ON app.wall_post_views FOR UPDATE TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified())
  WITH CHECK (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY place_bookmark_read ON app.place_bookmarks FOR SELECT TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY place_bookmark_write ON app.place_bookmarks FOR INSERT TO app_backend
  WITH CHECK (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY place_bookmark_delete ON app.place_bookmarks FOR DELETE TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY preference_owner ON app.user_preferences FOR ALL TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified())
  WITH CHECK (user_id = app.current_user_id() AND app.request_verified());

CREATE POLICY friendship_read ON app.friendships FOR SELECT TO app_backend
  USING (app.request_verified() AND (user_a = app.current_user_id() OR user_b = app.current_user_id()));
CREATE POLICY friend_preference_owner ON app.friend_preferences FOR ALL TO app_backend
  USING (owner_id = app.current_user_id() AND app.request_verified())
  WITH CHECK (owner_id = app.current_user_id() AND app.request_verified());
CREATE POLICY market_order_read ON app.market_orders FOR SELECT TO app_backend
  USING (app.request_verified() AND (buyer_id = app.current_user_id() OR seller_id = app.current_user_id()));
CREATE POLICY market_order_create ON app.market_orders FOR INSERT TO app_backend
  WITH CHECK (app.request_verified() AND buyer_id = app.current_user_id() AND buyer_id <> seller_id);
CREATE POLICY market_order_update ON app.market_orders FOR UPDATE TO app_backend
  USING (app.request_verified() AND (buyer_id = app.current_user_id() OR seller_id = app.current_user_id()))
  WITH CHECK (app.request_verified() AND (buyer_id = app.current_user_id() OR seller_id = app.current_user_id()));
CREATE POLICY market_event_read ON app.market_order_events FOR SELECT TO app_backend
  USING (EXISTS (SELECT 1 FROM app.market_orders o WHERE o.id = order_id
    AND app.request_verified() AND (o.buyer_id = app.current_user_id() OR o.seller_id = app.current_user_id())));
CREATE POLICY location_read ON app.campus_locations FOR SELECT TO app_backend
  USING (status = 'published' OR app.request_admin());
CREATE POLICY notice_read ON app.campus_notices FOR SELECT TO app_backend
  USING (status = 'published' OR app.request_admin());
CREATE POLICY notice_subscription_owner ON app.notice_subscriptions FOR ALL TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified())
  WITH CHECK (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY ai_conversation_owner ON app.ai_conversations FOR ALL TO app_backend
  USING (user_id = app.current_user_id() AND app.request_verified())
  WITH CHECK (user_id = app.current_user_id() AND app.request_verified());
CREATE POLICY ai_message_owner ON app.ai_messages FOR SELECT TO app_backend
  USING (EXISTS (SELECT 1 FROM app.ai_conversations c WHERE c.id = conversation_id
    AND c.user_id = app.current_user_id() AND app.request_verified()));
CREATE POLICY ai_message_write ON app.ai_messages FOR INSERT TO app_backend
  WITH CHECK (EXISTS (SELECT 1 FROM app.ai_conversations c WHERE c.id = conversation_id
    AND c.user_id = app.current_user_id() AND app.request_verified()));

-- Care records are visible only to the verified teacher assigned to the case.
-- Administrators deliberately have no policy on these tables.
CREATE POLICY care_case_teacher_read ON app.care_cases FOR SELECT TO app_backend
  USING (teacher_id = app.current_user_id() AND app.request_role() = 'teacher' AND app.request_verified()
    AND (consent_expires_at IS NULL OR consent_expires_at > now()));
CREATE POLICY care_snapshot_teacher_read ON app.wellbeing_snapshots FOR SELECT TO app_backend
  USING (EXISTS (SELECT 1 FROM app.care_cases c WHERE c.id = case_id AND c.teacher_id = app.current_user_id()
    AND app.request_role() = 'teacher' AND app.request_verified()
    AND (c.consent_expires_at IS NULL OR c.consent_expires_at > now())));
CREATE POLICY care_record_teacher_read ON app.care_records FOR SELECT TO app_backend
  USING (EXISTS (SELECT 1 FROM app.care_cases c WHERE c.id = case_id AND c.teacher_id = app.current_user_id()
    AND app.request_role() = 'teacher' AND app.request_verified()
    AND (c.consent_expires_at IS NULL OR c.consent_expires_at > now())));
CREATE POLICY care_record_teacher_write ON app.care_records FOR INSERT TO app_backend
  WITH CHECK (teacher_id = app.current_user_id() AND app.request_role() = 'teacher' AND app.request_verified()
    AND EXISTS (SELECT 1 FROM app.care_cases c WHERE c.id = case_id AND c.teacher_id = app.current_user_id()
      AND c.status <> 'archived'));
CREATE POLICY report_teacher_read ON app.wellbeing_reports FOR SELECT TO app_backend
  USING (teacher_id = app.current_user_id() AND app.request_role() = 'teacher' AND app.request_verified()
    AND EXISTS (SELECT 1 FROM app.care_cases c WHERE c.id = case_id AND c.teacher_id = app.current_user_id()
      AND (c.consent_expires_at IS NULL OR c.consent_expires_at > now())));

CREATE VIEW app.public_campus_locations WITH (security_barrier=true) AS
  SELECT id, slug, name, building, room, floor, kind, route, updated_at
  FROM app.campus_locations WHERE status = 'published';
CREATE VIEW app.public_campus_notices WITH (security_barrier=true) AS
  SELECT id, notice_type, title, detail, action_label, starts_at, ends_at, created_at
  FROM app.campus_notices WHERE status = 'published';
GRANT SELECT ON app.public_campus_locations, app.public_campus_notices TO app_backend, app_agent;

GRANT INSERT, DELETE ON app.wall_post_likes, app.place_bookmarks TO app_backend;
GRANT INSERT, UPDATE ON app.wall_post_views, app.user_preferences, app.friend_preferences,
  app.market_orders, app.ai_conversations, app.ai_messages TO app_backend;
GRANT INSERT ON app.market_order_events, app.notice_subscriptions, app.care_records TO app_backend;
GRANT USAGE ON SEQUENCE app.market_order_events_id_seq, app.ai_messages_id_seq TO app_backend;

-- Fresh installs require encrypted identity columns; no plaintext backfill is needed.
ALTER TABLE app.users ALTER COLUMN email_ciphertext SET NOT NULL, ALTER COLUMN email_lookup SET NOT NULL;
COMMIT;
