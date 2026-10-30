CREATE OR REPLACE FUNCTION vilqa.read_stats_fast(p_user bigint,p_timezone text DEFAULT 'Europe/Moscow') RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE p jsonb;z text:=COALESCE(NULLIF(p_timezone,''),'Europe/Moscow');day text;logs jsonb;
BEGIN
 IF NOT COALESCE(vilqa.access_check(p_user),false) THEN RETURN NULL;END IF;
 SELECT data INTO p FROM vilqa.profiles WHERE user_id=p_user;
 IF NOT FOUND OR NOT (p ?& ARRAY['daily_calories','daily_protein','daily_fats','daily_carbs']) THEN RETURN jsonb_build_object('fallback',true,'user_id',p_user,'timezone',z);END IF;
 day:=to_char(now() AT TIME ZONE z,'YYYY-MM-DD');
 SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.time,d.id),'[]') INTO logs FROM vilqa.diary d WHERE user_id=p_user AND date=day AND deleted_at IS NULL;
 RETURN jsonb_build_object('user_id',p_user,'timezone',z,'snapshot',jsonb_build_object('profile',p||jsonb_build_object('user_id',p_user),'logs',logs));
END $f$;
