CREATE TABLE IF NOT EXISTS vilqa.nav_sessions(
 user_id bigint PRIMARY KEY, revision bigint NOT NULL DEFAULT 0, current_message bigint,
 current_kind text, current_screen text, active_op bigint, input_state text NOT NULL DEFAULT '',
 state_data jsonb NOT NULL DEFAULT '{}', state_version bigint NOT NULL DEFAULT 0,
 imported boolean NOT NULL DEFAULT false, paused boolean NOT NULL DEFAULT false,
 last_activity timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS vilqa.nav_operations(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,user_id bigint NOT NULL,event_key text NOT NULL,
 payload jsonb NOT NULL,revision bigint,status text NOT NULL DEFAULT 'pending',method text,
 old_message bigint,old_kind text,created_at timestamptz NOT NULL DEFAULT now(),finished_at timestamptz,
 message_id bigint,error_kind text,attempts integer NOT NULL DEFAULT 0,
 UNIQUE(user_id,event_key)
);
ALTER TABLE vilqa.nav_sessions ADD COLUMN IF NOT EXISTS recipes_page integer NOT NULL DEFAULT 0;
ALTER TABLE vilqa.nav_operations ADD COLUMN IF NOT EXISTS executor_id text;
CREATE TABLE IF NOT EXISTS vilqa.nav_messages(
 user_id bigint NOT NULL,message_id bigint NOT NULL,kind text NOT NULL,revision bigint NOT NULL,
 payload jsonb NOT NULL,retired boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT now(),
 cleanup_status text NOT NULL DEFAULT 'pending',PRIMARY KEY(user_id,message_id)
);
CREATE TABLE IF NOT EXISTS vilqa.nav_events(user_id bigint NOT NULL,event_key text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(user_id,event_key));
CREATE TABLE IF NOT EXISTS vilqa.nav_state_events(user_id bigint NOT NULL,event_key text NOT NULL,result jsonb NOT NULL,PRIMARY KEY(user_id,event_key));
CREATE INDEX IF NOT EXISTS nav_pending ON vilqa.nav_operations(user_id,id) WHERE status='pending';

CREATE OR REPLACE FUNCTION vilqa.nav_ingress(p_user bigint,p_event text,p_callback text,p_message bigint,p_command text)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE s vilqa.nav_sessions%ROWTYPE;a text:=COALESCE(p_callback,'');v bigint;m vilqa.nav_messages%ROWTYPE;
BEGIN
 IF NOT vilqa.access_check(p_user) THEN RETURN jsonb_build_object('allowed',false,'reason','access');END IF;
 INSERT INTO vilqa.nav_sessions(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=p_user FOR UPDATE;
 IF EXISTS(SELECT 1 FROM vilqa.nav_events WHERE user_id=p_user AND event_key=p_event) THEN RETURN jsonb_build_object('allowed',false,'reason','duplicate');END IF;
 IF a LIKE 'n:%' THEN
  IF a !~ '^n:[0-9]{1,18}:[a-z_]{1,40}$' THEN RETURN jsonb_build_object('allowed',false,'reason','stale');END IF;
  v:=split_part(a,':',2)::bigint;a:=split_part(a,':',3);
  SELECT * INTO m FROM vilqa.nav_messages WHERE user_id=p_user AND message_id=p_message;
  IF s.active_op IS NOT NULL OR s.current_message IS DISTINCT FROM p_message OR s.revision<>v OR m.retired IS DISTINCT FROM false
   OR (a LIKE 'recipe_%' AND COALESCE((m.payload->>'recipe_version')::bigint,-1)<>s.state_version)
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(m.payload->'keyboard','[]')) r, jsonb_array_elements(r->'row'->'buttons') b WHERE b->'additionalFields'->>'callback_data'=a)
  THEN RETURN jsonb_build_object('allowed',false,'reason','stale');END IF;
 ELSIF a LIKE 'recipe_%' OR a='meal_delete_last' THEN
  RETURN jsonb_build_object('allowed',false,'reason','stale');
 ELSIF a LIKE 'menu_%' AND a NOT IN ('menu_main','menu_food_entry','menu_profile','menu_stats','menu_recipes','menu_recommendation') THEN
  RETURN jsonb_build_object('allowed',false,'reason','stale');
 END IF;
 INSERT INTO vilqa.nav_events VALUES(p_user,p_event,now());
 IF a='recipe_next' THEN UPDATE vilqa.nav_sessions SET recipes_page=recipes_page+1 WHERE user_id=p_user;
 ELSIF a='recipe_prev' THEN UPDATE vilqa.nav_sessions SET recipes_page=greatest(recipes_page-1,0) WHERE user_id=p_user;
 ELSIF a='menu_recipes' OR p_command ~* '^/recipes(@vilqa_bot)?[[:space:]]*$' THEN UPDATE vilqa.nav_sessions SET recipes_page=0 WHERE user_id=p_user;END IF;
 IF p_command ~* '^/(menu|start|recipes)(@vilqa_bot)?[[:space:]]*$' OR a IN ('menu_main','menu_food_entry','menu_profile','menu_stats','menu_recipes','menu_recommendation','recipe_pause') THEN
  UPDATE vilqa.nav_sessions SET state_data=CASE WHEN input_state<>'' THEN state_data||jsonb_build_object('_resume_state',input_state) ELSE state_data END,input_state='',paused=true,state_version=state_version+1,last_activity=now() WHERE user_id=p_user;
 END IF;
 RETURN jsonb_build_object('allowed',true,'action',a,'user_id',p_user,'chat_id',p_user);
END
$f$;

CREATE OR REPLACE FUNCTION vilqa.nav_register_executor(p_op jsonb,p_executor text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE o vilqa.nav_operations%ROWTYPE;
BEGIN
 IF p_op IS NULL THEN RETURN NULL;END IF;
 UPDATE vilqa.nav_operations SET executor_id=p_executor WHERE id=(p_op->>'id')::bigint AND status='in_flight' RETURNING * INTO o;
 RETURN CASE WHEN FOUND THEN to_jsonb(o) ELSE NULL END;
END
$f$;

CREATE OR REPLACE FUNCTION vilqa.nav_release_failed(p_executor text) RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE s vilqa.nav_sessions%ROWTYPE;released integer:=0;
BEGIN
 IF COALESCE(p_executor,'')='' THEN RETURN 0;END IF;
 FOR s IN SELECT ns.* FROM vilqa.nav_sessions ns JOIN vilqa.nav_operations op ON op.id=ns.active_op WHERE op.executor_id=p_executor AND op.status='in_flight' FOR UPDATE OF ns LOOP
  UPDATE vilqa.nav_operations SET status='unknown',error_kind='executor_failed',finished_at=now() WHERE id=s.active_op;
  UPDATE vilqa.nav_sessions SET active_op=NULL WHERE user_id=s.user_id AND active_op=s.active_op;
  released:=released+1;
 END LOOP;
 RETURN released;
END
$f$;

CREATE OR REPLACE FUNCTION vilqa.nav_profile(p_user bigint,p_profile jsonb) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE s vilqa.nav_sessions%ROWTYPE;d jsonb;st text;
BEGIN
 INSERT INTO vilqa.nav_sessions(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=p_user FOR UPDATE;
 IF NOT s.imported THEN
  BEGIN d:=COALESCE(NULLIF(p_profile->>'state_data',''),'{}')::jsonb;EXCEPTION WHEN OTHERS THEN d:='{}';END;
  IF jsonb_typeof(d)<>'object' THEN d:='{}';END IF;
  IF COALESCE(p_profile->>'current_state','') LIKE 'recipe_%' THEN d:=d||jsonb_build_object('_resume_state',p_profile->>'current_state');END IF;
  st:=CASE WHEN s.paused THEN '' ELSE COALESCE(p_profile->>'current_state','') END;
  UPDATE vilqa.nav_sessions SET state_data=d,input_state=st,imported=true WHERE user_id=p_user RETURNING * INTO s;
 END IF;
 RETURN p_profile || jsonb_build_object('current_state',s.input_state,'state_data',s.state_data::text,'_recipe_version',s.state_version,'recipe_last_activity',s.last_activity,'recipes_page',s.recipes_page);
END
$f$;

CREATE OR REPLACE FUNCTION vilqa.nav_state_write(p_user bigint,p_event text,p_expected bigint,p_state text,p_data jsonb,p_mode text)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE s vilqa.nav_sessions%ROWTYPE;r jsonb;d jsonb;st text;
BEGIN
 IF NOT vilqa.access_check(p_user) THEN RAISE EXCEPTION 'Navigation access denied';END IF;
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=p_user FOR UPDATE;
 SELECT result INTO r FROM vilqa.nav_state_events WHERE user_id=p_user AND event_key=p_event;
 IF FOUND THEN RETURN r;END IF;
 IF s.state_version IS DISTINCT FROM p_expected THEN
  IF p_mode='finished' THEN RETURN jsonb_build_object('user_id',p_user,'chat_id',p_user,'state_data',s.state_data::text,'current_state',s.input_state,'stale_job',true,'_recipe_version',s.state_version);END IF;
  RAISE EXCEPTION 'Recipe state changed; repeat the action';
 END IF;
 d:=COALESCE(p_data,s.state_data);st:=COALESCE(p_state,s.input_state);
 IF p_mode='start' THEN
  IF s.state_data ? 'recipe_draft' THEN RETURN jsonb_build_object('user_id',p_user,'chat_id',p_user,'state_data',s.state_data::text,'current_state',s.input_state,'_recipe_version',s.state_version,'existing_draft',true);END IF;
  d:=jsonb_build_object('recipe_draft',jsonb_build_object('draft_id',p_event,'recipe_name','','ingredients_raw','[]'::jsonb,'status','collecting'));st:='recipe_naming';
 ELSIF p_mode='pause' THEN st:='';d:=CASE WHEN s.input_state<>'' THEN s.state_data||jsonb_build_object('_resume_state',s.input_state) ELSE s.state_data END;
 ELSIF p_mode='resume' THEN
  IF NOT s.state_data ? 'recipe_draft' THEN RAISE EXCEPTION 'Recipe draft missing';END IF;
  st:=CASE WHEN d->>'_resume_state' IN ('recipe_naming','recipe_ingredients','recipe_weight','recipe_ai_processing') THEN d->>'_resume_state' WHEN COALESCE(d->'recipe_draft'->>'recipe_name','')='' THEN 'recipe_naming' WHEN COALESCE(d->'recipe_draft'->>'total_weight_raw','')<>'' THEN 'recipe_ai_processing' ELSE 'recipe_ingredients' END;
 ELSIF p_mode IN ('delete','finished') THEN st:='';d:='{}';END IF;
 IF st<>'' THEN d:=d||jsonb_build_object('_resume_state',st);END IF;
 UPDATE vilqa.nav_sessions SET input_state=st,state_data=d,state_version=state_version+1,paused=(st=''),imported=true,last_activity=now() WHERE user_id=p_user RETURNING * INTO s;
 r:=jsonb_build_object('user_id',p_user,'chat_id',p_user,'current_state',s.input_state,'state_data',s.state_data::text,'_recipe_version',s.state_version);
 INSERT INTO vilqa.nav_state_events VALUES(p_user,p_event,r);RETURN r;
END
$f$;

CREATE OR REPLACE FUNCTION vilqa.nav_claim(p_user bigint) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE s vilqa.nav_sessions%ROWTYPE;o vilqa.nav_operations%ROWTYPE;v_method text;
BEGIN
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=p_user FOR UPDATE;
 IF NOT FOUND OR s.active_op IS NOT NULL OR NOT vilqa.access_check(p_user) THEN RETURN NULL;END IF;
 SELECT * INTO o FROM vilqa.nav_operations WHERE user_id=p_user AND status='pending' ORDER BY id DESC LIMIT 1;
 IF NOT FOUND THEN RETURN NULL;END IF;
 UPDATE vilqa.nav_operations SET status='superseded',finished_at=now() WHERE user_id=p_user AND status='pending' AND id<>o.id;
 v_method:=CASE WHEN o.payload->>'screen'='retire' THEN 'retire' WHEN o.payload->>'kind'='text' AND s.current_kind='text' AND s.current_message IS NOT NULL AND COALESCE((o.payload->>'replace')::boolean,false)=false THEN 'edit' WHEN o.payload->>'kind'='photo' THEN 'photo' ELSE 'text' END;
 UPDATE vilqa.nav_sessions SET active_op=o.id WHERE user_id=p_user RETURNING * INTO s;
 UPDATE vilqa.nav_operations SET status='in_flight',revision=o.id,method=v_method,old_message=s.current_message,old_kind=s.current_kind,attempts=attempts+1 WHERE id=o.id RETURNING * INTO o;
 RETURN to_jsonb(o);
END
$f$;

CREATE OR REPLACE FUNCTION vilqa.nav_request(p_user bigint,p_event text,p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE s vilqa.nav_sessions%ROWTYPE;
BEGIN
 IF NOT vilqa.access_check(p_user) THEN RETURN NULL;END IF;
 IF p_payload->>'kind' NOT IN ('text','photo','retire') OR p_payload->>'screen' IS NULL THEN RAISE EXCEPTION 'Invalid navigation payload';END IF;
 INSERT INTO vilqa.nav_sessions(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=p_user FOR UPDATE;
 IF EXISTS(SELECT 1 FROM vilqa.nav_operations WHERE user_id=p_user AND event_key=p_event) THEN RETURN NULL;END IF;
 IF p_payload->>'screen' LIKE 'recipes_%' THEN
  IF p_payload->>'has_prev'='true' THEN p_payload:=jsonb_set(p_payload,'{keyboard}',(p_payload->'keyboard')||'[{"row":{"buttons":[{"text":"← Предыдущие рецепты","additionalFields":{"callback_data":"recipe_prev"}}]}}]'::jsonb);END IF;
  IF p_payload->>'has_next'='true' THEN p_payload:=jsonb_set(p_payload,'{keyboard}',(p_payload->'keyboard')||'[{"row":{"buttons":[{"text":"Следующие рецепты →","additionalFields":{"callback_data":"recipe_next"}}]}}]'::jsonb);END IF;
 END IF;
 INSERT INTO vilqa.nav_operations(user_id,event_key,payload) VALUES(p_user,p_event,p_payload||jsonb_build_object('recipe_version',s.state_version));
 RETURN vilqa.nav_claim(p_user);
END
$f$;

CREATE OR REPLACE FUNCTION vilqa.nav_finish(p_op bigint,p_message bigint,p_error text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE o vilqa.nav_operations%ROWTYPE;s vilqa.nav_sessions%ROWTYPE;
BEGIN
 SELECT * INTO o FROM vilqa.nav_operations WHERE id=p_op;
 SELECT * INTO s FROM vilqa.nav_sessions WHERE user_id=o.user_id FOR UPDATE;
 IF s.active_op IS DISTINCT FROM p_op OR o.status<>'in_flight' THEN RETURN jsonb_build_object('user_id',o.user_id,'status','ignored');END IF;
 IF p_error='edit_missing' AND o.method='edit' THEN
  UPDATE vilqa.nav_operations SET method='text',attempts=attempts+1 WHERE id=p_op RETURNING * INTO o;RETURN jsonb_build_object('user_id',o.user_id,'retry',to_jsonb(o),'status','retry');
 END IF;
 IF p_error IS NULL AND (p_message>0 OR o.method='retire') THEN
  IF o.old_message IS NOT NULL AND o.old_message IS DISTINCT FROM p_message THEN UPDATE vilqa.nav_messages SET retired=true WHERE user_id=o.user_id AND message_id=o.old_message;END IF;
  IF o.method='retire' THEN
   UPDATE vilqa.nav_sessions SET current_message=NULL,current_kind=NULL,current_screen=NULL,active_op=NULL WHERE user_id=o.user_id;
  ELSE
   INSERT INTO vilqa.nav_messages(user_id,message_id,kind,revision,payload) VALUES(o.user_id,p_message,o.payload->>'kind',o.revision,o.payload)
   ON CONFLICT(user_id,message_id) DO UPDATE SET revision=EXCLUDED.revision,payload=EXCLUDED.payload,retired=false;
   UPDATE vilqa.nav_sessions SET current_message=p_message,current_kind=o.payload->>'kind',current_screen=o.payload->>'screen',revision=o.revision,active_op=NULL WHERE user_id=o.user_id;
  END IF;
  UPDATE vilqa.nav_operations SET status='succeeded',message_id=p_message,finished_at=now() WHERE id=p_op;
 ELSE
  UPDATE vilqa.nav_operations SET status=CASE WHEN p_error='unknown' THEN 'unknown' ELSE 'failed' END,error_kind=p_error,finished_at=now() WHERE id=p_op;
  UPDATE vilqa.nav_sessions SET active_op=NULL WHERE user_id=o.user_id;
 END IF;
 RETURN jsonb_build_object('user_id',o.user_id,'status',CASE WHEN p_error IS NULL THEN 'succeeded' ELSE COALESCE(p_error,'failed') END);
END
$f$;
