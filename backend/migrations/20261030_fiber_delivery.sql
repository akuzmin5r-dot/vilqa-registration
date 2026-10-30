BEGIN;
CREATE TABLE IF NOT EXISTS vilqa.fiber_deliveries(
 job_key text NOT NULL,revision integer NOT NULL,user_id bigint NOT NULL,payload jsonb NOT NULL,
 state text NOT NULL DEFAULT 'pending' CHECK(state IN('pending','sending','sent','failed','unknown','superseded')),
 token text,attempts integer NOT NULL DEFAULT 0,ready_at timestamptz NOT NULL DEFAULT now(),lease_until timestamptz,
 message_id bigint,last_error text,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(job_key,revision));
CREATE INDEX IF NOT EXISTS fiber_deliveries_pending ON vilqa.fiber_deliveries(state,ready_at);

CREATE OR REPLACE FUNCTION vilqa.fiber_queue_notice(p jsonb) RETURNS SETOF jsonb LANGUAGE plpgsql AS $f$
DECLARE d vilqa.fiber_deliveries%ROWTYPE;
BEGIN
 IF p IS NOT NULL AND p<>'null'::jsonb THEN
  INSERT INTO vilqa.fiber_deliveries(job_key,revision,user_id,payload)
  SELECT job_key,revision,user_id,p FROM vilqa.fiber_jobs
  WHERE job_key=p->>'job_key' AND revision=(p->>'revision')::integer AND token=p->>'token'
   AND status='done' AND notify_chat AND notified_revision<revision AND vilqa.access_check(user_id)
  ON CONFLICT(job_key,revision) DO NOTHING;
 END IF;
 -- An expired request may already have reached Telegram. Do not blindly send it again.
 UPDATE vilqa.fiber_deliveries SET state='unknown',last_error='delivery_lease_expired',updated_at=now()
 WHERE state='sending' AND lease_until<now();
 UPDATE vilqa.fiber_deliveries q SET state='superseded',updated_at=now()
 WHERE q.state='pending' AND NOT EXISTS(SELECT 1 FROM vilqa.fiber_jobs j WHERE j.job_key=q.job_key
  AND j.revision=q.revision AND j.notify_chat AND j.notified_revision<j.revision AND vilqa.access_check(j.user_id));
 SELECT * INTO d FROM vilqa.fiber_deliveries q WHERE q.state='pending' AND q.ready_at<=now() AND q.attempts<3
  AND (p IS NULL OR p='null'::jsonb OR q.job_key=p->>'job_key' AND q.revision=(p->>'revision')::integer)
  ORDER BY q.ready_at,q.created_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN;END IF;
 UPDATE vilqa.fiber_deliveries SET state='sending',token=md5(random()::text||clock_timestamp()::text),
  attempts=attempts+1,lease_until=now()+interval '2 minutes',updated_at=now()
  WHERE job_key=d.job_key AND revision=d.revision RETURNING * INTO d;
 RETURN NEXT d.payload||jsonb_build_object('delivery_token',d.token);
END $f$;

CREATE OR REPLACE FUNCTION vilqa.fiber_finish_notice(p jsonb,p_response jsonb) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE d vilqa.fiber_deliveries%ROWTYPE;m jsonb:=COALESCE(p_response->'result',p_response);msg bigint;
 code integer;next_state text;retry_seconds integer:=30;
BEGIN
 SELECT * INTO d FROM vilqa.fiber_deliveries WHERE job_key=p->>'job_key' AND revision=(p->>'revision')::integer FOR UPDATE;
 IF NOT FOUND OR d.state<>'sending' OR d.token IS DISTINCT FROM p->>'delivery_token' THEN RETURN jsonb_build_object('state','ignored');END IF;
 IF m->>'message_id' ~ '^[0-9]+$' AND m#>>'{chat,id}'=d.user_id::text THEN
  msg:=(m->>'message_id')::bigint;next_state:='sent';
 ELSE
  code:=CASE WHEN p_response->>'error_code' ~ '^[0-9]{3}$' THEN (p_response->>'error_code')::integer
   WHEN p_response#>>'{error,error_code}' ~ '^[0-9]{3}$' THEN (p_response#>>'{error,error_code}')::integer
   WHEN p_response#>>'{error,httpCode}' ~ '^[0-9]{3}$' THEN (p_response#>>'{error,httpCode}')::integer END;
  -- Only an explicit Telegram rejection is safe to retry automatically.
  next_state:=CASE WHEN code=429 OR code>=500 THEN CASE WHEN d.attempts<3 THEN 'pending' ELSE 'failed' END
   WHEN code BETWEEN 400 AND 499 THEN 'failed' ELSE 'unknown' END;
  IF p_response#>>'{parameters,retry_after}' ~ '^[0-9]{1,5}$' THEN retry_seconds:=LEAST(3600,GREATEST(1,(p_response#>>'{parameters,retry_after}')::integer));END IF;
 END IF;
 UPDATE vilqa.fiber_deliveries SET state=next_state,message_id=msg,lease_until=NULL,ready_at=now()+make_interval(secs=>retry_seconds),
  last_error=CASE WHEN next_state='sent' THEN NULL ELSE COALESCE('telegram_'||code::text,'telegram_response_unconfirmed') END,
  updated_at=now() WHERE job_key=d.job_key AND revision=d.revision;
 IF next_state='sent' THEN
  UPDATE vilqa.fiber_jobs SET notified_revision=d.revision,telegram_message_id=msg
   WHERE job_key=d.job_key AND revision=d.revision;
 END IF;
 RETURN jsonb_build_object('state',next_state,'job_key',d.job_key,'revision',d.revision,'message_id',msg);
END $f$;
COMMIT;
