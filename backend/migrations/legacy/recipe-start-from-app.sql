BEGIN;
CREATE OR REPLACE FUNCTION vilqa.start_recipe_from_app(p_actor bigint,p_request text,p_legacy jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE profile jsonb;version bigint;row jsonb;
BEGIN
 IF NOT COALESCE(vilqa.access_check(p_actor),false) THEN RAISE EXCEPTION 'Recipe start access denied';END IF;
 IF p_request IS NULL OR p_request !~ '^[A-Za-z0-9_-]{16,80}$' THEN RAISE invalid_parameter_value USING MESSAGE='Invalid recipe start request';END IF;
 SELECT data INTO profile FROM vilqa.profiles WHERE user_id=p_actor AND data ? 'daily_calories';
 IF NOT FOUND THEN RAISE EXCEPTION 'Registered profile required';END IF;
 PERFORM vilqa.nav_profile(p_actor,vilqa.resolve_profile(p_actor,COALESCE(p_legacy,'{}')));
 SELECT state_version INTO version FROM vilqa.nav_sessions WHERE user_id=p_actor FOR UPDATE;
 row:=vilqa.nav_state_write(p_actor,'miniapp:'||p_request||':start',version,NULL,NULL,'start');
 RETURN row||jsonb_build_object('event_key','miniapp:'||p_request||':recipe-state');
END $f$;
COMMIT;
