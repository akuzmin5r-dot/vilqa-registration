BEGIN;
DO $t$
DECLARE u bigint:=900000000011;p jsonb;n jsonb;r jsonb;count_rows integer;
BEGIN
 IF EXISTS(SELECT 1 FROM vilqa.access_members WHERE user_id=u) THEN RAISE EXCEPTION 'Fixture collision';END IF;
 INSERT INTO vilqa.access_members(user_id,granted_by) VALUES(u,180753266);
 INSERT INTO vilqa.fiber_jobs(job_key,user_id,status,token,notify_chat) VALUES('test_delivery',u,'done','compute',true);
 p:=jsonb_build_object('job_key','test_delivery','revision',1,'token','compute','user_id',u,'text','TEST');
 SELECT x INTO n FROM vilqa.fiber_queue_notice(p) x;
 IF n->>'delivery_token' IS NULL THEN RAISE EXCEPTION 'No delivery lease';END IF;
 IF (SELECT notified_revision FROM vilqa.fiber_jobs WHERE job_key='test_delivery')<>0 THEN RAISE EXCEPTION 'Marked delivered before Telegram';END IF;
 SELECT count(*) INTO count_rows FROM vilqa.fiber_queue_notice(p);IF count_rows<>0 THEN RAISE EXCEPTION 'Concurrent duplicate';END IF;
 r:=vilqa.fiber_finish_notice(n,'{"ok":false,"error_code":429,"parameters":{"retry_after":1}}');
 IF r->>'state'<>'pending' THEN RAISE EXCEPTION 'Rejected send not retryable';END IF;
 UPDATE vilqa.fiber_deliveries SET ready_at=now()-interval '1 second' WHERE job_key='test_delivery';
 SELECT x INTO n FROM vilqa.fiber_queue_notice(NULL) x;
 r:=vilqa.fiber_finish_notice(n,jsonb_build_object('ok',true,'result',jsonb_build_object('message_id',123456,'chat',jsonb_build_object('id',u))));
 IF r->>'state'<>'sent' OR (SELECT notified_revision FROM vilqa.fiber_jobs WHERE job_key='test_delivery')<>1 THEN RAISE EXCEPTION 'Successful delivery not saved';END IF;
 SELECT count(*) INTO count_rows FROM vilqa.fiber_queue_notice(p);IF count_rows<>0 THEN RAISE EXCEPTION 'Delivered twice';END IF;
 UPDATE vilqa.fiber_jobs SET revision=2,token='next' WHERE job_key='test_delivery';p:=p||'{"revision":2,"token":"next"}'::jsonb;
 SELECT x INTO n FROM vilqa.fiber_queue_notice(p) x;
 r:=vilqa.fiber_finish_notice(n,'{"error":{"message":"request timeout"}}');IF r->>'state'<>'unknown' THEN RAISE EXCEPTION 'Ambiguous send retried';END IF;
 SELECT count(*) INTO count_rows FROM vilqa.fiber_queue_notice(NULL);IF count_rows<>0 THEN RAISE EXCEPTION 'Unknown send repeated';END IF;
 UPDATE vilqa.fiber_jobs SET revision=3,token='quiet',notify_chat=false WHERE job_key='test_delivery';p:=p||'{"revision":3,"token":"quiet"}'::jsonb;
 SELECT count(*) INTO count_rows FROM vilqa.fiber_queue_notice(p);IF count_rows<>0 THEN RAISE EXCEPTION 'Quiet edit delivered';END IF;
END $t$;
ROLLBACK;
SELECT 'PASS: acknowledgment, same-key exclusion, 429 retry, successful delivery, timeout ambiguity, quiet edits; fixtures rolled back' AS result;
