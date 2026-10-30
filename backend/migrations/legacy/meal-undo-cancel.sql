CREATE OR REPLACE FUNCTION vilqa.confirm_meal(p_id text, p_user bigint, p_chat bigint, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE d public.vilqa_meal_drafts%ROWTYPE; item jsonb; idx integer:=0; entry_id bigint; ids jsonb:='[]'; f text; n double precision;
BEGIN
 SELECT * INTO d FROM public.vilqa_meal_drafts WHERE draft_id=p_id AND user_id=p_user AND chat_id=p_chat FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('committed',false,'feedback','Эта кнопка устарела. Отправь продукты для нового расчёта.'); END IF;
 IF d.status='saved' THEN RETURN jsonb_build_object('committed',false,'outcome','already_saved','feedback','Этот расчёт уже записан. Повторная запись не нужна.'); END IF;
 IF d.status NOT IN ('pending','cancelled') THEN RETURN jsonb_build_object('committed',false,'feedback','Предыдущая операция требует проверки. Повторно продукты не записываю.'); END IF;
 IF d.expires_at<=now() THEN RETURN jsonb_build_object('committed',false,'outcome','expired','draft_id',p_id,'feedback','Срок действия расчёта истёк. Отправь продукты снова.'); END IF;
 IF d.status='cancelled' AND p_action IS DISTINCT FROM 'restore' THEN
  RETURN jsonb_build_object('committed',false,'outcome','cancelled','draft_id',p_id,'can_restore',true,'feedback','Расчёт отменён. Ничего не записано.');
 END IF;
 IF d.status='pending' AND p_action='restore' THEN RETURN jsonb_build_object('committed',false,'feedback','Этот расчёт ещё не отменён. Используй кнопку записи.'); END IF;
 IF p_action='cancel' THEN
  UPDATE public.vilqa_meal_drafts SET status='cancelled',updated_at=now() WHERE draft_id=p_id;
  RETURN jsonb_build_object('committed',false,'outcome','cancelled','draft_id',p_id,'can_restore',true,'feedback','Расчёт отменён. Ничего не записано.');
 END IF;
 IF p_action NOT IN ('confirm','restore') OR p_action IS NULL THEN RETURN jsonb_build_object('committed',false,'feedback','Эта кнопка устарела.'); END IF;
 IF jsonb_typeof(d.payload->'rows') IS DISTINCT FROM 'array' OR jsonb_array_length(d.payload->'rows') NOT BETWEEN 1 AND 10 THEN RAISE EXCEPTION 'Invalid meal draft'; END IF;
 FOR item IN SELECT x FROM jsonb_array_elements(d.payload->'rows') x LOOP
  idx:=idx+1;
  IF (item->>'user_id')::bigint IS DISTINCT FROM p_user OR length(trim(item->>'item_name')) NOT BETWEEN 1 AND 100 OR item->>'item_name' IS NULL THEN RAISE EXCEPTION 'Invalid draft owner or item'; END IF;
  FOREACH f IN ARRAY ARRAY['weight','calories','protein','fats','carbs'] LOOP
   IF jsonb_typeof(item->f) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Invalid meal number'; END IF;
   n:=(item->>f)::double precision;
   IF n<0 OR n>100000 OR (f='weight' AND n<=0) THEN RAISE EXCEPTION 'Invalid meal value'; END IF;
  END LOOP;
  INSERT INTO vilqa.diary(user_id,date,datetime,time,meal_type,item_type,item_name,weight,calories,protein,fats,carbs,draft_id,item_index)
  VALUES(p_user,item->>'date',item->>'datetime',item->>'time',item->>'meal_type',item->>'item_type',item->>'item_name',(item->>'weight')::double precision,(item->>'calories')::double precision,(item->>'protein')::double precision,(item->>'fats')::double precision,(item->>'carbs')::double precision,p_id,idx)
  RETURNING id INTO entry_id;
  ids:=ids||to_jsonb(entry_id);
  INSERT INTO vilqa.audit(entry_id,actor_id,action,after_data) SELECT id,p_user,'create',to_jsonb(t) FROM vilqa.diary t WHERE id=entry_id;
 END LOOP;
 UPDATE public.vilqa_meal_drafts SET status='saved',saved_row_ids=ids,updated_at=now() WHERE draft_id=p_id;
 RETURN jsonb_build_object('committed',true,'outcome','saved','row_ids',ids,'draft_id',p_id);
END $function$
