BEGIN;
ALTER TABLE vilqa.diary ADD COLUMN IF NOT EXISTS fiber numeric;
ALTER TABLE vilqa.diary ADD COLUMN IF NOT EXISTS fiber_status text NOT NULL DEFAULT 'unknown';
ALTER TABLE vilqa.diary ADD COLUMN IF NOT EXISTS fiber_basis text;
CREATE TABLE IF NOT EXISTS vilqa.fiber_settings(user_id bigint PRIMARY KEY,daily_target numeric NOT NULL DEFAULT 25 CHECK(daily_target BETWEEN 1 AND 100),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS vilqa.fiber_config(id boolean PRIMARY KEY DEFAULT true CHECK(id),enabled boolean NOT NULL DEFAULT false);
INSERT INTO vilqa.fiber_config(id) VALUES(true) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS vilqa.fiber_cache(cache_key text PRIMARY KEY,per100 numeric CHECK(per100 BETWEEN 0 AND 100),source text NOT NULL DEFAULT 'ai_estimate',updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS vilqa.fiber_jobs(
 job_key text PRIMARY KEY,user_id bigint NOT NULL,revision integer NOT NULL DEFAULT 1,status text NOT NULL DEFAULT 'pending',
 ready_at timestamptz NOT NULL DEFAULT now(),lease_until timestamptz,token text,attempts integer NOT NULL DEFAULT 0,
 notified_revision integer NOT NULL DEFAULT 0,telegram_message_id bigint,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS vilqa.fiber_audit(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,entry_id bigint,job_key text,revision integer,before_data jsonb,after_data jsonb,created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS fiber_jobs_pending ON vilqa.fiber_jobs(status,ready_at);
CREATE OR REPLACE FUNCTION vilqa.fiber_key(d vilqa.diary) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
 SELECT md5(lower(trim(d.item_name))||':'||COALESCE(d.item_type,'')||':'||COALESCE((d.legacy_data->'fiber_recipe')::text,''));
$f$;
CREATE OR REPLACE FUNCTION vilqa.fiber_signature(d vilqa.diary) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
 SELECT md5(jsonb_build_array(d.item_name,d.item_type,d.weight,d.calories,d.protein,d.fats,d.carbs,d.legacy_data->'fiber_recipe')::text);
$f$;
CREATE OR REPLACE FUNCTION vilqa.fiber_group(d vilqa.diary) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
 SELECT COALESCE('draft:'||d.draft_id,'entry:'||d.id::text)||':'||COALESCE(d.date,'unknown');
$f$;
CREATE OR REPLACE FUNCTION vilqa.fiber_enqueue() RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE k text;changed boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM vilqa.fiber_config WHERE enabled) THEN RETURN NEW;END IF;
 IF NOT COALESCE(vilqa.access_check(NEW.user_id),false) THEN RETURN NEW;END IF;
 IF TG_OP='INSERT' THEN changed:=true;
 ELSE changed:=vilqa.fiber_signature(NEW) IS DISTINCT FROM vilqa.fiber_signature(OLD) OR NEW.date IS DISTINCT FROM OLD.date OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at;
 END IF;
 IF NOT changed THEN RETURN NEW;END IF;
 IF TG_OP='INSERT' OR vilqa.fiber_signature(NEW) IS DISTINCT FROM vilqa.fiber_signature(OLD) THEN
  NEW.fiber:=NULL;NEW.fiber_status:='pending';NEW.fiber_basis:=NULL;
 END IF;
 k:=vilqa.fiber_group(NEW);
 INSERT INTO vilqa.fiber_jobs(job_key,user_id,ready_at) VALUES(k,NEW.user_id,now()+interval '9 seconds')
 ON CONFLICT(job_key) DO UPDATE SET revision=vilqa.fiber_jobs.revision+1,status='pending',attempts=0,ready_at=now()+interval '9 seconds',lease_until=NULL,token=NULL,updated_at=now();
 IF TG_OP='UPDATE' AND NEW.date IS DISTINCT FROM OLD.date THEN
  INSERT INTO vilqa.fiber_jobs(job_key,user_id,ready_at) VALUES(vilqa.fiber_group(OLD),OLD.user_id,now()+interval '9 seconds')
  ON CONFLICT(job_key) DO UPDATE SET revision=vilqa.fiber_jobs.revision+1,status='pending',attempts=0,ready_at=now()+interval '9 seconds',lease_until=NULL,token=NULL,updated_at=now();
 END IF;
 RETURN NEW;
END $f$;
DROP TRIGGER IF EXISTS fiber_enqueue ON vilqa.diary;
CREATE TRIGGER fiber_enqueue BEFORE INSERT OR UPDATE ON vilqa.diary FOR EACH ROW EXECUTE FUNCTION vilqa.fiber_enqueue();

CREATE OR REPLACE FUNCTION vilqa.fiber_claim(p_executor text) RETURNS SETOF jsonb LANGUAGE plpgsql AS $f$
DECLARE j vilqa.fiber_jobs%ROWTYPE;items jsonb;days jsonb;profile jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM vilqa.fiber_config WHERE enabled) THEN RETURN;END IF;
 SELECT * INTO j FROM vilqa.fiber_jobs WHERE (status='pending' AND ready_at<=now() OR status='processing' AND lease_until<now()) AND attempts<3 AND vilqa.access_check(user_id) ORDER BY ready_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN;END IF;
 UPDATE vilqa.fiber_jobs SET status='processing',token=p_executor||':'||revision,attempts=attempts+1,lease_until=now()+interval '5 minutes',updated_at=now() WHERE job_key=j.job_key RETURNING * INTO j;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',d.id,'name',d.item_name,'weight',d.weight,'calories',d.calories,'protein',d.protein,'fats',d.fats,'carbs',d.carbs,'signature',vilqa.fiber_signature(d),'cache_key',vilqa.fiber_key(d),'fiber',CASE WHEN d.fiber_basis=vilqa.fiber_signature(d) THEN d.fiber END,'cached_per100',c.per100,'recipe',d.legacy_data->'fiber_recipe') ORDER BY d.id),'[]') INTO items FROM vilqa.diary d LEFT JOIN vilqa.fiber_cache c ON c.cache_key=vilqa.fiber_key(d) AND c.updated_at>now()-interval '180 days' WHERE vilqa.fiber_group(d)=j.job_key AND d.deleted_at IS NULL;
 SELECT jsonb_agg(DISTINCT date) INTO days FROM vilqa.diary d WHERE vilqa.fiber_group(d)=j.job_key;
 profile:=vilqa.resolve_profile(j.user_id,'{}');
 RETURN NEXT jsonb_build_object('job_key',j.job_key,'user_id',j.user_id,'revision',j.revision,'token',j.token,'items',items,'dates',days,'profile',jsonb_build_object('daily_calories',profile->'daily_calories','timezone',COALESCE(profile->>'timezone','Europe/Moscow')));
END $f$;

CREATE OR REPLACE FUNCTION vilqa.fiber_apply(p_job jsonb,p_values jsonb) RETURNS SETOF jsonb LANGUAGE plpgsql AS $f$
DECLARE j vilqa.fiber_jobs%ROWTYPE;r jsonb;d vilqa.diary%ROWTYPE;before jsonb;v numeric;dt text;summary jsonb;meal numeric;known integer;cnt integer;total numeric;cal numeric;target numeric;profile jsonb;unresolved integer;
BEGIN
 PERFORM id FROM vilqa.diary WHERE id IN (SELECT (value->>'id')::bigint FROM jsonb_array_elements(p_values)) ORDER BY id FOR UPDATE;
 SELECT * INTO j FROM vilqa.fiber_jobs WHERE job_key=p_job->>'job_key' FOR UPDATE;
 IF NOT FOUND OR j.status<>'processing' OR j.token IS DISTINCT FROM p_job->>'token' OR j.revision<>(p_job->>'revision')::integer OR NOT vilqa.access_check(j.user_id) THEN RETURN;END IF;
 IF jsonb_typeof(p_values)<>'array' OR jsonb_array_length(p_values)<>jsonb_array_length(p_job->'items') THEN RAISE EXCEPTION 'Invalid fiber item count';END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(p_values) LOOP
  SELECT * INTO d FROM vilqa.diary WHERE id=(r->>'id')::bigint AND user_id=j.user_id FOR UPDATE;
  IF NOT FOUND OR d.deleted_at IS NOT NULL OR vilqa.fiber_signature(d) IS DISTINCT FROM r->>'signature' THEN
   UPDATE vilqa.fiber_jobs SET status='pending',ready_at=now()+interval '9 seconds',token=NULL WHERE job_key=j.job_key;RETURN;
  END IF;
  v:=NULL;
  IF jsonb_typeof(r->'fiber')='number' THEN v:=round((r->>'fiber')::numeric,1);IF v<0 OR v>d.weight THEN RAISE EXCEPTION 'Invalid fiber quantity';END IF;END IF;
  before:=jsonb_build_object('fiber',d.fiber,'fiber_status',d.fiber_status);
  UPDATE vilqa.diary SET fiber=v,fiber_status=CASE WHEN v IS NULL THEN 'unknown' WHEN d.fiber_status='manual' THEN 'manual' ELSE 'estimated' END,fiber_basis=vilqa.fiber_signature(d) WHERE id=d.id;
  INSERT INTO vilqa.fiber_audit(entry_id,job_key,revision,before_data,after_data) VALUES(d.id,j.job_key,j.revision,before,jsonb_build_object('fiber',v,'source','ai_estimate'));
  IF v IS NOT NULL AND d.weight>0 AND d.fiber_status<>'manual' THEN INSERT INTO vilqa.fiber_cache(cache_key,per100) VALUES(vilqa.fiber_key(d),v*100/d.weight) ON CONFLICT(cache_key) DO UPDATE SET per100=EXCLUDED.per100,updated_at=now();END IF;
 END LOOP;
 UPDATE vilqa.fiber_jobs SET status='done',lease_until=NULL,updated_at=now() WHERE job_key=j.job_key;
 SELECT min(q.date) INTO dt FROM vilqa.diary q WHERE vilqa.fiber_group(q)=j.job_key;
 dt:=COALESCE(dt,right(j.job_key,10));
 SELECT COALESCE(sum(q.fiber),0),count(q.fiber),count(*) INTO meal,known,cnt FROM vilqa.diary q WHERE vilqa.fiber_group(q)=j.job_key AND q.deleted_at IS NULL;
 SELECT COALESCE(sum(fiber),0),count(*) FILTER(WHERE fiber IS NULL),COALESCE(sum(calories),0) INTO total,unresolved,cal FROM vilqa.diary WHERE user_id=j.user_id AND date=dt AND deleted_at IS NULL;
 SELECT daily_target INTO target FROM vilqa.fiber_settings WHERE user_id=j.user_id;target:=COALESCE(target,25);profile:=vilqa.resolve_profile(j.user_id,'{}');
 IF j.notified_revision>=j.revision THEN RETURN;END IF;
 RETURN NEXT jsonb_build_object('job_key',j.job_key,'revision',j.revision,'token',j.token,'user_id',j.user_id,'date',dt,'meal_fiber',CASE WHEN cnt=0 THEN NULL ELSE meal END,'meal_unknown',cnt-known,'deleted',cnt=0,'day_fiber',total,'day_unknown',unresolved,'target',target,'remaining',GREATEST(0,target-total),'remaining_calories',GREATEST(0,COALESCE((profile->>'daily_calories')::numeric,0)-cal));
END $f$;

CREATE OR REPLACE FUNCTION vilqa.fiber_reserve_notice(p jsonb) RETURNS SETOF jsonb LANGUAGE plpgsql AS $f$
BEGIN
 UPDATE vilqa.fiber_jobs SET notified_revision=revision WHERE job_key=p->>'job_key' AND revision=(p->>'revision')::integer AND token=p->>'token' AND status='done' AND notified_revision<revision AND vilqa.access_check(user_id);
 IF FOUND THEN RETURN NEXT p;END IF;
END $f$;

CREATE OR REPLACE FUNCTION vilqa.fiber_api(p_actor bigint,p_req jsonb,p_profiles jsonb DEFAULT '[]') RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE r jsonb;uid bigint:=COALESCE((p_req->>'user_id')::bigint,p_actor);target numeric;f jsonb;v numeric;d vilqa.diary%ROWTYPE;
BEGIN
 IF NOT vilqa.access_check(p_actor) OR (uid<>p_actor AND NOT EXISTS(SELECT 1 FROM vilqa.admins WHERE user_id=p_actor)) OR (uid<>0 AND NOT vilqa.access_check(uid)) THEN RETURN jsonb_build_object('success',false,'status',403,'message','Нет доступа');END IF;
 IF p_req->>'action'='fiber_settings' THEN
  IF jsonb_typeof(p_req->'weight')<>'number' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Укажи ориентир клетчатки');END IF;
  target:=(p_req->>'weight')::numeric;IF target<1 OR target>100 THEN RETURN jsonb_build_object('success',false,'status',400,'message','Ориентир должен быть от 1 до 100 г');END IF;
  INSERT INTO vilqa.fiber_settings(user_id,daily_target) VALUES(uid,round(target,1)) ON CONFLICT(user_id) DO UPDATE SET daily_target=EXCLUDED.daily_target,updated_at=now();
  RETURN jsonb_build_object('success',true,'daily_fiber',round(target,1));
 END IF;
 IF p_req->>'action'='profile_edit' AND p_req->'patch' ? 'daily_fiber' THEN
  IF jsonb_typeof(p_req#>'{patch,daily_fiber}')<>'number' OR (p_req#>>'{patch,daily_fiber}')::numeric NOT BETWEEN 1 AND 100 THEN RETURN jsonb_build_object('success',false,'status',400,'message','Ориентир клетчатки должен быть от 1 до 100 г');END IF;
 END IF;
 IF p_req->>'action'='edit' AND p_req->'patch' ? 'fiber' THEN
  IF jsonb_typeof(p_req#>'{patch,fiber}') NOT IN ('number','null') THEN RETURN jsonb_build_object('success',false,'status',400,'message','Проверь клетчатку');END IF;
  v:=(p_req#>>'{patch,fiber}')::numeric;
  IF v<0 OR v>COALESCE((p_req#>>'{patch,weight}')::numeric,10000) THEN RETURN jsonb_build_object('success',false,'status',400,'message','Клетчатка не может превышать вес порции');END IF;
 END IF;
 r:=vilqa.private_api(p_actor,p_req,p_profiles);IF r->>'success'<>'true' THEN RETURN r;END IF;
 IF p_req->>'action'='profile_edit' AND p_req->'patch' ? 'daily_fiber' THEN
  INSERT INTO vilqa.fiber_settings(user_id,daily_target) VALUES(uid,round((p_req#>>'{patch,daily_fiber}')::numeric,1)) ON CONFLICT(user_id) DO UPDATE SET daily_target=EXCLUDED.daily_target,updated_at=now();
 END IF;
 IF p_req->>'action'='edit' AND p_req->'patch' ? 'fiber' THEN
  SELECT * INTO d FROM vilqa.diary WHERE id=(p_req->>'id')::bigint AND user_id=uid;
  IF FOUND AND d.version=(r#>>'{entry,version}')::integer THEN
   UPDATE vilqa.diary SET fiber=v,fiber_status=CASE WHEN v IS NULL THEN 'unknown' ELSE 'manual' END,fiber_basis=vilqa.fiber_signature(d) WHERE id=d.id RETURNING * INTO d;
   r:=jsonb_set(r,'{entry}',to_jsonb(d));
   INSERT INTO vilqa.fiber_audit(entry_id,before_data,after_data) VALUES(d.id,NULL,jsonb_build_object('fiber',v,'source','manual','actor',p_actor));
  END IF;
 END IF;
 SELECT daily_target INTO target FROM vilqa.fiber_settings WHERE user_id=uid;target:=COALESCE(target,25);
 IF r ? 'profile' THEN r:=jsonb_set(r,'{profile}',(r->'profile')||jsonb_build_object('daily_fiber',target));END IF;
 IF p_req->>'action'='day' THEN
  SELECT jsonb_build_object('fiber',COALESCE(sum(fiber),0),'fiber_known',count(fiber),'fiber_unknown',count(*) FILTER(WHERE fiber IS NULL)) INTO f FROM vilqa.diary WHERE user_id=uid AND date=r->>'date' AND deleted_at IS NULL;
  r:=jsonb_set(r,'{totals}',(r->'totals')||f);
 END IF;
 RETURN r;
END $f$;
COMMIT;
