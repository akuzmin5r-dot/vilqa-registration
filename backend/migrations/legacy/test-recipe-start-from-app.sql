BEGIN;
DO $t$
DECLARE u bigint:=8000000000000040;r jsonb;initial jsonb;draft jsonb;v bigint;
BEGIN
 INSERT INTO vilqa.access_members(user_id,granted_by) VALUES(u,180753266);
 INSERT INTO vilqa.profiles(user_id,data) VALUES(u,'{"daily_calories":2200}');
 r:=vilqa.start_recipe_from_app(u,'test-start-recipe-01');initial:=r;
 IF r->>'current_state' IS DISTINCT FROM 'recipe_naming' THEN RAISE EXCEPTION 'Recipe start failed';END IF;
 SELECT state_data,state_version INTO draft,v FROM vilqa.nav_sessions WHERE user_id=u;
 r:=vilqa.start_recipe_from_app(u,'test-start-recipe-01');
 IF r IS DISTINCT FROM initial OR (SELECT state_version FROM vilqa.nav_sessions WHERE user_id=u)<>v THEN RAISE EXCEPTION 'Repeated start changed state';END IF;
 r:=vilqa.start_recipe_from_app(u,'test-start-recipe-02');
 IF r->>'existing_draft' IS DISTINCT FROM 'true' OR (SELECT state_data FROM vilqa.nav_sessions WHERE user_id=u) IS DISTINCT FROM draft THEN RAISE EXCEPTION 'Existing draft overwritten';END IF;
 BEGIN PERFORM vilqa.start_recipe_from_app(u+1,'test-start-recipe-03');RAISE EXCEPTION 'Foreign actor accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM='Foreign actor accepted' THEN RAISE;END IF;END;
 INSERT INTO vilqa.access_members(user_id,granted_by) VALUES(u+2,180753266);
 INSERT INTO vilqa.profiles(user_id,data) VALUES(u+2,'{"daily_calories":2200}');
 r:=vilqa.start_recipe_from_app(u+2,'test-start-legacy-01','{"current_state":"recipe_ingredients","state_data":"{\"recipe_draft\":{\"recipe_name\":\"LEGACY PRESERVED\",\"ingredients_raw\":[\"rice\"]}}"}');
 IF r->>'existing_draft' IS DISTINCT FROM 'true' OR ((r->>'state_data')::jsonb->'recipe_draft'->>'recipe_name') IS DISTINCT FROM 'LEGACY PRESERVED' THEN RAISE EXCEPTION 'Legacy draft lost';END IF;
END $t$;
ROLLBACK;
SELECT to_regprocedure('vilqa.start_recipe_from_app(bigint,text,jsonb)')::text AS installed,'Start, replay, existing draft and access passed' AS result;
