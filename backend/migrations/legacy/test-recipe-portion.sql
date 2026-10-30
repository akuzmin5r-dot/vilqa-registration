BEGIN;
DO $test$
DECLARE u bigint:=8000000000000030;recipe jsonb;req jsonb;r jsonb;first jsonb;entry_id bigint;
BEGIN
 INSERT INTO vilqa.access_members(user_id,granted_by) VALUES(u,180753266);
 INSERT INTO vilqa.profiles(user_id,data) VALUES(u,'{"timezone":"Europe/Moscow","daily_calories":2200}');
 recipe:=jsonb_build_object('id',123,'user_id',u,'recipe_name','Куриный суп','per_100g_calories',80,'per_100g_protein',6,'per_100g_fats',3,'per_100g_carbs',7);
 req:=jsonb_build_object('action','recipe_add','id',123,'weight',250,'date','2026-10-26','time','13:15','request_id','test-recipe-portion-01','calories',99999);
 r:=vilqa.add_recipe_portion(u,req,recipe);first:=r;entry_id:=(r->'entry'->>'id')::bigint;
 IF r->>'success'<>'true' OR r->'entry'->>'weight'<>'250' OR r->'entry'->>'calories'<>'200' OR r->'entry'->>'protein'<>'15' OR r->'entry'->>'fats'<>'7.5' OR r->'entry'->>'datetime'<>'2026-10-26T10:15:00Z' OR r->'entry'->>'meal_type'<>'обед' OR r->'entry'->>'item_type'<>'recipe' THEN RAISE EXCEPTION 'Portion failed: %',r;END IF;
 r:=vilqa.add_recipe_portion(u,req,NULL);IF r<>first OR (SELECT count(*) FROM vilqa.diary WHERE user_id=u)<>1 THEN RAISE EXCEPTION 'Replay duplicated or changed entry';END IF;
 r:=vilqa.add_recipe_portion(u,req||'{"weight":300}',recipe);IF r->>'status'<>'409' THEN RAISE EXCEPTION 'Request reuse accepted';END IF;
 r:=vilqa.add_recipe_portion(u,req||'{"request_id":"test-portion-other-01"}',recipe||jsonb_build_object('user_id',u+1));IF r->>'status'<>'404' THEN RAISE EXCEPTION 'Foreign recipe accepted';END IF;
 r:=vilqa.add_recipe_portion(u,req||jsonb_build_object('request_id','test-portion-user-01','user_id',u+1),recipe);IF r->>'status'<>'403' THEN RAISE EXCEPTION 'Foreign diary accepted';END IF;
 r:=vilqa.add_recipe_portion(u,req||'{"request_id":"test-portion-baddate","date":"2026-02-30"}',recipe);IF r->>'status'<>'400' THEN RAISE EXCEPTION 'Invalid date accepted';END IF;
 r:=vilqa.add_recipe_portion(u,req||'{"request_id":"test-portion-badtime","time":"24:00"}',recipe);IF r->>'status'<>'400' THEN RAISE EXCEPTION 'Invalid time accepted';END IF;
 r:=vilqa.add_recipe_portion(u,req||'{"request_id":"test-portion-no-kbju"}',recipe-'per_100g_protein');IF r->>'status'<>'422' THEN RAISE EXCEPTION 'Missing macros accepted';END IF;
 r:=vilqa.add_recipe_portion(u,req||'{"request_id":"test-portion-badweight","weight":0}',recipe);IF r->>'status'<>'400' THEN RAISE EXCEPTION 'Zero weight accepted';END IF;
 r:=vilqa.add_recipe_portion(u,req||'{"request_id":"test-portion-totals-01"}',(recipe-'per_100g_calories')||'{"total_weight":1000,"total_calories":800}');IF r->'entry'->>'calories'<>'200' THEN RAISE EXCEPTION 'Legacy totals failed';END IF;
 UPDATE vilqa.diary SET deleted_at=now() WHERE id=entry_id;
 PERFORM vilqa.add_recipe_portion(u,req,NULL);IF EXISTS(SELECT 1 FROM vilqa.diary WHERE id=entry_id AND deleted_at IS NULL) THEN RAISE EXCEPTION 'Replay resurrected deleted entry';END IF;
 IF (SELECT count(*) FROM vilqa.diary WHERE user_id=u)<>2 OR (SELECT count(*) FROM vilqa.audit WHERE actor_id=u)<>2 THEN RAISE EXCEPTION 'Failed requests mutated data or missing audit';END IF;
END $test$;
ROLLBACK;
SELECT to_regprocedure('vilqa.add_recipe_portion(bigint,jsonb,jsonb)')::text AS installed_function,'Portion, ownership, dates, replay, audit, legacy totals and rollback passed' AS result;
