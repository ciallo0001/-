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
