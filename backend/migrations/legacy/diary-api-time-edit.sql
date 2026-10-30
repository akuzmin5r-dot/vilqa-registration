CREATE OR REPLACE FUNCTION vilqa.api(p_actor bigint, p_req jsonb, p_profiles jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
 v_action text:=p_req->>'action'; v_admin boolean; v_user bigint; v_day text; v_profile jsonb;
 v_row vilqa.diary%ROWTYPE; v_before jsonb; v_patch jsonb; v_time_patch jsonb; v_nonce text; v_cached vilqa.requests%ROWTYPE;
 v_response jsonb; v_entries jsonb; v_totals jsonb; v_audit vilqa.audit%ROWTYPE; f text; n double precision;
BEGIN
 SELECT EXISTS(SELECT 1 FROM vilqa.admins WHERE user_id=p_actor) INTO v_admin;
 IF p_actor IS NULL OR p_actor<=0 THEN RETURN jsonb_build_object('success',false,'status',401,'message','Открой дневник из Telegram'); END IF;
 v_user:=COALESCE((p_req->>'user_id')::bigint,p_actor);
 IF v_user<>p_actor AND NOT v_admin THEN RETURN jsonb_build_object('success',false,'status',403,'message','Нет доступа к этому дневнику'); END IF;
 SELECT x INTO v_profile FROM jsonb_array_elements(p_profiles) x WHERE (x->>'user_id')::bigint=v_user LIMIT 1;
 IF v_action='profile_edit' THEN RETURN vilqa.edit_profile(p_actor,v_user,p_req,v_profile);END IF;
 IF v_action='profile_history' THEN
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id DESC),'[]') INTO v_entries FROM (SELECT id,actor_id,action,before_data,after_data,created_at FROM vilqa.profile_audit WHERE user_id=v_user ORDER BY id DESC LIMIT 100) t;
  RETURN jsonb_build_object('success',true,'events',v_entries);
 END IF;
 v_profile:=vilqa.resolve_profile(v_user,COALESCE(v_profile,'{}'));
 IF v_action='profile' THEN RETURN jsonb_build_object('success',true,'profile',v_profile,'user_id',v_user,'is_admin',v_admin);END IF;
 v_day:=COALESCE(p_req->>'date',to_char(now() AT TIME ZONE COALESCE(v_profile->>'timezone','Europe/Moscow'),'YYYY-MM-DD'));
 IF v_day !~ '^\d{4}-\d{2}-\d{2}$' OR to_char(v_day::date,'YYYY-MM-DD')<>v_day THEN RETURN jsonb_build_object('success',false,'status',400,'message','Некорректная дата'); END IF;
 IF v_action='users' THEN
  IF NOT v_admin THEN RETURN jsonb_build_object('success',false,'status',403,'message','Нет доступа к админке'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('user_id',x->'user_id','name',x->>'name','username',x->>'username') ORDER BY x->>'name'),'[]') INTO v_entries FROM (SELECT vilqa.resolve_profile((value->>'user_id')::bigint,value) x FROM jsonb_array_elements(p_profiles)) profiles;
  IF EXISTS(SELECT 1 FROM vilqa.diary WHERE user_id=0) THEN v_entries:=v_entries||jsonb_build_array(jsonb_build_object('user_id',0,'name','Без владельца','username','')); END IF;
  RETURN jsonb_build_object('success',true,'users',v_entries,'is_admin',true);
 END IF;
 IF v_action='day' THEN
  v_profile:=vilqa.resolve_profile(v_user,v_profile,v_day);
  SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY time,id),'[]') INTO v_entries FROM vilqa.diary d WHERE user_id=v_user AND (date=v_day OR (v_admin AND v_user=0 AND date IS NULL)) AND (deleted_at IS NULL OR COALESCE((p_req->>'include_deleted')::boolean,false));
  SELECT jsonb_build_object('calories',COALESCE(sum(calories),0),'protein',COALESCE(sum(protein),0),'fats',COALESCE(sum(fats),0),'carbs',COALESCE(sum(carbs),0),'count',count(*)) INTO v_totals FROM vilqa.diary WHERE user_id=v_user AND (date=v_day OR (v_admin AND v_user=0 AND date IS NULL)) AND deleted_at IS NULL;
  RETURN jsonb_build_object('success',true,'date',v_day,'entries',v_entries,'totals',v_totals,'profile',v_profile-'current_state'-'recipe_draft','is_admin',v_admin,'actor_id',p_actor,'user_id',v_user);
 END IF;
 IF v_action='history' THEN
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.date DESC),'[]') INTO v_entries FROM (SELECT date,sum(calories) calories,sum(protein) protein,sum(fats) fats,sum(carbs) carbs,count(*) count FROM vilqa.diary WHERE user_id=v_user AND date BETWEEN to_char(v_day::date-29,'YYYY-MM-DD') AND v_day AND deleted_at IS NULL GROUP BY date) t;
  RETURN jsonb_build_object('success',true,'days',v_entries);
 END IF;
 IF v_action IN ('edit','delete','restore','revert') THEN
  v_nonce:=p_req->>'request_id';
  IF v_nonce IS NULL OR v_nonce !~ '^[A-Za-z0-9_-]{16,80}$' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Не указан идентификатор операции'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_actor::text||':'||v_nonce,0));
  SELECT * INTO v_cached FROM vilqa.requests WHERE actor_id=p_actor AND request_id=v_nonce;
  IF FOUND THEN
   IF v_cached.request_data<>p_req THEN RETURN jsonb_build_object('success',false,'status',409,'message','Повторный идентификатор операции'); END IF;
   RETURN v_cached.response;
  END IF;
 END IF;
 SELECT * INTO v_row FROM vilqa.diary WHERE id=(p_req->>'id')::bigint AND user_id=v_user FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'status',404,'message','Запись не найдена'); END IF;
 IF v_action='audit' THEN
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id DESC),'[]') INTO v_entries FROM (SELECT id,actor_id,action,before_data,after_data,created_at FROM vilqa.audit WHERE entry_id=v_row.id ORDER BY id DESC LIMIT 100) t;
  RETURN jsonb_build_object('success',true,'events',v_entries,'entry',to_jsonb(v_row));
 END IF;
 IF v_action NOT IN ('edit','delete','restore','revert') THEN RETURN jsonb_build_object('success',false,'status',400,'message','Неизвестная операция'); END IF;
 IF (p_req->>'version') IS NULL OR (p_req->>'version')::integer<>v_row.version THEN RETURN jsonb_build_object('success',false,'status',409,'message','Запись уже изменена. Обнови дневник и повтори правку.'); END IF;
 v_before:=to_jsonb(v_row);
 IF v_action IN ('edit','revert') THEN
  IF v_row.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('success',false,'status',409,'message','Сначала восстанови удалённую запись'); END IF;
  IF v_action='revert' THEN
   SELECT * INTO v_audit FROM vilqa.audit WHERE id=(p_req->>'audit_id')::bigint AND entry_id=v_row.id;
   IF NOT FOUND OR v_audit.before_data IS NULL THEN RETURN jsonb_build_object('success',false,'status',400,'message','Версия недоступна'); END IF;
   v_patch:=v_audit.before_data;
  ELSE v_patch:=p_req->'patch'; END IF;
  IF jsonb_typeof(v_patch)<>'object' OR length(trim(v_patch->>'item_name')) NOT BETWEEN 1 AND 100 OR v_patch->>'item_name' IS NULL THEN RETURN jsonb_build_object('success',false,'status',400,'message','Укажи название длиной до 100 символов'); END IF;
  FOREACH f IN ARRAY ARRAY['weight','calories','protein','fats','carbs'] LOOP
   IF jsonb_typeof(v_patch->f) IS DISTINCT FROM 'number' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Проверь числовые значения'); END IF;
   n:=(v_patch->>f)::double precision;
   IF n<0 OR n>100000 OR (f='weight' AND n<=0) THEN RETURN jsonb_build_object('success',false,'status',400,'message','Проверь вес и КБЖУ'); END IF;
  END LOOP;
  IF v_action='revert' THEN
   v_time_patch:=v_before || (SELECT COALESCE(jsonb_object_agg(key,value),'{}') FROM jsonb_each(v_patch) WHERE key=ANY(ARRAY['date','time','datetime','meal_type']));
  ELSE v_time_patch:=vilqa.diary_time_patch(v_patch,v_before,COALESCE(v_profile->>'timezone','Europe/Moscow'));END IF;
  UPDATE vilqa.diary SET item_name=trim(v_patch->>'item_name'),weight=(v_patch->>'weight')::double precision,calories=(v_patch->>'calories')::double precision,protein=(v_patch->>'protein')::double precision,fats=(v_patch->>'fats')::double precision,carbs=(v_patch->>'carbs')::double precision,date=v_time_patch->>'date',time=v_time_patch->>'time',datetime=v_time_patch->>'datetime',meal_type=v_time_patch->>'meal_type',version=version+1,updated_at=now() WHERE id=v_row.id RETURNING * INTO v_row;
 ELSIF v_action='delete' THEN
  IF v_row.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('success',false,'status',409,'message','Запись уже удалена'); END IF;
  UPDATE vilqa.diary SET deleted_at=now(),updated_at=now(),version=version+1 WHERE id=v_row.id RETURNING * INTO v_row;
 ELSE
  IF v_row.deleted_at IS NULL THEN RETURN jsonb_build_object('success',false,'status',409,'message','Запись уже восстановлена'); END IF;
  UPDATE vilqa.diary SET deleted_at=NULL,updated_at=now(),version=version+1 WHERE id=v_row.id RETURNING * INTO v_row;
 END IF;
 INSERT INTO vilqa.audit(entry_id,actor_id,action,before_data,after_data) VALUES(v_row.id,p_actor,v_action,v_before,to_jsonb(v_row));
 v_response:=jsonb_build_object('success',true,'entry',to_jsonb(v_row));
 INSERT INTO vilqa.requests(actor_id,request_id,request_data,response) VALUES(p_actor,v_nonce,p_req,v_response);
 RETURN v_response;
EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow OR invalid_parameter_value OR numeric_value_out_of_range THEN
 RETURN jsonb_build_object('success',false,'status',400,'message','Некорректные данные запроса');
END $function$;
