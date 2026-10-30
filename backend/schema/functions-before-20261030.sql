-- PostgreSQL function definitions captured from the live application before this release.
-- Historical baseline; new delivery functions are in migrations/20261030_fiber_delivery.sql.
CREATE OR REPLACE FUNCTION vilqa.profile_fields(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
 SELECT COALESCE(jsonb_object_agg(key,value),'{}') FROM jsonb_each(COALESCE(p,'{}')) WHERE key=ANY(ARRAY['name','gender','age','height','weight','activity_level','goal','goal_ru','timezone','daily_calories','daily_protein','daily_fats','daily_carbs','bmr','tdee','warning_message']);
$function$;

CREATE OR REPLACE FUNCTION vilqa.access_check(p_user bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
 SELECT p_user=180753266 OR EXISTS(SELECT 1 FROM vilqa.access_members WHERE user_id=p_user AND revoked_at IS NULL)
$function$;

CREATE OR REPLACE FUNCTION vilqa.import_legacy(p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE x jsonb; r vilqa.diary%ROWTYPE; imported integer:=0; differences integer:=0; expected integer;
BEGIN
 IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Expected array'; END IF;
 expected:=jsonb_array_length(p_rows);
 FOR x IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  INSERT INTO vilqa.diary(id,user_id,date,datetime,time,meal_type,item_type,item_name,weight,calories,protein,fats,carbs,legacy_data,created_at,updated_at)
  VALUES((x->>'id')::bigint,COALESCE((x->>'user_id')::bigint,0),x->>'date',x->>'datetime',x->>'time',x->>'meal_type',x->>'item_type',x->>'item_name',(x->>'weight')::double precision,(x->>'calories')::double precision,(x->>'protein')::double precision,(x->>'fats')::double precision,(x->>'carbs')::double precision,x,(x->>'createdAt')::timestamptz,(x->>'updatedAt')::timestamptz)
  ON CONFLICT(id) DO NOTHING RETURNING * INTO r;
  IF FOUND THEN
   imported:=imported+1;
   INSERT INTO vilqa.audit(entry_id,actor_id,action,after_data) VALUES(r.id,180753266,'import',to_jsonb(r));
  END IF;
 END LOOP;
 SELECT count(*) INTO differences FROM jsonb_array_elements(p_rows) AS src(value) LEFT JOIN vilqa.diary d ON d.id=(src.value->>'id')::bigint
 WHERE d.id IS NULL OR d.legacy_data IS DISTINCT FROM src.value OR d.user_id IS DISTINCT FROM COALESCE((src.value->>'user_id')::bigint,0)
 OR d.date IS DISTINCT FROM src.value->>'date' OR d.item_name IS DISTINCT FROM src.value->>'item_name'
 OR d.weight IS DISTINCT FROM (src.value->>'weight')::double precision OR d.calories IS DISTINCT FROM (src.value->>'calories')::double precision
 OR d.protein IS DISTINCT FROM (src.value->>'protein')::double precision OR d.fats IS DISTINCT FROM (src.value->>'fats')::double precision OR d.carbs IS DISTINCT FROM (src.value->>'carbs')::double precision;
 IF differences<>0 THEN RAISE EXCEPTION 'Import verification failed: % mismatches',differences; END IF;
 PERFORM setval(pg_get_serial_sequence('vilqa.diary','id'),GREATEST(COALESCE((SELECT max(id) FROM vilqa.diary),1),1),true);
 RETURN jsonb_build_object('source_count',expected,'imported_count',imported,'target_count',(SELECT count(*) FROM vilqa.diary),'differences',differences,'orphan_count',(SELECT count(*) FROM vilqa.diary WHERE user_id=0),'source_calories',(SELECT sum((value->>'calories')::double precision) FROM jsonb_array_elements(p_rows)),'target_calories',(SELECT sum(calories) FROM vilqa.diary));
END $function$;

CREATE OR REPLACE FUNCTION vilqa.confirm_meal(p_id text, p_user bigint, p_chat bigint, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE d public.vilqa_meal_drafts%ROWTYPE; item jsonb; idx integer:=0; entry_id bigint; ids jsonb:='[]'; f text; n double precision;
BEGIN
 SELECT * INTO d FROM public.vilqa_meal_drafts WHERE draft_id=p_id AND user_id=p_user AND chat_id=p_chat FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('committed',false,'feedback','Эта кнопка устарела. Отправь продукты для нового расчёта.'); END IF;
 IF d.status='saved' THEN RETURN jsonb_build_object('committed',false,'outcome','already_saved','feedback','Этот расчёт уже записан. Повторная запись не нужна.'); END IF;
 IF d.status NOT IN ('pending','cancelled') THEN RETURN jsonb_build_object('committed',false,'feedback','Предыдущая операция требует проверки. Повторно продукты не записываю.'); END IF;
 IF d.expires_at<=now() THEN RETURN jsonb_build_object('committed',false,'outcome','expired','draft_id',p_id,'feedback','Срок действия расчёта истёк. Отправь продукты снова.'); END IF;
 IF d.status='cancelled' AND p_action IS DISTINCT FROM 'restore' THEN
  RETURN jsonb_build_object('committed',false,'outcome','cancelled','draft_id',p_id,'can_restore',true,'feedback','Расчёт отменён. Ничего не записано.');
 END IF;
 IF d.status='pending' AND p_action='restore' THEN RETURN jsonb_build_object('committed',false,'feedback','Этот расчёт ещё не отменён. Используй кнопку записи.'); END IF;
 IF p_action='cancel' THEN
  UPDATE public.vilqa_meal_drafts SET status='cancelled',updated_at=now() WHERE draft_id=p_id;
  RETURN jsonb_build_object('committed',false,'outcome','cancelled','draft_id',p_id,'can_restore',true,'feedback','Расчёт отменён. Ничего не записано.');
 END IF;
 IF p_action NOT IN ('confirm','restore') OR p_action IS NULL THEN RETURN jsonb_build_object('committed',false,'feedback','Эта кнопка устарела.'); END IF;
 IF jsonb_typeof(d.payload->'rows') IS DISTINCT FROM 'array' OR jsonb_array_length(d.payload->'rows') NOT BETWEEN 1 AND 10 THEN RAISE EXCEPTION 'Invalid meal draft'; END IF;
 FOR item IN SELECT x FROM jsonb_array_elements(d.payload->'rows') x LOOP
  idx:=idx+1;
  IF (item->>'user_id')::bigint IS DISTINCT FROM p_user OR length(trim(item->>'item_name')) NOT BETWEEN 1 AND 100 OR item->>'item_name' IS NULL THEN RAISE EXCEPTION 'Invalid draft owner or item'; END IF;
  FOREACH f IN ARRAY ARRAY['weight','calories','protein','fats','carbs'] LOOP
   IF jsonb_typeof(item->f) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Invalid meal number'; END IF;
   n:=(item->>f)::double precision;
   IF n<0 OR n>100000 OR (f='weight' AND n<=0) THEN RAISE EXCEPTION 'Invalid meal value'; END IF;
  END LOOP;
  INSERT INTO vilqa.diary(user_id,date,datetime,time,meal_type,item_type,item_name,weight,calories,protein,fats,carbs,draft_id,item_index)
  VALUES(p_user,item->>'date',item->>'datetime',item->>'time',item->>'meal_type',item->>'item_type',item->>'item_name',(item->>'weight')::double precision,(item->>'calories')::double precision,(item->>'protein')::double precision,(item->>'fats')::double precision,(item->>'carbs')::double precision,p_id,idx)
  RETURNING id INTO entry_id;
  ids:=ids||to_jsonb(entry_id);
  INSERT INTO vilqa.audit(entry_id,actor_id,action,after_data) SELECT id,p_user,'create',to_jsonb(t) FROM vilqa.diary t WHERE id=entry_id;
 END LOOP;
 UPDATE public.vilqa_meal_drafts SET status='saved',saved_row_ids=ids,updated_at=now() WHERE draft_id=p_id;
 RETURN jsonb_build_object('committed',true,'outcome','saved','row_ids',ids,'draft_id',p_id);
END $function$;

CREATE OR REPLACE FUNCTION vilqa.resolve_profile(p_user bigint, p_base jsonb, p_day text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
END $function$;

CREATE OR REPLACE FUNCTION vilqa.edit_profile(p_actor bigint, p_user bigint, p_req jsonb, p_base jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
END $function$;

CREATE OR REPLACE FUNCTION vilqa.registration_profile(p_row jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE uid bigint:=(p_row->>'user_id')::bigint;old jsonb;newdata jsonb:=vilqa.profile_fields(p_row);
BEGIN
 IF uid IS NULL OR uid<=0 THEN RAISE EXCEPTION 'Invalid registered user';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('profile-register:'||uid::text,0));
 SELECT data INTO old FROM vilqa.profiles WHERE user_id=uid FOR UPDATE;
 INSERT INTO vilqa.profiles(user_id,data,version) VALUES(uid,newdata,1) ON CONFLICT(user_id) DO UPDATE SET data=EXCLUDED.data,version=vilqa.profiles.version+1,updated_at=now();
 INSERT INTO vilqa.profile_audit(user_id,actor_id,action,before_data,after_data) VALUES(uid,uid,'registration',old,newdata);
 RETURN vilqa.resolve_profile(uid,p_row);
END $function$;

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

CREATE OR REPLACE FUNCTION vilqa.access_observe(p_user bigint, p_username text, p_name text, p_private boolean DEFAULT true, p_intro boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE u text:=lower(trim(leading '@' from trim(COALESCE(p_username,''))));allowed boolean;reply boolean:=false;i vilqa.access_identities%ROWTYPE;
BEGIN
 IF p_user IS NULL OR p_user<=0 OR p_private IS DISTINCT FROM true THEN RETURN jsonb_build_object('user_id',p_user,'allowed',false,'should_reply',false);END IF;
 IF u !~ '^[a-z0-9_]{5,32}$' THEN u:=NULL;END IF;
 -- Serialize username reassignment; membership itself is always bound to the numeric ID.
 PERFORM pg_advisory_xact_lock(hashtextextended('vilqa-access-identity',0));
 IF u IS NOT NULL THEN UPDATE vilqa.access_identities SET username=NULL,identity_version=identity_version+1 WHERE lower(username)=u AND user_id<>p_user;END IF;
 INSERT INTO vilqa.access_identities(user_id,username,name) VALUES(p_user,u,left(COALESCE(p_name,''),100))
 ON CONFLICT(user_id) DO UPDATE SET username=EXCLUDED.username,name=EXCLUDED.name,last_seen=now(),identity_version=vilqa.access_identities.identity_version+CASE WHEN vilqa.access_identities.username IS DISTINCT FROM EXCLUDED.username THEN 1 ELSE 0 END;
 SELECT * INTO i FROM vilqa.access_identities WHERE user_id=p_user FOR UPDATE;
 allowed:=vilqa.access_check(p_user);
 IF NOT allowed AND p_intro AND (i.last_intro_at IS NULL OR i.last_intro_at<now()-interval '15 minutes') THEN
  UPDATE vilqa.access_identities SET last_intro_at=now() WHERE user_id=p_user;reply:=true;
 END IF;
 RETURN jsonb_build_object('user_id',p_user,'allowed',allowed,'should_reply',reply);
END $function$;

CREATE OR REPLACE FUNCTION vilqa.private_api(p_actor bigint, p_req jsonb, p_profiles jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE target bigint;filtered jsonb;
BEGIN
 IF NOT COALESCE(vilqa.access_check(p_actor),false) THEN RETURN jsonb_build_object('success',false,'status',403,'message','VILQA работает по приглашению. Получить доступ: @vilqa_support_bot','support_url','https://t.me/vilqa_support_bot');END IF;
 IF p_req->>'action' LIKE 'access_%' THEN RETURN vilqa.access_manage(p_actor,p_req);END IF;
 target:=COALESCE((p_req->>'user_id')::bigint,p_actor);
 IF target<>0 AND NOT COALESCE(vilqa.access_check(target),false) THEN RETURN jsonb_build_object('success',false,'status',403,'message','Доступ к этому аккаунту закрыт');END IF;
 SELECT COALESCE(jsonb_agg(p),'[]') INTO filtered FROM jsonb_array_elements(p_profiles) p WHERE vilqa.access_check((p->>'user_id')::bigint);
 RETURN vilqa.api(p_actor,p_req,filtered);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('success',false,'status',400,'message','Некорректный аккаунт');
END $function$;

CREATE OR REPLACE FUNCTION vilqa.access_manage(p_actor bigint, p_req jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE a text:=p_req->>'action';u text:=lower(trim(leading '@' from trim(COALESCE(p_req->>'username',''))));i vilqa.access_identities%ROWTYPE;uid bigint;items jsonb;changed integer;
BEGIN
 IF p_actor IS DISTINCT FROM 180753266 OR NOT COALESCE(vilqa.access_check(p_actor),false) THEN RETURN jsonb_build_object('success',false,'status',403,'message','Управлять доступом может только владелец');END IF;
 IF a='access_list' THEN
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.is_owner DESC,x.active DESC,x.last_seen DESC),'[]') INTO items FROM (
   SELECT ident.user_id,ident.username,ident.name,ident.last_seen,ident.identity_version,(ident.user_id=180753266) AS is_owner,
    (m.user_id IS NOT NULL AND m.revoked_at IS NULL) AS active,m.granted_at,m.revoked_at
   FROM vilqa.access_identities ident LEFT JOIN vilqa.access_members m USING(user_id)
   WHERE m.user_id IS NOT NULL OR ident.last_seen>now()-interval '30 days' ORDER BY ident.last_seen DESC LIMIT 200
  ) x;
  RETURN jsonb_build_object('success',true,'accounts',items);
 END IF;
 IF a IN ('access_lookup','access_grant') THEN
  IF u !~ '^[a-z0-9_]{5,32}$' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Введи Telegram-ник, например @username');END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('vilqa-access-identity',0));
  SELECT * INTO i FROM vilqa.access_identities WHERE lower(username)=u AND last_seen>now()-interval '30 days' FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'status',404,'message','Бот ещё не видел этот аккаунт или сведения устарели. Попроси человека открыть @vilqa_bot и нажать «Начать», затем найди его снова.');END IF;
  IF a='access_lookup' THEN RETURN jsonb_build_object('success',true,'account',jsonb_build_object('user_id',i.user_id,'username',i.username,'name',i.name,'identity_version',i.identity_version,'active',vilqa.access_check(i.user_id),'is_owner',i.user_id=180753266));END IF;
  IF p_req->>'resolved_user_id' IS NULL OR (p_req->>'resolved_user_id')::bigint<>i.user_id OR (p_req->>'identity_version')::integer IS DISTINCT FROM i.identity_version THEN RETURN jsonb_build_object('success',false,'status',409,'message','Аккаунт изменился. Найди его по нику ещё раз.');END IF;
  INSERT INTO vilqa.access_members(user_id,granted_by) VALUES(i.user_id,p_actor) ON CONFLICT(user_id) DO UPDATE SET revoked_at=NULL,granted_by=p_actor,granted_at=CASE WHEN vilqa.access_members.revoked_at IS NOT NULL THEN now() ELSE vilqa.access_members.granted_at END WHERE vilqa.access_members.revoked_at IS NOT NULL;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed>0 THEN INSERT INTO vilqa.access_audit(actor_id,user_id,action) VALUES(p_actor,i.user_id,'grant');END IF;
  RETURN jsonb_build_object('success',true,'user_id',i.user_id,'message','Доступ открыт. Пользователь может вернуться в бот и нажать /start.');
 END IF;
 IF a='access_revoke' THEN
  uid:=(p_req->>'resolved_user_id')::bigint;
  IF uid IS NULL OR uid<=0 OR uid=180753266 THEN RETURN jsonb_build_object('success',false,'status',400,'message','Нельзя отключить доступ владельцу');END IF;
  UPDATE vilqa.access_members SET revoked_at=now() WHERE user_id=uid AND revoked_at IS NULL;GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed>0 THEN INSERT INTO vilqa.access_audit(actor_id,user_id,action) VALUES(p_actor,uid,'revoke');END IF;
  RETURN jsonb_build_object('success',true,'user_id',uid,'message','Доступ отключён. Сохранённые записи не удалены.');
 END IF;
 RETURN jsonb_build_object('success',false,'status',400,'message','Неизвестная операция доступа');
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('success',false,'status',400,'message','Некорректный аккаунт');
END $function$;

CREATE OR REPLACE FUNCTION vilqa.nav_register_executor(p_op jsonb, p_executor text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE o vilqa.nav_operations%ROWTYPE;
BEGIN
 IF p_op IS NULL THEN RETURN NULL;END IF;
 UPDATE vilqa.nav_operations SET executor_id=p_executor WHERE id=(p_op->>'id')::bigint AND status='in_flight' RETURNING * INTO o;
 RETURN CASE WHEN FOUND THEN to_jsonb(o) ELSE NULL END;
END
$function$;

CREATE OR REPLACE FUNCTION vilqa.nav_release_failed(p_executor text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE s vilqa.nav_sessions%ROWTYPE;released integer:=0;
BEGIN
 IF COALESCE(p_executor,'')='' THEN RETURN 0;END IF;
 FOR s IN SELECT ns.* FROM vilqa.nav_sessions ns JOIN vilqa.nav_operations op ON op.id=ns.active_op WHERE op.executor_id=p_executor AND op.status='in_flight' FOR UPDATE OF ns LOOP
  UPDATE vilqa.nav_operations SET status='unknown',error_kind='executor_failed',finished_at=now() WHERE id=s.active_op;
  UPDATE vilqa.nav_sessions SET active_op=NULL WHERE user_id=s.user_id AND active_op=s.active_op;
  released:=released+1;
 END LOOP;
 RETURN released;
END
$function$;

CREATE OR REPLACE FUNCTION vilqa.nav_profile(p_user bigint, p_profile jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE s vilqa.nav_sessions%ROWTYPE;d jsonb;st text;
BEGIN
 INSERT INTO vilqa.nav_sessions(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=p_user FOR UPDATE;
 IF NOT s.imported THEN
  BEGIN d:=COALESCE(NULLIF(p_profile->>'state_data',''),'{}')::jsonb;EXCEPTION WHEN OTHERS THEN d:='{}';END;
  IF jsonb_typeof(d)<>'object' THEN d:='{}';END IF;
  IF COALESCE(p_profile->>'current_state','') LIKE 'recipe_%' THEN d:=d||jsonb_build_object('_resume_state',p_profile->>'current_state');END IF;
  st:=CASE WHEN s.paused THEN '' ELSE COALESCE(p_profile->>'current_state','') END;
  UPDATE vilqa.nav_sessions SET state_data=d,input_state=st,imported=true WHERE user_id=p_user RETURNING * INTO s;
 END IF;
 RETURN p_profile || jsonb_build_object('current_state',s.input_state,'state_data',s.state_data::text,'_recipe_version',s.state_version,'recipe_last_activity',s.last_activity,'recipes_page',s.recipes_page);
END
$function$;

CREATE OR REPLACE FUNCTION vilqa.nav_finish(p_op bigint, p_message bigint, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE o vilqa.nav_operations%ROWTYPE;s vilqa.nav_sessions%ROWTYPE;
BEGIN
 SELECT * INTO o FROM vilqa.nav_operations WHERE id=p_op;
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=o.user_id FOR UPDATE;
 IF s.active_op IS DISTINCT FROM p_op OR o.status<>'in_flight' THEN RETURN jsonb_build_object('user_id',o.user_id,'status','ignored');END IF;
 IF p_error='edit_missing' AND o.method='edit' THEN
  UPDATE vilqa.nav_operations SET method='text',attempts=attempts+1 WHERE id=p_op RETURNING * INTO o;RETURN jsonb_build_object('user_id',o.user_id,'retry',to_jsonb(o),'status','retry');
 END IF;
 IF p_error IS NULL AND (p_message>0 OR o.method='retire') THEN
  IF o.old_message IS NOT NULL AND o.old_message IS DISTINCT FROM p_message THEN UPDATE vilqa.nav_messages SET retired=true WHERE user_id=o.user_id AND message_id=o.old_message;END IF;
  IF o.method='retire' THEN
   UPDATE vilqa.nav_sessions SET current_message=NULL,current_kind=NULL,current_screen=NULL,active_op=NULL WHERE user_id=o.user_id;
  ELSE
   INSERT INTO vilqa.nav_messages(user_id,message_id,kind,revision,payload) VALUES(o.user_id,p_message,o.payload->>'kind',o.revision,o.payload)
   ON CONFLICT(user_id,message_id) DO UPDATE SET revision=EXCLUDED.revision,payload=EXCLUDED.payload,retired=false;
   UPDATE vilqa.nav_sessions SET current_message=p_message,current_kind=o.payload->>'kind',current_screen=o.payload->>'screen',revision=o.revision,active_op=NULL WHERE user_id=o.user_id;
  END IF;
  UPDATE vilqa.nav_operations SET status='succeeded',message_id=p_message,finished_at=now() WHERE id=p_op;
 ELSE
  UPDATE vilqa.nav_operations SET status=CASE WHEN p_error='unknown' THEN 'unknown' ELSE 'failed' END,error_kind=p_error,finished_at=now() WHERE id=p_op;
  UPDATE vilqa.nav_sessions SET active_op=NULL WHERE user_id=o.user_id;
 END IF;
 RETURN jsonb_build_object('user_id',o.user_id,'status',CASE WHEN p_error IS NULL THEN 'succeeded' ELSE COALESCE(p_error,'failed') END);
END
$function$;

CREATE OR REPLACE FUNCTION vilqa.fiber_key(d vilqa.diary)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
 SELECT md5(lower(trim(d.item_name))||':'||COALESCE(d.item_type,'')||':'||COALESCE((d.legacy_data->'fiber_recipe')::text,''));
$function$;

CREATE OR REPLACE FUNCTION vilqa.fiber_signature(d vilqa.diary)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
 SELECT md5(jsonb_build_array(d.item_name,d.item_type,d.weight,d.calories,d.protein,d.fats,d.carbs,d.legacy_data->'fiber_recipe')::text);
$function$;

CREATE OR REPLACE FUNCTION vilqa.fiber_group(d vilqa.diary)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
 SELECT COALESCE('draft:'||d.draft_id,'entry:'||d.id::text)||':'||COALESCE(d.date,'unknown');
$function$;

CREATE OR REPLACE FUNCTION vilqa.nav_claim(p_user bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE s vilqa.nav_sessions%ROWTYPE;o vilqa.nav_operations%ROWTYPE;v_method text;
BEGIN
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=p_user FOR UPDATE;
 IF NOT FOUND OR s.active_op IS NOT NULL OR NOT vilqa.access_check(p_user) THEN RETURN NULL;END IF;
 SELECT * INTO o FROM vilqa.nav_operations WHERE user_id=p_user AND status='pending' ORDER BY id DESC LIMIT 1;
 IF NOT FOUND THEN RETURN NULL;END IF;
 UPDATE vilqa.nav_operations SET status='superseded',finished_at=now() WHERE user_id=p_user AND status='pending' AND id<>o.id;
 v_method:=CASE WHEN o.payload->>'screen'='retire' THEN 'retire' WHEN o.payload->>'kind'='text' AND s.current_kind='text' AND s.current_message IS NOT NULL AND COALESCE((o.payload->>'replace')::boolean,false)=false THEN 'edit' WHEN o.payload->>'kind'='photo' THEN 'photo' ELSE 'text' END;
 UPDATE vilqa.nav_sessions SET active_op=o.id WHERE user_id=p_user RETURNING * INTO s;
 UPDATE vilqa.nav_operations SET status='in_flight',revision=o.id,method=v_method,old_message=s.current_message,old_kind=s.current_kind,attempts=attempts+1 WHERE id=o.id RETURNING * INTO o;
 RETURN to_jsonb(o);
END
$function$;

CREATE OR REPLACE FUNCTION vilqa.archive_recipe(p_actor bigint, p_row jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
BEGIN
 IF NOT COALESCE(vilqa.access_check(p_actor),false) OR (p_row->>'user_id')::bigint IS DISTINCT FROM p_actor OR COALESCE((p_row->>'id')::bigint,0)<=0 THEN RAISE EXCEPTION 'Recipe ownership violation';END IF;
 INSERT INTO vilqa.recipe_deletions(actor_id,recipe_id,snapshot) VALUES(p_actor,(p_row->>'id')::bigint,p_row) ON CONFLICT DO NOTHING;
 RETURN true;
END $function$;

CREATE OR REPLACE FUNCTION vilqa.add_recipe_portion(p_actor bigint, p_req jsonb, p_recipe jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE key text:=p_req->>'request_id';cached vilqa.requests%ROWTYPE;rid bigint;w numeric;n numeric;field text;per100 jsonb:='{}';nutrition jsonb:='{}';stamp jsonb;profile jsonb;entry vilqa.diary%ROWTYPE;result jsonb;name text;
BEGIN
 IF NOT COALESCE(vilqa.access_check(p_actor),false) THEN RETURN jsonb_build_object('success',false,'status',403,'message','Нет доступа к дневнику');END IF;
 IF p_req->>'action' IS DISTINCT FROM 'recipe_add' OR (p_req ? 'user_id' AND (p_req->>'user_id')::bigint IS DISTINCT FROM p_actor) THEN RETURN jsonb_build_object('success',false,'status',403,'message','Можно записать порцию только в свой дневник');END IF;
 IF key IS NULL OR key !~ '^[A-Za-z0-9_-]{16,80}$' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Не указан идентификатор записи');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('vilqa-request:'||p_actor::text||':'||key,0));
 SELECT * INTO cached FROM vilqa.requests WHERE actor_id=p_actor AND request_id=key;
 IF FOUND THEN
  IF cached.request_data IS DISTINCT FROM p_req THEN RETURN jsonb_build_object('success',false,'status',409,'message','Этот запрос уже использован. Открой порцию заново');END IF;
  RETURN cached.response;
 END IF;
 IF jsonb_typeof(p_req->'id') IS DISTINCT FROM 'number' OR p_req->>'id' !~ '^[0-9]+$' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Некорректный рецепт');END IF;
 rid:=(p_req->>'id')::bigint;
 IF p_recipe IS NULL OR p_recipe='null'::jsonb OR (p_recipe->>'id')::bigint IS DISTINCT FROM rid OR (p_recipe->>'user_id')::bigint IS DISTINCT FROM p_actor THEN RETURN jsonb_build_object('success',false,'status',404,'message','Рецепт не найден. Обнови список рецептов');END IF;
 IF jsonb_typeof(p_req->'weight') IS DISTINCT FROM 'number' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Укажи вес порции в граммах');END IF;
 w:=round((p_req->>'weight')::numeric,1);
 IF w<0.1 OR w>10000 THEN RETURN jsonb_build_object('success',false,'status',400,'message','Вес порции должен быть от 0,1 до 10 000 г');END IF;
 name:=trim(p_recipe->>'recipe_name');
 IF name IS NULL OR name='' OR length(name)>100 THEN RETURN jsonb_build_object('success',false,'status',422,'message','Проверь название сохранённого рецепта');END IF;
 FOREACH field IN ARRAY ARRAY['calories','protein','fats','carbs'] LOOP
  IF jsonb_typeof(p_recipe->('per_100g_'||field))='number' THEN n:=(p_recipe->>('per_100g_'||field))::numeric;
  ELSIF jsonb_typeof(p_recipe->('total_'||field))='number' AND jsonb_typeof(p_recipe->'total_weight')='number' AND (p_recipe->>'total_weight')::numeric>0 THEN n:=(p_recipe->>('total_'||field))::numeric*100/(p_recipe->>'total_weight')::numeric;
  ELSE RETURN jsonb_build_object('success',false,'status',422,'message','В рецепте не хватает КБЖУ для записи порции');END IF;
  IF n<0 OR n>(CASE WHEN field='calories' THEN 100000 ELSE 10000 END) OR n*w/100>(CASE WHEN field='calories' THEN 100000 ELSE 10000 END) THEN RETURN jsonb_build_object('success',false,'status',422,'message','Проверь КБЖУ сохранённого рецепта');END IF;
  per100:=per100||jsonb_build_object(field,n);nutrition:=nutrition||jsonb_build_object(field,round(n*w/100,1));
 END LOOP;
 profile:=vilqa.resolve_profile(p_actor,'{}');
 stamp:=vilqa.diary_time_patch(jsonb_build_object('date',p_req->'date','time',p_req->'time'),'{}',COALESCE(profile->>'timezone','Europe/Moscow'));
 INSERT INTO vilqa.diary(user_id,date,time,datetime,meal_type,item_type,item_name,weight,calories,protein,fats,carbs,legacy_data)
 VALUES(p_actor,stamp->>'date',stamp->>'time',stamp->>'datetime',stamp->>'meal_type','recipe',name,w,(nutrition->>'calories')::double precision,(nutrition->>'protein')::double precision,(nutrition->>'fats')::double precision,(nutrition->>'carbs')::double precision,jsonb_build_object('source','saved_recipe','recipe_id',rid,'recipe_per_100g',per100,'fiber_recipe',jsonb_build_object('id',rid,'total_weight',p_recipe->'total_weight','ingredients',p_recipe->'ingredients'))) RETURNING * INTO entry;
 INSERT INTO vilqa.audit(entry_id,actor_id,action,before_data,after_data) VALUES(entry.id,p_actor,'create',NULL,to_jsonb(entry));
 result:=jsonb_build_object('success',true,'entry',to_jsonb(entry));
 INSERT INTO vilqa.requests(actor_id,request_id,request_data,response) VALUES(p_actor,key,p_req,result);
 RETURN result;
EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow OR invalid_parameter_value OR numeric_value_out_of_range THEN
 RETURN jsonb_build_object('success',false,'status',400,'message','Проверь вес, дату и время порции');
END $function$;

CREATE OR REPLACE FUNCTION vilqa.nav_ingress(p_user bigint, p_event text, p_callback text, p_message bigint, p_command text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE s vilqa.nav_sessions%ROWTYPE;a text:=COALESCE(p_callback,'');v bigint;m vilqa.nav_messages%ROWTYPE;
BEGIN
 IF NOT vilqa.access_check(p_user) THEN RETURN jsonb_build_object('allowed',false,'reason','access');END IF;
 INSERT INTO vilqa.nav_sessions(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=p_user FOR UPDATE;
 IF EXISTS(SELECT 1 FROM vilqa.nav_events WHERE user_id=p_user AND event_key=p_event) THEN RETURN jsonb_build_object('allowed',false,'reason','duplicate');END IF;
 IF a LIKE 'n:%' THEN
  IF a !~ '^n:[0-9]{1,18}:[a-z_]{1,40}$' THEN RETURN jsonb_build_object('allowed',false,'reason','stale');END IF;
  v:=split_part(a,':',2)::bigint;a:=split_part(a,':',3);
  SELECT * INTO m FROM vilqa.nav_messages WHERE user_id=p_user AND message_id=p_message;
  IF s.active_op IS NOT NULL OR s.current_message IS DISTINCT FROM p_message OR s.revision<>v OR m.retired IS DISTINCT FROM false
   OR (a LIKE 'recipe_%' AND COALESCE((m.payload->>'recipe_version')::bigint,-1)<>s.state_version)
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(m.payload->'keyboard','[]')) r, jsonb_array_elements(r->'row'->'buttons') b WHERE b->'additionalFields'->>'callback_data'=a)
  THEN RETURN jsonb_build_object('allowed',false,'reason','stale');END IF;
 ELSIF a LIKE 'recipe_%' OR a='meal_delete_last' THEN
  RETURN jsonb_build_object('allowed',false,'reason','stale');
 ELSIF a LIKE 'menu_%' AND a NOT IN ('menu_main','menu_food_entry','menu_profile','menu_stats','menu_recipes','menu_recommendation') THEN
  RETURN jsonb_build_object('allowed',false,'reason','stale');
 END IF;
 INSERT INTO vilqa.nav_events VALUES(p_user,p_event,now());
 IF a='recipe_next' THEN UPDATE vilqa.nav_sessions SET recipes_page=recipes_page+1 WHERE user_id=p_user;
 ELSIF a='recipe_prev' THEN UPDATE vilqa.nav_sessions SET recipes_page=greatest(recipes_page-1,0) WHERE user_id=p_user;
 ELSIF a='menu_recipes' OR p_command ~* '^/recipes(@vilqa_bot)?[[:space:]]*$' THEN UPDATE vilqa.nav_sessions SET recipes_page=0 WHERE user_id=p_user;END IF;
 IF p_command ~* '^/(menu|start|recipes)(@vilqa_bot)?[[:space:]]*$' OR a IN ('menu_main','menu_food_entry','menu_profile','menu_stats','menu_recipes','menu_recommendation','recipe_pause') THEN
  UPDATE vilqa.nav_sessions SET state_data=CASE WHEN input_state<>'' THEN state_data||jsonb_build_object('_resume_state',input_state) ELSE state_data END,input_state='',paused=true,state_version=state_version+1,last_activity=now() WHERE user_id=p_user;
 END IF;
 RETURN jsonb_build_object('allowed',true,'action',a,'user_id',p_user,'chat_id',p_user);
END
$function$;

CREATE OR REPLACE FUNCTION vilqa.nav_state_write(p_user bigint, p_event text, p_expected bigint, p_state text, p_data jsonb, p_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE s vilqa.nav_sessions%ROWTYPE;r jsonb;d jsonb;st text;
BEGIN
 IF NOT vilqa.access_check(p_user) THEN RAISE EXCEPTION 'Navigation access denied';END IF;
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=p_user FOR UPDATE;
 SELECT result INTO r FROM vilqa.nav_state_events WHERE user_id=p_user AND event_key=p_event;
 IF FOUND THEN RETURN r;END IF;
 IF s.state_version IS DISTINCT FROM p_expected THEN
  IF p_mode='finished' THEN RETURN jsonb_build_object('user_id',p_user,'chat_id',p_user,'state_data',s.state_data::text,'current_state',s.input_state,'stale_job',true,'_recipe_version',s.state_version);END IF;
  RAISE EXCEPTION 'Recipe state changed; repeat the action';
 END IF;
 d:=COALESCE(p_data,s.state_data);st:=COALESCE(p_state,s.input_state);
 IF p_mode='start' THEN
  IF s.state_data ? 'recipe_draft' THEN RETURN jsonb_build_object('user_id',p_user,'chat_id',p_user,'state_data',s.state_data::text,'current_state',s.input_state,'_recipe_version',s.state_version,'existing_draft',true);END IF;
  d:=jsonb_build_object('recipe_draft',jsonb_build_object('draft_id',p_event,'recipe_name','','ingredients_raw','[]'::jsonb,'status','collecting'));st:='recipe_naming';
 ELSIF p_mode='pause' THEN st:='';d:=CASE WHEN s.input_state<>'' THEN s.state_data||jsonb_build_object('_resume_state',s.input_state) ELSE s.state_data END;
 ELSIF p_mode='resume' THEN
  IF NOT s.state_data ? 'recipe_draft' THEN RAISE EXCEPTION 'Recipe draft missing';END IF;
  st:=CASE WHEN d->>'_resume_state' IN ('recipe_naming','recipe_ingredients','recipe_weight','recipe_ai_processing') THEN d->>'_resume_state' WHEN COALESCE(d->'recipe_draft'->>'recipe_name','')='' THEN 'recipe_naming' WHEN COALESCE(d->'recipe_draft'->>'total_weight_raw','')<>'' THEN 'recipe_ai_processing' ELSE 'recipe_ingredients' END;
 ELSIF p_mode IN ('delete','finished') THEN st:='';d:='{}';END IF;
 IF st<>'' THEN d:=d||jsonb_build_object('_resume_state',st);END IF;
 UPDATE vilqa.nav_sessions SET input_state=st,state_data=d,state_version=state_version+1,paused=(st=''),imported=true,last_activity=now() WHERE user_id=p_user RETURNING * INTO s;
 r:=jsonb_build_object('user_id',p_user,'chat_id',p_user,'current_state',s.input_state,'state_data',s.state_data::text,'_recipe_version',s.state_version);
 INSERT INTO vilqa.nav_state_events VALUES(p_user,p_event,r);RETURN r;
END
$function$;

CREATE OR REPLACE FUNCTION vilqa.nav_request(p_user bigint, p_event text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE s vilqa.nav_sessions%ROWTYPE;
BEGIN
 IF NOT vilqa.access_check(p_user) THEN RETURN NULL;END IF;
 IF p_payload->>'kind' NOT IN ('text','photo','retire') OR p_payload->>'screen' IS NULL THEN RAISE EXCEPTION 'Invalid navigation payload';END IF;
 INSERT INTO vilqa.nav_sessions(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=p_user FOR UPDATE;
 IF EXISTS(SELECT 1 FROM vilqa.nav_operations WHERE user_id=p_user AND event_key=p_event) THEN RETURN NULL;END IF;
 IF p_payload->>'screen' LIKE 'recipes_%' THEN
  IF p_payload->>'has_prev'='true' THEN p_payload:=jsonb_set(p_payload,'{keyboard}',(p_payload->'keyboard')||'[{"row":{"buttons":[{"text":"← Предыдущие рецепты","additionalFields":{"callback_data":"recipe_prev"}}]}}]'::jsonb);END IF;
  IF p_payload->>'has_next'='true' THEN p_payload:=jsonb_set(p_payload,'{keyboard}',(p_payload->'keyboard')||'[{"row":{"buttons":[{"text":"Следующие рецепты →","additionalFields":{"callback_data":"recipe_next"}}]}}]'::jsonb);END IF;
 END IF;
 INSERT INTO vilqa.nav_operations(user_id,event_key,payload) VALUES(p_user,p_event,p_payload||jsonb_build_object('recipe_version',s.state_version));
 RETURN vilqa.nav_claim(p_user);
END
$function$;

CREATE OR REPLACE FUNCTION vilqa.read_stats_fast(p_user bigint, p_timezone text DEFAULT 'Europe/Moscow'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE p jsonb;z text:=COALESCE(NULLIF(p_timezone,''),'Europe/Moscow');day text;logs jsonb;
BEGIN
 IF NOT COALESCE(vilqa.access_check(p_user),false) THEN RETURN NULL;END IF;
 SELECT data INTO p FROM vilqa.profiles WHERE user_id=p_user;
 IF NOT FOUND OR NOT (p ?& ARRAY['daily_calories','daily_protein','daily_fats','daily_carbs']) THEN RETURN jsonb_build_object('fallback',true,'user_id',p_user,'timezone',z);END IF;
 day:=to_char(now() AT TIME ZONE z,'YYYY-MM-DD');
 SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.time,d.id),'[]') INTO logs FROM vilqa.diary d WHERE user_id=p_user AND date=day AND deleted_at IS NULL;
 RETURN jsonb_build_object('user_id',p_user,'timezone',z,'snapshot',jsonb_build_object('profile',p||jsonb_build_object('user_id',p_user),'logs',logs));
END $function$;

CREATE OR REPLACE FUNCTION vilqa.nav_prepare_fast(p_op jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE rows jsonb:='[]';buttons jsonb;r jsonb;b jsonb;a jsonb;action text;style text;title text;signature text:='';shape text:='';multi boolean:=false;layout_key text;route integer;n integer;
BEGIN
 IF p_op IS NULL OR p_op->>'id' IS NULL THEN RETURN NULL;END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_op->'payload'->'keyboard','[]')) LOOP
  buttons:='[]';n:=jsonb_array_length(r->'row'->'buttons');multi:=multi OR n>1;shape:=shape||CASE WHEN shape='' THEN '' ELSE ',' END||n::text;
  FOR b IN SELECT value FROM jsonb_array_elements(r->'row'->'buttons') LOOP
   a:=COALESCE(b->'additionalFields','{}');action:=a->>'callback_data';title:=COALESCE(b->>'text','');
   IF action IS NOT NULL AND action<>'' THEN
    IF action !~ '^[a-z_]{1,40}$' THEN RAISE EXCEPTION 'Invalid navigation action';END IF;
    style:=CASE WHEN action='recipe_delete_confirm' OR action ~ '^(meal_cancel|recipe_cancel)(:|$)' OR title ~* 'отмен' THEN 'danger' WHEN action='menu_main' OR title ~* 'назад|главное[[:space:]]*меню|в[[:space:]]*меню' THEN '' ELSE 'success' END;
    action:='n:'||(p_op->>'revision')||':'||action;IF length(action)>64 THEN RAISE EXCEPTION 'Navigation callback too long';END IF;
    a:=a||jsonb_build_object('callback_data',action,'style',style);signature:=signature||'C';
   ELSIF a ? 'web_app' THEN
    a:=a||jsonb_build_object('style',CASE p_op->'payload'->>'screen' WHEN 'profile' THEN 'success' WHEN 'main' THEN 'primary' ELSE '' END);signature:=signature||'W';
   ELSE signature:=signature||'C';
   END IF;
   buttons:=buttons||jsonb_build_array(b||jsonb_build_object('additionalFields',a));
  END LOOP;
  rows:=rows||jsonb_build_array(jsonb_build_object('row',jsonb_build_object('buttons',buttons)));
 END LOOP;
 layout_key:=CASE WHEN p_op->>'method'='retire' THEN 'retire' ELSE (p_op->>'method')||':'||signature||CASE WHEN multi THEN ':'||shape ELSE '' END END;
 SELECT v.i INTO route FROM (VALUES ('text:C',0),('text:CC',1),('text:CCC',2),('text:CCCC',3),('text:CCCCC',4),('text:CCCCCC',5),('edit:C',6),('edit:CC',7),('edit:CCC',8),('edit:CCCC',9),('edit:CCCCC',10),('edit:CCCCCC',11),('photo:CWCCC',12),('photo:WC',13),('retire',14),('photo:CWCCC:1,1,2,1',15)) v(k,i) WHERE v.k=layout_key;
 IF route IS NULL THEN RAISE EXCEPTION 'Unsupported navigation layout: %',layout_key;END IF;
 RETURN p_op||jsonb_build_object('keyboard',jsonb_build_object('rows',rows),'route',route);
END $function$;

CREATE OR REPLACE FUNCTION vilqa.ensure_profile(p_base jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
END $function$;

CREATE OR REPLACE FUNCTION vilqa.diary_time_patch(p_patch jsonb, p_current jsonb, p_timezone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
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
END $function$;

CREATE OR REPLACE FUNCTION vilqa.fast_interface(p_user bigint, p_chat bigint, p_private boolean, p_event text, p_callback text, p_message bigint, p_command text, p_name text, p_username text, p_main jsonb, p_food jsonb, p_executor text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE a text:=regexp_replace(COALESCE(p_callback,''),'^n:[0-9]+:','');e jsonb;d jsonb;o jsonb;k text;t timestamptz:=clock_timestamp();
BEGIN
 IF p_private IS DISTINCT FROM true OR p_user IS NULL OR p_user<=0 OR p_chat IS DISTINCT FROM p_user THEN RETURN jsonb_build_object('route','ignore','event',jsonb_build_object('allowed',false,'reason','private'));END IF;
 IF NOT (COALESCE(p_command,'') ~* '^/(menu|start)(@vilqa_bot)?[[:space:]]*$' OR a IN ('menu_main','menu_food_entry','menu_stats') OR a ~ '^meal_(confirm|cancel|restore):[A-Za-z0-9_-]{1,48}$') THEN RETURN jsonb_build_object('route','legacy');END IF;
 -- Unknown/incomplete profiles retain the existing registration and invitation flow.
 IF NOT COALESCE(vilqa.access_check(p_user),false) THEN RETURN jsonb_build_object('route','legacy');END IF;
 SELECT data INTO d FROM vilqa.profiles WHERE user_id=p_user AND data ? 'daily_calories';
 IF NOT FOUND THEN RETURN jsonb_build_object('route','legacy');END IF;
 IF COALESCE(p_event,'') !~ '^[0-9]{1,30}$' THEN RAISE EXCEPTION 'Invalid trusted Telegram event';END IF;
 e:=vilqa.nav_ingress(p_user,p_event,COALESCE(p_callback,''),COALESCE(p_message,0),COALESCE(p_command,''));
 IF e->>'allowed' IS DISTINCT FROM 'true' THEN RETURN jsonb_build_object('route','ignore','event',e,'user_id',p_user,'chat_id',p_chat);END IF;
 PERFORM vilqa.access_observe(p_user,p_username,p_name,true,false);
 IF a ~ '^meal_(confirm|cancel|restore):[A-Za-z0-9_-]{1,48}$' THEN
  RETURN jsonb_build_object('route','meal','event',e,'user_id',p_user,'chat_id',p_chat,'timezone',COALESCE(d->>'timezone','Europe/Moscow'),'action',split_part(split_part(a,':',1),'meal_',2),'draft_id',split_part(a,':',2));
 END IF;
 IF a='menu_stats' THEN
  RETURN jsonb_build_object('route','stats','event',e,'user_id',p_user,'chat_id',p_chat,'timezone',COALESCE(d->>'timezone','Europe/Moscow'),'guard_ms',round((extract(epoch FROM clock_timestamp()-t)*1000)::numeric,2));
 END IF;
 k:=CASE WHEN a='menu_food_entry' THEN 'food' ELSE 'main' END;
 IF (CASE k WHEN 'food' THEN p_food ELSE p_main END)->>'screen' IS DISTINCT FROM k THEN RAISE EXCEPTION 'Invalid trusted screen payload';END IF;
 o:=vilqa.nav_register_executor(vilqa.nav_request(p_user,p_event||':'||k,CASE k WHEN 'food' THEN p_food ELSE p_main END),p_executor);
 RETURN jsonb_build_object('route','deliver','event',e,'op',o,'user_id',p_user,'chat_id',p_chat,'guard_ms',round((extract(epoch FROM clock_timestamp()-t)*1000)::numeric,2));
END $function$;

CREATE OR REPLACE FUNCTION vilqa.start_recipe_from_app(p_actor bigint, p_request text, p_legacy jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
END $function$;

CREATE OR REPLACE FUNCTION vilqa.status_begin(p_user bigint, p_kind text, p_scope text, p_owner text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r vilqa.processing_status%ROWTYPE;k text:=md5(COALESCE(p_scope,''));
BEGIN
 IF NOT COALESCE(vilqa.access_check(p_user),false) OR p_kind NOT IN ('food','stats','recommendations','recipe','voice','fiber') OR p_owner !~ '^[A-Za-z0-9_-]{1,80}$' THEN RETURN;END IF;
 INSERT INTO vilqa.processing_status(user_id,kind,scope,owner_execution) VALUES(p_user,p_kind,k,p_owner)
 ON CONFLICT(user_id,kind,scope) DO UPDATE SET owner_execution=EXCLUDED.owner_execution,state='active',message_id=NULL,frame=0,expires_at=now()+interval '5 minutes',updated_at=now()
 WHERE vilqa.processing_status.state<>'active' OR vilqa.processing_status.expires_at<now()
 RETURNING * INTO r;
 IF FOUND THEN RETURN NEXT to_jsonb(r);END IF;
END $function$;

CREATE OR REPLACE FUNCTION vilqa.status_attach(p_user bigint, p_kind text, p_scope text, p_owner text, p_message bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r vilqa.processing_status%ROWTYPE;
BEGIN
 UPDATE vilqa.processing_status SET message_id=NULLIF(p_message,0),updated_at=now() WHERE user_id=p_user AND kind=p_kind AND scope=p_scope AND owner_execution=p_owner AND state='active' RETURNING * INTO r;
 RETURN to_jsonb(r);
END $function$;

CREATE OR REPLACE FUNCTION vilqa.status_tick(p_user bigint, p_kind text, p_scope text, p_owner text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r vilqa.processing_status%ROWTYPE;
BEGIN
 UPDATE vilqa.processing_status SET frame=frame%3+1,state=CASE WHEN expires_at<=now() THEN 'expired' ELSE state END,updated_at=now()
 WHERE user_id=p_user AND kind=p_kind AND scope=p_scope AND owner_execution=p_owner AND state='active' AND message_id IS NOT NULL RETURNING * INTO r;
 IF FOUND THEN RETURN NEXT to_jsonb(r)||jsonb_build_object('expired',r.state='expired');END IF;
END $function$;

CREATE OR REPLACE FUNCTION vilqa.status_finish(p_user bigint, p_kind text, p_scope text, p_owner text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r vilqa.processing_status%ROWTYPE;
BEGIN
 UPDATE vilqa.processing_status SET state='finished',updated_at=now() WHERE user_id=p_user AND kind=p_kind AND scope=md5(COALESCE(p_scope,'')) AND owner_execution=p_owner AND state='active' RETURNING * INTO r;
 RETURN COALESCE(to_jsonb(r),jsonb_build_object('user_id',p_user,'message_id',NULL));
END $function$;

CREATE OR REPLACE FUNCTION vilqa.status_abort(p_owner text)
 RETURNS SETOF jsonb
 LANGUAGE sql
AS $function$
 UPDATE vilqa.processing_status SET state='failed',updated_at=now() WHERE owner_execution=p_owner AND state='active' RETURNING to_jsonb(processing_status);
$function$;

CREATE OR REPLACE FUNCTION vilqa.fiber_reserve_notice(p jsonb)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
AS $function$
BEGIN
 UPDATE vilqa.fiber_jobs SET notified_revision=revision WHERE job_key=p->>'job_key' AND revision=(p->>'revision')::integer AND token=p->>'token' AND status='done' AND notify_chat AND notified_revision<revision AND vilqa.access_check(user_id);
 IF FOUND THEN RETURN NEXT p;END IF;
END $function$;

CREATE OR REPLACE FUNCTION vilqa.fiber_api(p_actor bigint, p_req jsonb, p_profiles jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb;uid bigint:=COALESCE((p_req->>'user_id')::bigint,p_actor);target numeric;f jsonb;v numeric;d vilqa.diary%ROWTYPE;
BEGIN
 IF NOT vilqa.access_check(p_actor) OR (uid<>p_actor AND NOT EXISTS(SELECT 1 FROM vilqa.admins WHERE user_id=p_actor)) OR (uid<>0 AND NOT vilqa.access_check(uid)) THEN RETURN jsonb_build_object('success',false,'status',403,'message','Нет доступа');END IF;
 IF p_req->>'action'='fiber_settings' THEN
  IF jsonb_typeof(p_req->'weight')<>'number' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Укажи ориентир клетчатки');END IF;
  target:=(p_req->>'weight')::numeric;IF target<1 OR target>100 THEN RETURN jsonb_build_object('success',false,'status',400,'message','Ориентир должен быть от 1 до 100 г');END IF;
  INSERT INTO vilqa.fiber_settings(user_id,daily_target) VALUES(uid,round(target,1)) ON CONFLICT(user_id) DO UPDATE SET daily_target=EXCLUDED.daily_target,updated_at=now();
  RETURN jsonb_build_object('success',true,'daily_fiber',round(target,1));
 END IF;
 IF p_req->>'action'='profile_edit' AND p_req->'patch' ? 'daily_fiber' THEN
  IF jsonb_typeof(p_req#>'{patch,daily_fiber}')<>'number' OR (p_req#>>'{patch,daily_fiber}')::numeric NOT BETWEEN 1 AND 100 THEN RETURN jsonb_build_object('success',false,'status',400,'message','Ориентир клетчатки должен быть от 1 до 100 г');END IF;
 END IF;
 IF p_req->>'action'='edit' AND p_req->'patch' ? 'fiber' THEN
  IF jsonb_typeof(p_req#>'{patch,fiber}') NOT IN ('number','null') THEN RETURN jsonb_build_object('success',false,'status',400,'message','Проверь клетчатку');END IF;
  v:=(p_req#>>'{patch,fiber}')::numeric;
  IF v<0 OR v>COALESCE((p_req#>>'{patch,weight}')::numeric,10000) THEN RETURN jsonb_build_object('success',false,'status',400,'message','Клетчатка не может превышать вес порции');END IF;
 END IF;
 r:=vilqa.private_api(p_actor,p_req,p_profiles);IF r->>'success'<>'true' THEN RETURN r;END IF;
 IF p_req->>'action'='profile_edit' AND p_req->'patch' ? 'daily_fiber' THEN
  INSERT INTO vilqa.fiber_settings(user_id,daily_target) VALUES(uid,round((p_req#>>'{patch,daily_fiber}')::numeric,1)) ON CONFLICT(user_id) DO UPDATE SET daily_target=EXCLUDED.daily_target,updated_at=now();
 END IF;
 IF p_req->>'action'='edit' AND p_req->'patch' ? 'fiber' THEN
  SELECT * INTO d FROM vilqa.diary WHERE id=(p_req->>'id')::bigint AND user_id=uid;
  IF FOUND AND d.version=(r#>>'{entry,version}')::integer THEN
   UPDATE vilqa.diary SET fiber=v,fiber_status=CASE WHEN v IS NULL THEN 'unknown' ELSE 'manual' END,fiber_basis=vilqa.fiber_signature(d) WHERE id=d.id RETURNING * INTO d;
   r:=jsonb_set(r,'{entry}',to_jsonb(d));
   INSERT INTO vilqa.fiber_audit(entry_id,before_data,after_data) VALUES(d.id,NULL,jsonb_build_object('fiber',v,'source','manual','actor',p_actor));
  END IF;
 END IF;
 SELECT daily_target INTO target FROM vilqa.fiber_settings WHERE user_id=uid;target:=COALESCE(target,25);
 IF r ? 'profile' THEN r:=jsonb_set(r,'{profile}',(r->'profile')||jsonb_build_object('daily_fiber',target));END IF;
 IF p_req->>'action'='day' THEN
  SELECT jsonb_build_object('fiber',COALESCE(sum(fiber),0),'fiber_known',count(fiber),'fiber_unknown',count(*) FILTER(WHERE fiber IS NULL)) INTO f FROM vilqa.diary WHERE user_id=uid AND date=r->>'date' AND deleted_at IS NULL;
  r:=jsonb_set(r,'{totals}',(r->'totals')||f);
 END IF;
 RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION vilqa.fiber_claim(p_executor text)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE j vilqa.fiber_jobs%ROWTYPE;items jsonb;days jsonb;profile jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM vilqa.fiber_config WHERE enabled) THEN RETURN;END IF;
 SELECT * INTO j FROM vilqa.fiber_jobs WHERE (status='pending' AND ready_at<=now() OR status='processing' AND lease_until<now()) AND attempts<3 AND vilqa.access_check(user_id) ORDER BY ready_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN;END IF;
 UPDATE vilqa.fiber_jobs SET status='processing',token=p_executor||':'||revision,attempts=attempts+1,lease_until=now()+interval '5 minutes',updated_at=now() WHERE job_key=j.job_key RETURNING * INTO j;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',d.id,'name',d.item_name,'weight',d.weight,'calories',d.calories,'protein',d.protein,'fats',d.fats,'carbs',d.carbs,'signature',vilqa.fiber_signature(d),'cache_key',vilqa.fiber_key(d),'fiber',CASE WHEN d.fiber_basis=vilqa.fiber_signature(d) THEN d.fiber END,'cached_per100',c.per100,'recipe',d.legacy_data->'fiber_recipe') ORDER BY d.id),'[]') INTO items FROM vilqa.diary d LEFT JOIN vilqa.fiber_cache c ON c.cache_key=vilqa.fiber_key(d) AND c.updated_at>now()-interval '180 days' WHERE vilqa.fiber_group(d)=j.job_key AND d.deleted_at IS NULL;
 SELECT jsonb_agg(DISTINCT date) INTO days FROM vilqa.diary d WHERE vilqa.fiber_group(d)=j.job_key;
 profile:=vilqa.resolve_profile(j.user_id,'{}');
 RETURN NEXT jsonb_build_object('job_key',j.job_key,'user_id',j.user_id,'revision',j.revision,'token',j.token,'items',items,'dates',days,'profile',jsonb_build_object('daily_calories',profile->'daily_calories','timezone',COALESCE(profile->>'timezone','Europe/Moscow')));
END $function$;

CREATE OR REPLACE FUNCTION vilqa.fiber_apply(p_job jsonb, p_values jsonb)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE j vilqa.fiber_jobs%ROWTYPE;r jsonb;d vilqa.diary%ROWTYPE;before jsonb;v numeric;dt text;summary jsonb;meal numeric;known integer;cnt integer;total numeric;cal numeric;target numeric;profile jsonb;unresolved integer;
BEGIN
 PERFORM id FROM vilqa.diary WHERE id IN (SELECT (value->>'id')::bigint FROM jsonb_array_elements(p_values)) ORDER BY id FOR UPDATE;
 SELECT * INTO j FROM vilqa.fiber_jobs WHERE job_key=p_job->>'job_key' FOR UPDATE;
 IF NOT FOUND OR j.status<>'processing' OR j.token IS DISTINCT FROM p_job->>'token' OR j.revision<>(p_job->>'revision')::integer OR NOT vilqa.access_check(j.user_id) THEN RETURN;END IF;
 IF jsonb_typeof(p_values)<>'array' OR jsonb_array_length(p_values)<>jsonb_array_length(p_job->'items') THEN RAISE EXCEPTION 'Invalid fiber item count';END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(p_values) LOOP
  SELECT * INTO d FROM vilqa.diary WHERE id=(r->>'id')::bigint AND user_id=j.user_id FOR UPDATE;
  IF NOT FOUND OR d.deleted_at IS NOT NULL OR vilqa.fiber_signature(d) IS DISTINCT FROM r->>'signature' THEN
   UPDATE vilqa.fiber_jobs SET status='pending',ready_at=now()+interval '9 seconds',token=NULL WHERE job_key=j.job_key;RETURN;
  END IF;
  v:=NULL;
  IF jsonb_typeof(r->'fiber')='number' THEN v:=round((r->>'fiber')::numeric,1);IF v<0 OR v>d.weight THEN RAISE EXCEPTION 'Invalid fiber quantity';END IF;END IF;
  before:=jsonb_build_object('fiber',d.fiber,'fiber_status',d.fiber_status);
  UPDATE vilqa.diary SET fiber=v,fiber_status=CASE WHEN v IS NULL THEN 'unknown' WHEN d.fiber_status='manual' THEN 'manual' ELSE 'estimated' END,fiber_basis=vilqa.fiber_signature(d) WHERE id=d.id;
  INSERT INTO vilqa.fiber_audit(entry_id,job_key,revision,before_data,after_data) VALUES(d.id,j.job_key,j.revision,before,jsonb_build_object('fiber',v,'source','ai_estimate'));
  IF v IS NOT NULL AND d.weight>0 AND d.fiber_status<>'manual' THEN INSERT INTO vilqa.fiber_cache(cache_key,per100) VALUES(vilqa.fiber_key(d),v*100/d.weight) ON CONFLICT(cache_key) DO UPDATE SET per100=EXCLUDED.per100,updated_at=now();END IF;
 END LOOP;
 UPDATE vilqa.fiber_jobs SET status='done',lease_until=NULL,updated_at=now() WHERE job_key=j.job_key;
 SELECT min(q.date) INTO dt FROM vilqa.diary q WHERE vilqa.fiber_group(q)=j.job_key;
 dt:=COALESCE(dt,right(j.job_key,10));
 SELECT COALESCE(sum(q.fiber),0),count(q.fiber),count(*) INTO meal,known,cnt FROM vilqa.diary q WHERE vilqa.fiber_group(q)=j.job_key AND q.deleted_at IS NULL;
 SELECT COALESCE(sum(fiber),0),count(*) FILTER(WHERE fiber IS NULL),COALESCE(sum(calories),0) INTO total,unresolved,cal FROM vilqa.diary WHERE user_id=j.user_id AND date=dt AND deleted_at IS NULL;
 SELECT daily_target INTO target FROM vilqa.fiber_settings WHERE user_id=j.user_id;target:=COALESCE(target,25);profile:=vilqa.resolve_profile(j.user_id,'{}');
 IF j.notified_revision>=j.revision THEN RETURN;END IF;
 RETURN NEXT jsonb_build_object('job_key',j.job_key,'revision',j.revision,'token',j.token,'user_id',j.user_id,'date',dt,'meal_fiber',CASE WHEN cnt=0 THEN NULL ELSE meal END,'meal_unknown',cnt-known,'deleted',cnt=0,'day_fiber',total,'day_unknown',unresolved,'target',target,'remaining',GREATEST(0,target-total),'remaining_calories',GREATEST(0,COALESCE((profile->>'daily_calories')::numeric,0)-cal));
END $function$;

CREATE OR REPLACE FUNCTION vilqa.fiber_enqueue()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE k text;changed boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM vilqa.fiber_config WHERE enabled) THEN RETURN NEW;END IF;
 IF NOT COALESCE(vilqa.access_check(NEW.user_id),false) THEN RETURN NEW;END IF;
 IF TG_OP='INSERT' THEN changed:=true;
 ELSE changed:=vilqa.fiber_signature(NEW) IS DISTINCT FROM vilqa.fiber_signature(OLD) OR NEW.date IS DISTINCT FROM OLD.date OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at;
 END IF;
 IF NOT changed THEN RETURN NEW;END IF;
 IF TG_OP='INSERT' OR vilqa.fiber_signature(NEW) IS DISTINCT FROM vilqa.fiber_signature(OLD) THEN
  NEW.fiber:=NULL;NEW.fiber_status:='pending';NEW.fiber_basis:=NULL;
 END IF;
 k:=vilqa.fiber_group(NEW);
 INSERT INTO vilqa.fiber_jobs(job_key,user_id,ready_at,notify_chat) VALUES(k,NEW.user_id,now()+interval '60 seconds',TG_OP='INSERT')
 ON CONFLICT(job_key) DO UPDATE SET notify_chat=EXCLUDED.notify_chat,revision=vilqa.fiber_jobs.revision+1,status='pending',attempts=0,ready_at=now()+interval '60 seconds',lease_until=NULL,token=NULL,updated_at=now();
 IF TG_OP='UPDATE' AND NEW.date IS DISTINCT FROM OLD.date THEN
  INSERT INTO vilqa.fiber_jobs(job_key,user_id,ready_at,notify_chat) VALUES(vilqa.fiber_group(OLD),OLD.user_id,now()+interval '60 seconds',false)
  ON CONFLICT(job_key) DO UPDATE SET notify_chat=EXCLUDED.notify_chat,revision=vilqa.fiber_jobs.revision+1,status='pending',attempts=0,ready_at=now()+interval '60 seconds',lease_until=NULL,token=NULL,updated_at=now();
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION vilqa.fiber_claim_for_user(p_executor text, p_user bigint)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE j vilqa.fiber_jobs%ROWTYPE;items jsonb;days jsonb;profile jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM vilqa.fiber_config WHERE enabled) THEN RETURN;END IF;
 SELECT * INTO j FROM vilqa.fiber_jobs WHERE (status='pending' AND (ready_at<=now() OR p_user IS NOT NULL) OR status='processing' AND lease_until<now()) AND attempts<3 AND (p_user IS NULL OR user_id=p_user) AND vilqa.access_check(user_id) ORDER BY ready_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN;END IF;
 UPDATE vilqa.fiber_jobs SET status='processing',token=p_executor||':'||revision,attempts=attempts+1,lease_until=now()+interval '5 minutes',updated_at=now() WHERE job_key=j.job_key RETURNING * INTO j;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',d.id,'name',d.item_name,'weight',d.weight,'calories',d.calories,'protein',d.protein,'fats',d.fats,'carbs',d.carbs,'signature',vilqa.fiber_signature(d),'cache_key',vilqa.fiber_key(d),'fiber',CASE WHEN d.fiber_basis=vilqa.fiber_signature(d) THEN d.fiber END,'cached_per100',c.per100,'recipe',d.legacy_data->'fiber_recipe') ORDER BY d.id),'[]') INTO items FROM vilqa.diary d LEFT JOIN vilqa.fiber_cache c ON c.cache_key=vilqa.fiber_key(d) AND c.updated_at>now()-interval '180 days' WHERE vilqa.fiber_group(d)=j.job_key AND d.deleted_at IS NULL;
 SELECT jsonb_agg(DISTINCT date) INTO days FROM vilqa.diary d WHERE vilqa.fiber_group(d)=j.job_key;
 profile:=vilqa.resolve_profile(j.user_id,'{}');
 RETURN NEXT jsonb_build_object('job_key',j.job_key,'user_id',j.user_id,'notify_chat',j.notify_chat,'revision',j.revision,'token',j.token,'items',items,'dates',days,'profile',jsonb_build_object('daily_calories',profile->'daily_calories','timezone',COALESCE(profile->>'timezone','Europe/Moscow')));
END $function$;
