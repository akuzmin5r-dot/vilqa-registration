BEGIN;
DO $t$
DECLARE r jsonb;n integer;
BEGIN
 SELECT x INTO r FROM vilqa.status_begin(180753266,'stats','status_unit_test','test_status_1') x;
 IF r IS NULL THEN RAISE EXCEPTION 'Did not claim';END IF;
 SELECT count(*) INTO n FROM vilqa.status_begin(180753266,'stats','status_unit_test','test_status_2');IF n<>0 THEN RAISE EXCEPTION 'Allowed duplicate';END IF;
 PERFORM vilqa.status_attach(180753266,'stats',md5('status_unit_test'),'test_status_1',999);
 FOR n IN 1..4 LOOP
  SELECT x INTO r FROM vilqa.status_tick(180753266,'stats',md5('status_unit_test'),'test_status_1') x;
  IF (r->>'frame')::integer<>((n-1)%3+1) THEN RAISE EXCEPTION 'Wrong frame';END IF;
 END LOOP;
 r:=vilqa.status_finish(180753266,'stats','status_unit_test','test_status_2');IF (r->>'message_id')::bigint IS NOT NULL THEN RAISE EXCEPTION 'Old owner finished other operation';END IF;
 r:=vilqa.status_finish(180753266,'stats','status_unit_test','test_status_1');IF (r->>'message_id')::bigint<>999 THEN RAISE EXCEPTION 'Missing cleanup id';END IF;
 SELECT count(*) INTO n FROM vilqa.status_tick(180753266,'stats',md5('status_unit_test'),'test_status_1');IF n<>0 THEN RAISE EXCEPTION 'Animation after finish';END IF;
 PERFORM vilqa.status_begin(180753266,'stats','status_unit_test','test_status_3');
 UPDATE vilqa.processing_status SET expires_at=now()-interval '1 second' WHERE user_id=180753266 AND scope=md5('status_unit_test');
 PERFORM vilqa.status_begin(180753266,'stats','status_unit_test','test_status_4');
 r:=vilqa.status_finish(180753266,'stats','status_unit_test','test_status_3');
 IF NOT EXISTS(SELECT 1 FROM vilqa.processing_status WHERE user_id=180753266 AND scope=md5('status_unit_test') AND owner_execution='test_status_4' AND state='active') THEN RAISE EXCEPTION 'Old owner corrupted newer operation';END IF;
 SELECT count(*) INTO n FROM vilqa.status_abort('test_status_4');IF n<>1 THEN RAISE EXCEPTION 'Abort did not release';END IF;
 SELECT count(*) INTO n FROM vilqa.status_begin(999999,'stats','status_unit_test','test_status_5');IF n<>0 THEN RAISE EXCEPTION 'Unauthorized status';END IF;
END $t$;
ROLLBACK;
SELECT 'PASS: deduplication, frame sequence, stop, owner isolation, expiry, error cleanup, access and rollback' AS result;
