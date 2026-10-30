CREATE OR REPLACE FUNCTION vilqa.import_legacy(p_rows jsonb) RETURNS jsonb LANGUAGE plpgsql AS $fn$
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
END $fn$;
