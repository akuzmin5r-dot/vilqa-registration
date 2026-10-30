CREATE OR REPLACE FUNCTION vilqa.diary_time_patch(p_patch jsonb,p_current jsonb,p_timezone text) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $f$
DECLARE d text;t text;z text:=COALESCE(NULLIF(p_timezone,''),'Europe/Moscow');moment timestamptz;h integer;
BEGIN
 IF NOT (p_patch ? 'date' OR p_patch ? 'time') THEN RETURN p_current;END IF;
 IF (p_patch ? 'date' AND jsonb_typeof(p_patch->'date') IS DISTINCT FROM 'string') OR (p_patch ? 'time' AND jsonb_typeof(p_patch->'time') IS DISTINCT FROM 'string') THEN RAISE invalid_parameter_value USING MESSAGE='Invalid diary date or time';END IF;
 d:=COALESCE(p_patch->>'date',p_current->>'date');t:=COALESCE(p_patch->>'time',p_current->>'time');
 IF d IS NULL OR d !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' OR t IS NULL OR t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE invalid_parameter_value USING MESSAGE='Invalid diary date or time';END IF;
 PERFORM make_date(substring(d,1,4)::integer,substring(d,6,2)::integer,substring(d,9,2)::integer);
 moment:=(d||' '||t)::timestamp AT TIME ZONE z;
 IF to_char(moment AT TIME ZONE z,'YYYY-MM-DD HH24:MI')<>d||' '||t THEN RAISE invalid_parameter_value USING MESSAGE='Local diary time does not exist';END IF;
 h:=substring(t,1,2)::integer;
 RETURN jsonb_build_object('date',d,'time',t,'datetime',to_char(moment AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'meal_type',CASE WHEN h>=6 AND h<11 THEN 'завтрак' WHEN h>=11 AND h<16 THEN 'обед' WHEN h>=16 AND h<21 THEN 'ужин' ELSE 'перекус' END);
END $f$;
