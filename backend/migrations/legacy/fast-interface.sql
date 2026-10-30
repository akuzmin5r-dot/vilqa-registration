CREATE OR REPLACE FUNCTION vilqa.fast_interface(p_user bigint, p_chat bigint, p_private boolean, p_event text, p_callback text, p_message bigint, p_command text, p_name text, p_username text, p_main jsonb, p_food jsonb, p_executor text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE a text:=regexp_replace(COALESCE(p_callback,''),'^n:[0-9]+:','');e jsonb;d jsonb;o jsonb;k text;t timestamptz:=clock_timestamp();
BEGIN
 IF p_private IS DISTINCT FROM true OR p_user IS NULL OR p_user<=0 OR p_chat IS DISTINCT FROM p_user THEN RETURN jsonb_build_object('route','ignore','event',jsonb_build_object('allowed',false,'reason','private'));END IF;
 IF NOT (COALESCE(p_command,'') ~* '^/(menu|start)(@vilqa_bot)?[[:space:]]*$' OR a IN ('menu_main','menu_food_entry','menu_stats') OR a ~ '^meal_(confirm|cancel|restore):[A-Za-z0-9_-]{1,48}$') THEN RETURN jsonb_build_object('route','legacy');END IF;
 -- Unknown/incomplete profiles retain the existing registration and invitation flow.
 IF NOT COALESCE(vilqa.access_check(p_user),false) THEN RETURN jsonb_build_object('route','legacy');END IF;
 SELECT data INTO d FROM vilqa.profiles WHERE user_id=p_user AND data ? 'daily_calories';
 IF NOT FOUND THEN RETURN jsonb_build_object('route','legacy');END IF;
 IF COALESCE(p_event,'') !~ '^[0-9]{1,30}$' THEN RAISE EXCEPTION 'Invalid trusted Telegram event';END IF;
 e:=vilqa.nav_ingress(p_user,p_event,COALESCE(p_callback,''),COALESCE(p_message,0),COALESCE(p_command,''));
 IF e->>'allowed' IS DISTINCT FROM 'true' THEN RETURN jsonb_build_object('route','ignore','event',e,'user_id',p_user,'chat_id',p_chat);END IF;
 PERFORM vilqa.access_observe(p_user,p_username,p_name,true,false);
 IF a ~ '^meal_(confirm|cancel|restore):[A-Za-z0-9_-]{1,48}$' THEN
  RETURN jsonb_build_object('route','meal','event',e,'user_id',p_user,'chat_id',p_chat,'timezone',COALESCE(d->>'timezone','Europe/Moscow'),'action',split_part(split_part(a,':',1),'meal_',2),'draft_id',split_part(a,':',2));
 END IF;
 IF a='menu_stats' THEN
  RETURN jsonb_build_object('route','stats','event',e,'user_id',p_user,'chat_id',p_chat,'timezone',COALESCE(d->>'timezone','Europe/Moscow'),'guard_ms',round((extract(epoch FROM clock_timestamp()-t)*1000)::numeric,2));
 END IF;
 k:=CASE WHEN a='menu_food_entry' THEN 'food' ELSE 'main' END;
 IF (CASE k WHEN 'food' THEN p_food ELSE p_main END)->>'screen' IS DISTINCT FROM k THEN RAISE EXCEPTION 'Invalid trusted screen payload';END IF;
 o:=vilqa.nav_register_executor(vilqa.nav_request(p_user,p_event||':'||k,CASE k WHEN 'food' THEN p_food ELSE p_main END),p_executor);
 RETURN jsonb_build_object('route','deliver','event',e,'op',o,'user_id',p_user,'chat_id',p_chat,'guard_ms',round((extract(epoch FROM clock_timestamp()-t)*1000)::numeric,2));
END $function$;
