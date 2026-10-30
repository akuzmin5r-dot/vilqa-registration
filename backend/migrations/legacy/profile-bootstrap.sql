CREATE OR REPLACE FUNCTION vilqa.ensure_profile(p_base jsonb) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE uid bigint:=(p_base->>'user_id')::bigint;p jsonb:=vilqa.profile_fields(p_base);old vilqa.profiles%ROWTYPE;merged jsonb;inserted integer;
BEGIN
 IF uid IS NULL OR uid<=0 OR NOT COALESCE(vilqa.access_check(uid),false) THEN RETURN vilqa.resolve_profile(uid,p_base);END IF;
 IF NOT (p ?& ARRAY['name','daily_calories','daily_protein','daily_fats','daily_carbs']) THEN RETURN vilqa.resolve_profile(uid,p_base);END IF;
 INSERT INTO vilqa.profiles(user_id,data,version) VALUES(uid,p,0) ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS inserted=ROW_COUNT;
 SELECT * INTO old FROM vilqa.profiles WHERE user_id=uid FOR UPDATE;
 merged:=p||old.data;
 IF inserted=1 THEN
  INSERT INTO vilqa.profile_audit(user_id,actor_id,action,before_data,after_data) VALUES(uid,uid,'import',NULL,old.data);
 ELSIF merged IS DISTINCT FROM old.data THEN
  UPDATE vilqa.profiles SET data=merged,version=version+1,updated_at=now() WHERE user_id=uid;
  INSERT INTO vilqa.profile_audit(user_id,actor_id,action,before_data,after_data) VALUES(uid,uid,'import',old.data,merged);
 END IF;
 RETURN vilqa.resolve_profile(uid,p_base);
END $f$;
