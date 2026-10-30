BEGIN;
DO $t$
DECLARE u bigint:=900000000003; a bigint; k text; j jsonb; n integer;
BEGIN
 IF EXISTS(SELECT 1 FROM vilqa.access_members WHERE user_id=u) THEN RAISE EXCEPTION 'Test user exists'; END IF;
 INSERT INTO vilqa.access_members(user_id,granted_by) VALUES(u,180753266);
 INSERT INTO vilqa.diary(user_id,date,time,item_name,item_type,weight,calories,protein,fats,carbs,draft_id,item_index) VALUES(u,'1900-01-01','12:00','QUIET FIBER TEST','product',100,100,1,1,1,'quiet_fiber_transaction',0) RETURNING id INTO a;
 SELECT vilqa.fiber_group(d) INTO k FROM vilqa.diary d WHERE id=a;
 IF (SELECT notify_chat FROM vilqa.fiber_jobs WHERE job_key=k) IS DISTINCT FROM true THEN RAISE EXCEPTION 'New meal is silent'; END IF;
 UPDATE vilqa.diary SET weight=120 WHERE id=a;
 IF (SELECT notify_chat FROM vilqa.fiber_jobs WHERE job_key=k) IS DISTINCT FROM false THEN RAISE EXCEPTION 'Edit sends notification'; END IF;
 UPDATE vilqa.diary SET deleted_at=now() WHERE id=a;
 IF (SELECT notify_chat FROM vilqa.fiber_jobs WHERE job_key=k) IS DISTINCT FROM false THEN RAISE EXCEPTION 'Deletion sends notification'; END IF;
 SELECT x INTO j FROM vilqa.fiber_claim_for_user('quiet_test',u) x;
 IF j->'notify_chat'<>'false'::jsonb OR jsonb_array_length(j->'items')<>0 THEN RAISE EXCEPTION 'Deleted meal claimed incorrectly'; END IF;
 UPDATE vilqa.fiber_jobs SET status='done' WHERE job_key=k;
 SELECT count(*) INTO n FROM vilqa.fiber_reserve_notice(j);IF n<>0 THEN RAISE EXCEPTION 'Quiet job sent notice';END IF;
 UPDATE vilqa.fiber_jobs SET notify_chat=true WHERE job_key=k;
 SELECT count(*) INTO n FROM vilqa.fiber_reserve_notice(j);IF n<>1 THEN RAISE EXCEPTION 'New meal notice blocked';END IF;
 SELECT count(*) INTO n FROM vilqa.fiber_reserve_notice(j);IF n<>0 THEN RAISE EXCEPTION 'Duplicate notice allowed';END IF;
 UPDATE vilqa.fiber_jobs SET revision=revision+1 WHERE job_key=k;
 SELECT count(*) INTO n FROM vilqa.fiber_reserve_notice(j);IF n<>0 THEN RAISE EXCEPTION 'Stale notice allowed';END IF;
END $t$;
ROLLBACK;
SELECT 'PASS: additions notify; edits and deletion silent; duplicate and stale notices blocked; all fixtures rolled back' AS result;
