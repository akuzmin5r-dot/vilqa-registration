BEGIN;
CREATE TABLE IF NOT EXISTS vilqa.processing_status(
 user_id bigint NOT NULL,kind text NOT NULL,scope text NOT NULL DEFAULT '',owner_execution text NOT NULL,
 state text NOT NULL DEFAULT 'active',message_id bigint,frame integer NOT NULL DEFAULT 0,
 expires_at timestamptz NOT NULL DEFAULT now()+interval '5 minutes',updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,kind,scope));
CREATE OR REPLACE FUNCTION vilqa.status_begin(p_user bigint,p_kind text,p_scope text,p_owner text) RETURNS SETOF jsonb LANGUAGE plpgsql AS $f$
DECLARE r vilqa.processing_status%ROWTYPE;k text:=md5(COALESCE(p_scope,''));
BEGIN
 IF NOT COALESCE(vilqa.access_check(p_user),false) OR p_kind NOT IN ('food','stats','recommendations','recipe','voice','fiber') OR p_owner !~ '^[A-Za-z0-9_-]{1,80}$' THEN RETURN;END IF;
 INSERT INTO vilqa.processing_status(user_id,kind,scope,owner_execution) VALUES(p_user,p_kind,k,p_owner)
 ON CONFLICT(user_id,kind,scope) DO UPDATE SET owner_execution=EXCLUDED.owner_execution,state='active',message_id=NULL,frame=0,expires_at=now()+interval '5 minutes',updated_at=now()
 WHERE vilqa.processing_status.state<>'active' OR vilqa.processing_status.expires_at<now()
 RETURNING * INTO r;
 IF FOUND THEN RETURN NEXT to_jsonb(r);END IF;
END $f$;
CREATE OR REPLACE FUNCTION vilqa.status_attach(p_user bigint,p_kind text,p_scope text,p_owner text,p_message bigint) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE r vilqa.processing_status%ROWTYPE;
BEGIN
 UPDATE vilqa.processing_status SET message_id=NULLIF(p_message,0),updated_at=now() WHERE user_id=p_user AND kind=p_kind AND scope=p_scope AND owner_execution=p_owner AND state='active' RETURNING * INTO r;
 RETURN to_jsonb(r);
END $f$;
CREATE OR REPLACE FUNCTION vilqa.status_tick(p_user bigint,p_kind text,p_scope text,p_owner text) RETURNS SETOF jsonb LANGUAGE plpgsql AS $f$
DECLARE r vilqa.processing_status%ROWTYPE;
BEGIN
 UPDATE vilqa.processing_status SET frame=frame%3+1,state=CASE WHEN expires_at<=now() THEN 'expired' ELSE state END,updated_at=now()
 WHERE user_id=p_user AND kind=p_kind AND scope=p_scope AND owner_execution=p_owner AND state='active' AND message_id IS NOT NULL RETURNING * INTO r;
 IF FOUND THEN RETURN NEXT to_jsonb(r)||jsonb_build_object('expired',r.state='expired');END IF;
END $f$;
CREATE OR REPLACE FUNCTION vilqa.status_finish(p_user bigint,p_kind text,p_scope text,p_owner text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE r vilqa.processing_status%ROWTYPE;
BEGIN
 UPDATE vilqa.processing_status SET state='finished',updated_at=now() WHERE user_id=p_user AND kind=p_kind AND scope=md5(COALESCE(p_scope,'')) AND owner_execution=p_owner AND state='active' RETURNING * INTO r;
 RETURN COALESCE(to_jsonb(r),jsonb_build_object('user_id',p_user,'message_id',NULL));
END $f$;
CREATE OR REPLACE FUNCTION vilqa.status_abort(p_owner text) RETURNS SETOF jsonb LANGUAGE sql AS $f$
 UPDATE vilqa.processing_status SET state='failed',updated_at=now() WHERE owner_execution=p_owner AND state='active' RETURNING to_jsonb(processing_status);
$f$;
COMMIT;
