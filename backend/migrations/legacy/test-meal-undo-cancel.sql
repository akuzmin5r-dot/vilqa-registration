BEGIN;
DO $test$
DECLARE x jsonb;r jsonb;n integer;
BEGIN
 x:='{"user_id":123,"date":"2026-10-25","time":"16:08","item_name":"Undo test","weight":150,"calories":358,"protein":45,"fats":21,"carbs":0}';
 INSERT INTO public.vilqa_meal_drafts(draft_id,user_id,chat_id,payload) VALUES
 ('undo-test-ok',123,123,jsonb_build_object('rows',jsonb_build_array(x,x||'{"item_name":"Second","weight":200,"calories":260}'))),
 ('undo-test-bad',123,123,jsonb_build_object('rows',jsonb_build_array(x,x||'{"weight":-1}'))),
 ('undo-test-expired',123,123,jsonb_build_object('rows',jsonb_build_array(x)));
 r:=vilqa.confirm_meal('undo-test-ok',123,123,'restore');IF COALESCE((r->>'committed')::boolean,false) THEN RAISE EXCEPTION 'Pending restored without cancellation';END IF;
 r:=vilqa.confirm_meal('undo-test-ok',123,123,'cancel');IF r->>'outcome'<>'cancelled' OR r->>'can_restore'<>'true' THEN RAISE EXCEPTION 'Cancellation must offer explicit undo';END IF;
 IF EXISTS(SELECT 1 FROM vilqa.diary WHERE draft_id='undo-test-ok') THEN RAISE EXCEPTION 'Cancel saved rows';END IF;
 r:=vilqa.confirm_meal('undo-test-ok',123,123,'confirm');IF r->>'outcome'<>'cancelled' THEN RAISE EXCEPTION 'Stale confirm undid cancellation';END IF;
 r:=vilqa.confirm_meal('undo-test-ok',456,123,'restore');IF COALESCE((r->>'committed')::boolean,false) THEN RAISE EXCEPTION 'Wrong user restored';END IF;
 r:=vilqa.confirm_meal('undo-test-ok',123,456,'restore');IF COALESCE((r->>'committed')::boolean,false) THEN RAISE EXCEPTION 'Wrong chat restored';END IF;
 r:=vilqa.confirm_meal('undo-test-ok',123,123,'restore');IF r->>'outcome'<>'saved' OR r->>'committed'<>'true' THEN RAISE EXCEPTION 'Explicit undo failed';END IF;
 SELECT count(*) INTO n FROM vilqa.diary WHERE draft_id='undo-test-ok';IF n<>2 THEN RAISE EXCEPTION 'Original rows not saved exactly once';END IF;
 IF (SELECT sum(calories) FROM vilqa.diary WHERE draft_id='undo-test-ok')<>618 THEN RAISE EXCEPTION 'Original calculation changed';END IF;
 r:=vilqa.confirm_meal('undo-test-ok',123,123,'restore');IF r->>'outcome'<>'already_saved' THEN RAISE EXCEPTION 'Restore replay was not idempotent';END IF;
 r:=vilqa.confirm_meal('undo-test-ok',123,123,'cancel');IF r->>'outcome'<>'already_saved' THEN RAISE EXCEPTION 'Late cancellation undid commit';END IF;
 SELECT count(*) INTO n FROM vilqa.diary WHERE draft_id='undo-test-ok';IF n<>2 THEN RAISE EXCEPTION 'Duplicate rows';END IF;
 UPDATE vilqa.diary SET deleted_at=now() WHERE draft_id='undo-test-ok';
 PERFORM vilqa.confirm_meal('undo-test-ok',123,123,'restore');IF EXISTS(SELECT 1 FROM vilqa.diary WHERE draft_id='undo-test-ok' AND deleted_at IS NULL) THEN RAISE EXCEPTION 'Draft undo resurrected deleted diary rows';END IF;
 PERFORM vilqa.confirm_meal('undo-test-expired',123,123,'cancel');
 UPDATE public.vilqa_meal_drafts SET expires_at=now()-interval '1 minute' WHERE draft_id='undo-test-expired';
 r:=vilqa.confirm_meal('undo-test-expired',123,123,'restore');IF r->>'outcome'<>'expired' THEN RAISE EXCEPTION 'Expired draft restored';END IF;
 PERFORM vilqa.confirm_meal('undo-test-bad',123,123,'cancel');
 BEGIN PERFORM vilqa.confirm_meal('undo-test-bad',123,123,'restore');RAISE EXCEPTION 'Expected malformed row rejection';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='Expected malformed row rejection' THEN RAISE;END IF;END;
 IF EXISTS(SELECT 1 FROM vilqa.diary WHERE draft_id='undo-test-bad') THEN RAISE EXCEPTION 'Partial restore committed';END IF;
 IF (SELECT status FROM public.vilqa_meal_drafts WHERE draft_id='undo-test-bad')<>'cancelled' THEN RAISE EXCEPTION 'Failed restore lost cancelled draft';END IF;
END $test$;
SELECT 'meal undo checks passed; test data rolled back' AS result;
ROLLBACK;
