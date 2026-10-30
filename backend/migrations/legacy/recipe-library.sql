-- Commit installation before running any rollback-only regression tests.
BEGIN;
CREATE TABLE IF NOT EXISTS vilqa.recipe_deletions(actor_id bigint NOT NULL,recipe_id bigint NOT NULL,snapshot jsonb NOT NULL,archived_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(actor_id,recipe_id));
CREATE OR REPLACE FUNCTION vilqa.archive_recipe(p_actor bigint,p_row jsonb) RETURNS boolean LANGUAGE plpgsql AS $f$
BEGIN
 IF NOT COALESCE(vilqa.access_check(p_actor),false) OR (p_row->>'user_id')::bigint IS DISTINCT FROM p_actor OR COALESCE((p_row->>'id')::bigint,0)<=0 THEN RAISE EXCEPTION 'Recipe ownership violation';END IF;
 INSERT INTO vilqa.recipe_deletions(actor_id,recipe_id,snapshot) VALUES(p_actor,(p_row->>'id')::bigint,p_row) ON CONFLICT DO NOTHING;
 RETURN true;
END $f$;
COMMIT;
