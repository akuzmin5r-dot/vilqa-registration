BEGIN;
SELECT vilqa.archive_recipe(180753266,'{"id":800000091,"user_id":180753266,"recipe_name":"VILQA TEMP ARCHIVE TEST"}');
SELECT vilqa.archive_recipe(180753266,'{"id":800000091,"user_id":180753266,"recipe_name":"VILQA TEMP ARCHIVE TEST"}');
DO $t$
BEGIN
 IF (SELECT count(*) FROM vilqa.recipe_deletions WHERE actor_id=180753266 AND recipe_id=800000091)<>1 THEN RAISE EXCEPTION 'Duplicate archive';END IF;
 BEGIN PERFORM vilqa.archive_recipe(180753266,'{"id":800000092,"user_id":207093928}');RAISE EXCEPTION 'Foreign accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='Foreign accepted' THEN RAISE;END IF;END;
END $t$;
ROLLBACK;
SELECT to_regclass('vilqa.recipe_deletions')::text AS archive_table,to_regprocedure('vilqa.archive_recipe(bigint,jsonb)')::text AS archive_function;
