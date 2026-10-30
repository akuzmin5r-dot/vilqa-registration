CREATE OR REPLACE FUNCTION vilqa.nav_prepare_fast(p_op jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $f$
DECLARE rows jsonb:='[]';buttons jsonb;r jsonb;b jsonb;a jsonb;action text;style text;title text;signature text:='';shape text:='';multi boolean:=false;layout_key text;route integer;n integer;
BEGIN
 IF p_op IS NULL OR p_op->>'id' IS NULL THEN RETURN NULL;END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_op->'payload'->'keyboard','[]')) LOOP
  buttons:='[]';n:=jsonb_array_length(r->'row'->'buttons');multi:=multi OR n>1;shape:=shape||CASE WHEN shape='' THEN '' ELSE ',' END||n::text;
  FOR b IN SELECT value FROM jsonb_array_elements(r->'row'->'buttons') LOOP
   a:=COALESCE(b->'additionalFields','{}');action:=a->>'callback_data';title:=COALESCE(b->>'text','');
   IF action IS NOT NULL AND action<>'' THEN
    IF action !~ '^[a-z_]{1,40}$' THEN RAISE EXCEPTION 'Invalid navigation action';END IF;
    style:=CASE WHEN action='recipe_delete_confirm' OR action ~ '^(meal_cancel|recipe_cancel)(:|$)' OR title ~* 'отмен' THEN 'danger' WHEN action='menu_main' OR title ~* 'назад|главное[[:space:]]*меню|в[[:space:]]*меню' THEN '' ELSE 'success' END;
    action:='n:'||(p_op->>'revision')||':'||action;IF length(action)>64 THEN RAISE EXCEPTION 'Navigation callback too long';END IF;
    a:=a||jsonb_build_object('callback_data',action,'style',style);signature:=signature||'C';
   ELSIF a ? 'web_app' THEN
    a:=a||jsonb_build_object('style',CASE p_op->'payload'->>'screen' WHEN 'profile' THEN 'success' WHEN 'main' THEN 'primary' ELSE '' END);signature:=signature||'W';
   ELSE signature:=signature||'C';
   END IF;
   buttons:=buttons||jsonb_build_array(b||jsonb_build_object('additionalFields',a));
  END LOOP;
  rows:=rows||jsonb_build_array(jsonb_build_object('row',jsonb_build_object('buttons',buttons)));
 END LOOP;
 layout_key:=CASE WHEN p_op->>'method'='retire' THEN 'retire' ELSE (p_op->>'method')||':'||signature||CASE WHEN multi THEN ':'||shape ELSE '' END END;
 SELECT v.i INTO route FROM (VALUES ('text:C',0),('text:CC',1),('text:CCC',2),('text:CCCC',3),('text:CCCCC',4),('text:CCCCCC',5),('edit:C',6),('edit:CC',7),('edit:CCC',8),('edit:CCCC',9),('edit:CCCCC',10),('edit:CCCCCC',11),('photo:CWCCC',12),('photo:WC',13),('retire',14),('photo:CWCCC:1,1,2,1',15)) v(k,i) WHERE v.k=layout_key;
 IF route IS NULL THEN RAISE EXCEPTION 'Unsupported navigation layout: %',layout_key;END IF;
 RETURN p_op||jsonb_build_object('keyboard',jsonb_build_object('rows',rows),'route',route);
END $f$;
