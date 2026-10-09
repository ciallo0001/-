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
