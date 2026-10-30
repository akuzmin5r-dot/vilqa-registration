BEGIN;
DO $t$
DECLARE u bigint:=8000000000000002;r jsonb;i integer:=0;a text;
BEGIN
 INSERT INTO vilqa.access_members(user_id,granted_by) VALUES(u,180753266);
 INSERT INTO vilqa.profiles(user_id,data) VALUES(u,'{"daily_calories":2200,"timezone":"Europe/Moscow"}');
 FOREACH a IN ARRAY ARRAY['confirm','cancel','restore'] LOOP
  i:=i+1;r:=vilqa.fast_interface(u,u,true,(900000+i)::text,'meal_'||a||':tg_test_1',123,'','','','{}','{}','test');
  IF r->>'route'<>'meal' OR r->>'action'<>a OR r->>'draft_id'<>'tg_test_1' OR r->>'user_id'<>u::text THEN RAISE EXCEPTION 'Meal route failed: %',r;END IF;
 END LOOP;
 r:=vilqa.fast_interface(u,u,true,'900001','meal_confirm:tg_test_1',123,'','','','{}','{}','test');
 IF r->'event'->>'reason'<>'duplicate' OR r->>'route'<>'ignore' THEN RAISE EXCEPTION 'Duplicate ingress accepted';END IF;
 r:=vilqa.fast_interface(u,u+1,true,'900004','meal_confirm:tg_test_1',123,'','','','{}','{}','test');
 IF r->>'route'<>'ignore' THEN RAISE EXCEPTION 'Wrong chat accepted';END IF;
 r:=vilqa.fast_interface(u+1,u+1,true,'900005','meal_confirm:tg_test_1',123,'','','','{}','{}','test');
 IF r->>'route'<>'legacy' THEN RAISE EXCEPTION 'Unknown actor bypassed access';END IF;
END $t$;
SELECT 'Fast meal routes, identity and event replay passed; rolled back' AS result;
ROLLBACK;
