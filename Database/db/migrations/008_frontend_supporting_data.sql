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
