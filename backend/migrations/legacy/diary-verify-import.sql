WITH source AS (SELECT x FROM jsonb_array_elements($1::jsonb) x), differences AS (
 SELECT x->>'id' AS id FROM source LEFT JOIN vilqa.diary d ON d.id=(x->>'id')::bigint
 WHERE d.id IS NULL OR d.legacy_data IS DISTINCT FROM x OR d.user_id IS DISTINCT FROM COALESCE((x->>'user_id')::bigint,0)
 OR d.date IS DISTINCT FROM x->>'date' OR d.item_name IS DISTINCT FROM x->>'item_name'
 OR d.weight IS DISTINCT FROM (x->>'weight')::double precision OR d.calories IS DISTINCT FROM (x->>'calories')::double precision
 OR d.protein IS DISTINCT FROM (x->>'protein')::double precision OR d.fats IS DISTINCT FROM (x->>'fats')::double precision OR d.carbs IS DISTINCT FROM (x->>'carbs')::double precision
)
SELECT (SELECT count(*) FROM source) AS source_count,(SELECT count(*) FROM vilqa.diary) AS target_count,(SELECT count(*) FROM differences) AS differences,
(SELECT sum((x->>'calories')::double precision) FROM source) AS source_calories,(SELECT sum(calories) FROM vilqa.diary) AS target_calories,
(SELECT count(*) FROM vilqa.diary WHERE user_id=0) AS orphan_count;
