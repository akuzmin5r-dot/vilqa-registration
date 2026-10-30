WITH source AS (SELECT x FROM jsonb_array_elements($1::jsonb) x), inserted AS (
 INSERT INTO vilqa.diary(id,user_id,date,datetime,time,meal_type,item_type,item_name,weight,calories,protein,fats,carbs,legacy_data,created_at,updated_at)
 SELECT (x->>'id')::bigint,COALESCE((x->>'user_id')::bigint,0),x->>'date',x->>'datetime',x->>'time',x->>'meal_type',x->>'item_type',x->>'item_name',(x->>'weight')::double precision,(x->>'calories')::double precision,(x->>'protein')::double precision,(x->>'fats')::double precision,(x->>'carbs')::double precision,x,(x->>'createdAt')::timestamptz,(x->>'updatedAt')::timestamptz FROM source
 ON CONFLICT(id) DO NOTHING RETURNING *
), journal AS (
 INSERT INTO vilqa.audit(entry_id,actor_id,action,after_data) SELECT id,180753266,'import',to_jsonb(inserted) FROM inserted RETURNING id
)
SELECT (SELECT count(*) FROM source) AS source_count,(SELECT count(*) FROM inserted) AS imported_count,(SELECT count(*) FROM journal) AS audit_count;
