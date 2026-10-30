CREATE TABLE IF NOT EXISTS vilqa.profiles(user_id bigint PRIMARY KEY,data jsonb NOT NULL,version integer NOT NULL DEFAULT 0,updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS vilqa.profile_audit(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,user_id bigint NOT NULL,actor_id bigint NOT NULL,action text NOT NULL,before_data jsonb,after_data jsonb,created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS profile_audit_user ON vilqa.profile_audit(user_id,id);
CREATE OR REPLACE FUNCTION vilqa.profile_fields(p jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
 SELECT COALESCE(jsonb_object_agg(key,value),'{}') FROM jsonb_each(COALESCE(p,'{}')) WHERE key=ANY(ARRAY['name','gender','age','height','weight','activity_level','goal','goal_ru','timezone','daily_calories','daily_protein','daily_fats','daily_carbs','bmr','tdee','warning_message']);
$f$;
CREATE OR REPLACE FUNCTION vilqa.resolve_profile(p_user bigint,p_base jsonb,p_day text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE d jsonb;v integer:=0;stamp timestamptz;z text;historic jsonb;
BEGIN
 SELECT data,version,updated_at INTO d,v,stamp FROM vilqa.profiles WHERE user_id=p_user;
 d:=COALESCE(p_base,'{}')||COALESCE(d,'{}');z:=COALESCE(d->>'timezone','Europe/Moscow');
 IF p_day IS NOT NULL AND p_day<to_char(now() AT TIME ZONE z,'YYYY-MM-DD') THEN
  SELECT after_data INTO historic FROM vilqa.profile_audit WHERE user_id=p_user AND to_char(created_at AT TIME ZONE z,'YYYY-MM-DD')<=p_day ORDER BY id DESC LIMIT 1;
  IF historic IS NULL THEN SELECT before_data INTO historic FROM vilqa.profile_audit WHERE user_id=p_user AND before_data IS NOT NULL ORDER BY id LIMIT 1;END IF;
  IF historic IS NOT NULL THEN d:=d||historic;END IF;
 END IF;
 RETURN d||jsonb_build_object('user_id',p_user,'profile_version',COALESCE(v,0),'profile_updated_at',stamp);
END $f$;
CREATE OR REPLACE FUNCTION vilqa.edit_profile(p_actor bigint,p_user bigint,p_req jsonb,p_base jsonb) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE old vilqa.profiles%ROWTYPE;cached vilqa.requests%ROWTYPE;patch jsonb:=p_req->'patch';before jsonb;after jsonb;nonce text:=p_req->>'request_id';age integer;h double precision;w double precision;a double precision;g text;sex text;nm text;z text;bmr double precision;tdee double precision;kcal double precision;mincal double precision;warn text;response jsonb;field text;
BEGIN
 IF p_actor<>p_user AND NOT EXISTS(SELECT 1 FROM vilqa.admins WHERE user_id=p_actor) THEN RETURN jsonb_build_object('success',false,'status',403,'message','Нет доступа к профилю');END IF;
 IF p_user<=0 OR (p_base->>'user_id')::bigint IS DISTINCT FROM p_user THEN RETURN jsonb_build_object('success',false,'status',404,'message','Профиль не найден. Пройди регистрацию в боте.');END IF;
 IF nonce IS NULL OR nonce !~ '^[A-Za-z0-9_-]{16,80}$' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Не указан идентификатор операции');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_actor::text||':'||nonce,0));
 SELECT * INTO cached FROM vilqa.requests WHERE actor_id=p_actor AND request_id=nonce;
 IF FOUND THEN IF cached.request_data<>p_req THEN RETURN jsonb_build_object('success',false,'status',409,'message','Повторный идентификатор операции');END IF;RETURN cached.response;END IF;
 INSERT INTO vilqa.profiles(user_id,data) VALUES(p_user,vilqa.profile_fields(p_base)) ON CONFLICT DO NOTHING;
 SELECT * INTO old FROM vilqa.profiles WHERE user_id=p_user FOR UPDATE;
 IF p_req->>'version' IS NULL OR (p_req->>'version')::integer<>old.version THEN RETURN jsonb_build_object('success',false,'status',409,'message','Профиль уже изменён. Закрой форму и открой её снова.');END IF;
 before:=old.data;nm:=trim(patch->>'name');sex:=patch->>'gender';g:=patch->>'goal';
 IF nm IS NULL OR length(nm) NOT BETWEEN 1 AND 100 OR nm ~ '[[:cntrl:]]' OR sex NOT IN ('male','female') OR sex IS NULL OR g NOT IN ('lose','lose_fast','maintain','gain','gain_fast') OR g IS NULL THEN RETURN jsonb_build_object('success',false,'status',400,'message','Проверь имя, пол и цель');END IF;
 FOREACH field IN ARRAY ARRAY['age','height','weight','activity'] LOOP IF jsonb_typeof(patch->field) IS DISTINCT FROM 'number' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Заполни все параметры числами');END IF;END LOOP;
 IF (patch->>'age')::numeric<>trunc((patch->>'age')::numeric) THEN RETURN jsonb_build_object('success',false,'status',400,'message','Возраст должен быть целым числом');END IF;
 age:=(patch->>'age')::integer;h:=(patch->>'height')::double precision;w:=(patch->>'weight')::double precision;a:=(patch->>'activity')::double precision;
 IF age NOT BETWEEN 10 AND 120 OR h NOT BETWEEN 100 AND 250 OR w NOT BETWEEN 30 AND 300 OR a NOT IN (1.2,1.375,1.55,1.725,1.9) THEN RETURN jsonb_build_object('success',false,'status',400,'message','Проверь возраст, рост, вес и активность');END IF;
 z:=COALESCE(before->>'timezone',p_base->>'timezone','Europe/Moscow');
 bmr:=10*w+6.25*h-5*age+CASE WHEN sex='male' THEN 5 ELSE -161 END;tdee:=bmr*a;
 kcal:=CASE g WHEN 'lose' THEN tdee-500 WHEN 'lose_fast' THEN tdee-LEAST(tdee*.25,750) WHEN 'gain' THEN tdee+300 WHEN 'gain_fast' THEN tdee+400 ELSE tdee END;
 mincal:=GREATEST(CASE WHEN sex='male' THEN 1500 ELSE 1200 END,round((bmr*1.1)::numeric));
 IF kcal<mincal THEN kcal:=mincal;warn:='Расчётный ориентир скорректирован с учётом параметров.';END IF;
 kcal:=round(kcal::numeric);
 after:=jsonb_build_object('name',nm,'gender',sex,'age',age,'height',h,'weight',w,'activity_level',a::text,'goal',g,'goal_ru',CASE g WHEN 'lose' THEN 'похудение' WHEN 'lose_fast' THEN 'быстрое похудение' WHEN 'gain' THEN 'набор массы' WHEN 'gain_fast' THEN 'быстрый набор массы' ELSE 'поддержание веса' END,'timezone',z,'bmr',round(bmr::numeric),'tdee',round(tdee::numeric),'daily_calories',kcal,'daily_protein',round((kcal*.3/4)::numeric),'daily_fats',round((kcal*.25/9)::numeric),'daily_carbs',round((kcal*.45/4)::numeric),'warning_message',warn);
 UPDATE vilqa.profiles SET data=after,version=version+1,updated_at=now() WHERE user_id=p_user;
 INSERT INTO vilqa.profile_audit(user_id,actor_id,action,before_data,after_data) VALUES(p_user,p_actor,'edit',before,after);
 response:=jsonb_build_object('success',true,'profile',vilqa.resolve_profile(p_user,p_base));
 INSERT INTO vilqa.requests(actor_id,request_id,request_data,response) VALUES(p_actor,nonce,p_req,response);
 RETURN response;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('success',false,'status',400,'message','Некорректные параметры профиля');
END $f$;
CREATE OR REPLACE FUNCTION vilqa.registration_profile(p_row jsonb) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE uid bigint:=(p_row->>'user_id')::bigint;old jsonb;newdata jsonb:=vilqa.profile_fields(p_row);
BEGIN
 IF uid IS NULL OR uid<=0 THEN RAISE EXCEPTION 'Invalid registered user';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('profile-register:'||uid::text,0));
 SELECT data INTO old FROM vilqa.profiles WHERE user_id=uid FOR UPDATE;
 INSERT INTO vilqa.profiles(user_id,data,version) VALUES(uid,newdata,1) ON CONFLICT(user_id) DO UPDATE SET data=EXCLUDED.data,version=vilqa.profiles.version+1,updated_at=now();
 INSERT INTO vilqa.profile_audit(user_id,actor_id,action,before_data,after_data) VALUES(uid,uid,'registration',old,newdata);
 RETURN vilqa.resolve_profile(uid,p_row);
END $f$;
