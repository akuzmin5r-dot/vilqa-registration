BEGIN;
INSERT INTO vilqa.diary(id,user_id,date,time,item_name,weight,calories,protein,fats,carbs) VALUES(-91001,123,'2026-10-24','12:00','Original',100,100,10,3,12);
DO $test$
DECLARE r jsonb; q jsonb; audit_id bigint; cnt integer; x jsonb;
BEGIN
 r:=vilqa.api(456,'{"action":"day","user_id":123}');
 IF (r->>'status')::int<>403 THEN RAISE EXCEPTION 'Cross-user read'; END IF;
 r:=vilqa.api(123,'{"action":"users"}');IF (r->>'status')::int<>403 THEN RAISE EXCEPTION 'User got admin';END IF;
 r:=vilqa.api(180753266,'{"action":"day","user_id":123,"date":"2026-10-24"}');IF NOT (r->>'success')::boolean THEN RAISE EXCEPTION 'Admin read blocked';END IF;
 q:='{"action":"edit","id":-91001,"version":1,"request_id":"test-edit-00000001","patch":{"item_name":"Edited","weight":200,"calories":200,"protein":20,"fats":6,"carbs":24}}';
 r:=vilqa.api(123,q);IF (r->'entry'->>'version')::int<>2 THEN RAISE EXCEPTION 'Edit failed';END IF;
 r:=vilqa.api(123,q);IF (r->'entry'->>'version')::int<>2 THEN RAISE EXCEPTION 'Retry duplicated edit';END IF;
 r:=vilqa.api(123,q||'{"request_id":"test-edit-00000002"}');IF (r->>'status')::int<>409 THEN RAISE EXCEPTION 'Lost update accepted';END IF;
 r:=vilqa.api(123,q||'{"patch":{"item_name":"Missing values"},"version":2,"request_id":"test-invalid-000001"}');IF (r->>'status')::int<>400 THEN RAISE EXCEPTION 'Missing numbers accepted';END IF;
 r:=vilqa.api(123,'{"action":"delete","id":-91001,"version":2,"request_id":"test-delete-000001"}');IF r->'entry'->>'deleted_at' IS NULL THEN RAISE EXCEPTION 'Delete failed';END IF;
 r:=vilqa.api(123,'{"action":"day","date":"2026-10-24"}');IF (r->'totals'->>'count')::int<>0 THEN RAISE EXCEPTION 'Deleted row counted';END IF;
 r:=vilqa.api(123,'{"action":"restore","id":-91001,"version":3,"request_id":"test-restore-00001"}');IF r->'entry'->>'deleted_at' IS NOT NULL THEN RAISE EXCEPTION 'Restore failed';END IF;
 SELECT id INTO audit_id FROM vilqa.audit WHERE entry_id=-91001 AND action='edit';
 r:=vilqa.api(123,jsonb_build_object('action','revert','id',-91001,'version',4,'request_id','test-revert-000001','audit_id',audit_id));IF r->'entry'->>'item_name'<>'Original' THEN RAISE EXCEPTION 'Previous values not restored';END IF;
 SELECT count(*) INTO cnt FROM vilqa.audit WHERE entry_id=-91001;IF cnt<>4 THEN RAISE EXCEPTION 'Audit missing';END IF;
 r:=vilqa.api(456,'{"action":"audit","id":-91001,"user_id":123}');IF (r->>'status')::int<>403 THEN RAISE EXCEPTION 'Audit leaked';END IF;
 x:='{"user_id":123,"date":"2026-10-24","time":"12:00","item_name":"Test","weight":100,"calories":100,"protein":10,"fats":3,"carbs":12}';
 INSERT INTO public.vilqa_meal_drafts(draft_id,user_id,chat_id,payload) VALUES('diary-test-good',123,123,jsonb_build_object('rows',jsonb_build_array(x,x))),('diary-test-bad',123,123,jsonb_build_object('rows',jsonb_build_array(x,x||'{"weight":-1}')));
 r:=vilqa.confirm_meal('diary-test-good',123,123,'confirm');IF NOT (r->>'committed')::boolean THEN RAISE EXCEPTION 'Commit failed';END IF;
 r:=vilqa.confirm_meal('diary-test-good',123,123,'confirm');IF r->>'outcome'<>'already_saved' THEN RAISE EXCEPTION 'Retry duplicated meal';END IF;
 BEGIN
  PERFORM vilqa.confirm_meal('diary-test-bad',123,123,'confirm');RAISE EXCEPTION 'Expected invalid second product';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='Expected invalid second product' THEN RAISE;END IF;END;
 SELECT count(*) INTO cnt FROM vilqa.diary WHERE draft_id='diary-test-bad';IF cnt<>0 THEN RAISE EXCEPTION 'Partial meal committed';END IF;
 IF (SELECT status FROM public.vilqa_meal_drafts WHERE draft_id='diary-test-bad')<>'pending' THEN RAISE EXCEPTION 'Draft changed on failure';END IF;
END $test$;
ROLLBACK;
SELECT 17 AS passed,'rolled_back' AS test_data;
