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
