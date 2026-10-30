BEGIN;
DO $test$
DECLARE base jsonb:='{"user_id":123,"name":"Original","gender":"male","age":30,"height":180,"weight":75,"activity_level":"1.55","goal":"maintain","goal_ru":"поддержание веса","timezone":"Europe/Moscow","daily_calories":2200,"daily_protein":165,"daily_fats":61,"daily_carbs":248,"current_state":"recipe_name"}';req jsonb;r jsonb;cnt integer;
BEGIN
 req:='{"action":"profile_edit","version":0,"request_id":"profile-test-000001","patch":{"name":"Updated","gender":"male","age":30,"height":180,"weight":80,"activity":1.55,"goal":"maintain"}}';
 r:=vilqa.edit_profile(456,123,req,base);IF (r->>'status')::int<>403 THEN RAISE EXCEPTION 'Unauthorized profile edit';END IF;
 r:=vilqa.edit_profile(123,123,req,base);IF NOT (r->>'success')::boolean OR (r->'profile'->>'daily_calories')::int<>2759 THEN RAISE EXCEPTION 'Profile calculation failed';END IF;
 IF (r->'profile'->>'daily_protein')::int<>207 OR (r->'profile'->>'profile_version')::int<>1 THEN RAISE EXCEPTION 'Macros or version incorrect';END IF;
 r:=vilqa.edit_profile(123,123,req,base);IF (r->'profile'->>'profile_version')::int<>1 THEN RAISE EXCEPTION 'Duplicate profile save';END IF;
 r:=vilqa.edit_profile(123,123,req||'{"request_id":"profile-test-000002"}',base);IF (r->>'status')::int<>409 THEN RAISE EXCEPTION 'Lost update accepted';END IF;
 r:=vilqa.edit_profile(123,123,req||'{"version":1,"request_id":"profile-test-bad001","patch":{"name":"Bad","gender":"male","goal":"maintain","age":30.5,"height":180,"weight":80,"activity":1.55}}',base);IF (r->>'status')::int<>400 THEN RAISE EXCEPTION 'Fractional age accepted';END IF;
 r:=vilqa.edit_profile(180753266,123,req||'{"version":1,"request_id":"profile-admin-00001"}',base);IF NOT (r->>'success')::boolean THEN RAISE EXCEPTION 'Admin profile edit failed';END IF;
 SELECT count(*) INTO cnt FROM vilqa.profile_audit WHERE user_id=123;IF cnt<>2 THEN RAISE EXCEPTION 'Profile audit incorrect';END IF;
 r:=vilqa.resolve_profile(123,base||'{"current_state":"recipe_weight"}');IF r->>'current_state'<>'recipe_weight' THEN RAISE EXCEPTION 'Recipe state overridden';END IF;
 r:=vilqa.resolve_profile(123,base,to_char(now()-interval '1 day','YYYY-MM-DD'));IF (r->>'daily_calories')::int<>2200 THEN RAISE EXCEPTION 'Historical target changed';END IF;
 r:=vilqa.api(123,'{"action":"profile"}',jsonb_build_array(base));IF (r->'profile'->>'weight')::int<>80 THEN RAISE EXCEPTION 'API profile stale';END IF;
 r:=vilqa.api(456,'{"action":"profile_history","user_id":123}',jsonb_build_array(base));IF (r->>'status')::int<>403 THEN RAISE EXCEPTION 'Profile audit leaked';END IF;
 r:=vilqa.registration_profile(base||'{"weight":90,"daily_calories":2400}');IF (r->>'weight')::int<>90 OR (r->>'profile_version')::int<>3 THEN RAISE EXCEPTION 'Repeat registration failed';END IF;
END $test$;
ROLLBACK;
SELECT 13 AS passed,'rolled_back' AS test_data;
