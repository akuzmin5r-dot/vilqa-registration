BEGIN;
DO $t$
DECLARE j jsonb;n integer;u bigint:=900000000001;v bigint:=900000000002;
BEGIN
 IF EXISTS(SELECT 1 FROM vilqa.access_members WHERE user_id IN(u,v)) THEN RAISE EXCEPTION 'Test identifiers already exist';END IF;
 INSERT INTO vilqa.access_members(user_id,granted_by) VALUES(u,180753266),(v,180753266);
 INSERT INTO vilqa.fiber_jobs(job_key,user_id,ready_at) VALUES('test_after_stats_1',u,now()+interval '60 seconds'),('test_after_stats_2',v,now()-interval '60 seconds');
 SELECT x INTO j FROM vilqa.fiber_claim_for_user('test_stats',u) x;
 IF j->>'job_key'<>'test_after_stats_1' THEN RAISE EXCEPTION 'Wrong user or did not skip fallback delay';END IF;
 IF (SELECT status FROM vilqa.fiber_jobs WHERE job_key='test_after_stats_2')<>'pending' THEN RAISE EXCEPTION 'Touched another user job';END IF;
 SELECT count(*) INTO n FROM vilqa.fiber_claim_for_user('test_stats_repeat',u);IF n<>0 THEN RAISE EXCEPTION 'Duplicate claim';END IF;
 UPDATE vilqa.access_members SET revoked_at=now() WHERE user_id=v;
 SELECT count(*) INTO n FROM vilqa.fiber_claim_for_user('test_stats_revoked',v);IF n<>0 THEN RAISE EXCEPTION 'Claimed revoked user';END IF;
END $t$;
ROLLBACK;
SELECT 'PASS: after-stats claim skips delay, selects correct user, duplicate and access guarded; all fixtures rolled back' AS result;
