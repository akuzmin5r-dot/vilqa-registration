BEGIN;
CREATE OR REPLACE FUNCTION vilqa.add_recipe_portion(p_actor bigint,p_req jsonb,p_recipe jsonb) RETURNS jsonb LANGUAGE plpgsql AS $f$
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
 VALUES(p_actor,stamp->>'date',stamp->>'time',stamp->>'datetime',stamp->>'meal_type','recipe',name,w,(nutrition->>'calories')::double precision,(nutrition->>'protein')::double precision,(nutrition->>'fats')::double precision,(nutrition->>'carbs')::double precision,jsonb_build_object('source','saved_recipe','recipe_id',rid,'recipe_per_100g',per100)) RETURNING * INTO entry;
 INSERT INTO vilqa.audit(entry_id,actor_id,action,before_data,after_data) VALUES(entry.id,p_actor,'create',NULL,to_jsonb(entry));
 result:=jsonb_build_object('success',true,'entry',to_jsonb(entry));
 INSERT INTO vilqa.requests(actor_id,request_id,request_data,response) VALUES(p_actor,key,p_req,result);
 RETURN result;
EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow OR invalid_parameter_value OR numeric_value_out_of_range THEN
 RETURN jsonb_build_object('success',false,'status',400,'message','Проверь вес, дату и время порции');
END $f$;
COMMIT;
