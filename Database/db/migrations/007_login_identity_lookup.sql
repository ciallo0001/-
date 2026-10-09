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
