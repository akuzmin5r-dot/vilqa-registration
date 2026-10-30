BEGIN;
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
 INSERT INTO vilqa.fiber_jobs(job_key,user_id,ready_at) VALUES(k,NEW.user_id,now()+interval '60 seconds')
 ON CONFLICT(job_key) DO UPDATE SET revision=vilqa.fiber_jobs.revision+1,status='pending',attempts=0,ready_at=now()+interval '60 seconds',lease_until=NULL,token=NULL,updated_at=now();
 IF TG_OP='UPDATE' AND NEW.date IS DISTINCT FROM OLD.date THEN
  INSERT INTO vilqa.fiber_jobs(job_key,user_id,ready_at) VALUES(vilqa.fiber_group(OLD),OLD.user_id,now()+interval '60 seconds')
  ON CONFLICT(job_key) DO UPDATE SET revision=vilqa.fiber_jobs.revision+1,status='pending',attempts=0,ready_at=now()+interval '60 seconds',lease_until=NULL,token=NULL,updated_at=now();
 END IF;
 RETURN NEW;
END $f$;

CREATE OR REPLACE FUNCTION vilqa.fiber_claim_for_user(p_executor text,p_user bigint) RETURNS SETOF jsonb LANGUAGE plpgsql AS $f$
DECLARE j vilqa.fiber_jobs%ROWTYPE;items jsonb;days jsonb;profile jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM vilqa.fiber_config WHERE enabled) THEN RETURN;END IF;
 SELECT * INTO j FROM vilqa.fiber_jobs WHERE (status='pending' AND (ready_at<=now() OR p_user IS NOT NULL) OR status='processing' AND lease_until<now()) AND attempts<3 AND (p_user IS NULL OR user_id=p_user) AND vilqa.access_check(user_id) ORDER BY ready_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN;END IF;
 UPDATE vilqa.fiber_jobs SET status='processing',token=p_executor||':'||revision,attempts=attempts+1,lease_until=now()+interval '5 minutes',updated_at=now() WHERE job_key=j.job_key RETURNING * INTO j;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',d.id,'name',d.item_name,'weight',d.weight,'calories',d.calories,'protein',d.protein,'fats',d.fats,'carbs',d.carbs,'signature',vilqa.fiber_signature(d),'cache_key',vilqa.fiber_key(d),'fiber',CASE WHEN d.fiber_basis=vilqa.fiber_signature(d) THEN d.fiber END,'cached_per100',c.per100,'recipe',d.legacy_data->'fiber_recipe') ORDER BY d.id),'[]') INTO items FROM vilqa.diary d LEFT JOIN vilqa.fiber_cache c ON c.cache_key=vilqa.fiber_key(d) AND c.updated_at>now()-interval '180 days' WHERE vilqa.fiber_group(d)=j.job_key AND d.deleted_at IS NULL;
 SELECT jsonb_agg(DISTINCT date) INTO days FROM vilqa.diary d WHERE vilqa.fiber_group(d)=j.job_key;
 profile:=vilqa.resolve_profile(j.user_id,'{}');
 RETURN NEXT jsonb_build_object('job_key',j.job_key,'user_id',j.user_id,'revision',j.revision,'token',j.token,'items',items,'dates',days,'profile',jsonb_build_object('daily_calories',profile->'daily_calories','timezone',COALESCE(profile->>'timezone','Europe/Moscow')));
END $f$;


COMMIT;
