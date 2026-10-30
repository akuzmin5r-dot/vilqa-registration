BEGIN;
DO $test$
DECLARE r jsonb;v integer;uid bigint:=987654321001;other bigint:=987654321002;
BEGIN
 IF NOT vilqa.access_check(180753266) OR NOT vilqa.access_check(207093928) THEN RAISE EXCEPTION 'Owner or confirmed spouse locked out';END IF;
 IF vilqa.access_check(uid) THEN RAISE EXCEPTION 'Unknown member admitted';END IF;
 r:=vilqa.access_observe(uid,'vqa_test_user','<img onerror=alert(1)>',true,true);
 IF (r->>'allowed')::boolean OR NOT (r->>'should_reply')::boolean THEN RAISE EXCEPTION 'Unknown intro gate failed';END IF;
 r:=vilqa.access_observe(uid,'vqa_test_user','Name',true,true);IF (r->>'should_reply')::boolean THEN RAISE EXCEPTION 'Intro flood throttle failed';END IF;
 r:=vilqa.access_manage(207093928,'{"action":"access_list"}');IF r->>'status'<>'403' THEN RAISE EXCEPTION 'Non-owner management allowed';END IF;
 r:=vilqa.access_manage(180753266,'{"action":"access_list"}');IF r->>'success'<>'true' OR jsonb_typeof(r->'accounts')<>'array' THEN RAISE EXCEPTION 'Owner access list failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'accounts') account WHERE (account->>'user_id')::bigint=180753266 AND (account->>'is_owner')::boolean AND (account->>'active')::boolean) THEN RAISE EXCEPTION 'Owner missing in access list';END IF;
 r:=vilqa.private_api(180753266,'{"action":"access_list"}');IF r->>'success'<>'true' THEN RAISE EXCEPTION 'Owner list via real API function failed';END IF;
 r:=vilqa.access_manage(180753266,'{"action":"access_lookup","username":"@VQA_TEST_USER"}');IF (r->'account'->>'user_id')::bigint<>uid THEN RAISE EXCEPTION 'Lookup failed';END IF;v:=(r->'account'->>'identity_version')::integer;
 r:=vilqa.access_manage(180753266,jsonb_build_object('action','access_grant','username','vqa_test_user','resolved_user_id',other,'identity_version',v));IF r->>'status'<>'409' THEN RAISE EXCEPTION 'Identity mismatch accepted';END IF;
 r:=vilqa.access_manage(180753266,jsonb_build_object('action','access_grant','username','vqa_test_user','resolved_user_id',uid,'identity_version',v));IF r->>'success'<>'true' OR NOT vilqa.access_check(uid) THEN RAISE EXCEPTION 'Grant failed';END IF;
 r:=vilqa.access_observe(uid,'vqa_changed_name','Name',true,false);IF NOT (r->>'allowed')::boolean THEN RAISE EXCEPTION 'Username rename broke membership';END IF;
 r:=vilqa.access_observe(other,'vqa_test_user','Other',true,false);IF (r->>'allowed')::boolean THEN RAISE EXCEPTION 'Username reuse inherited membership';END IF;
 r:=vilqa.access_manage(180753266,jsonb_build_object('action','access_grant','username','vqa_test_user','resolved_user_id',uid,'identity_version',v));IF r->>'status'<>'409' THEN RAISE EXCEPTION 'Stale lookup accepted';END IF;
 r:=vilqa.access_manage(180753266,jsonb_build_object('action','access_revoke','resolved_user_id',uid));IF r->>'success'<>'true' OR vilqa.access_check(uid) THEN RAISE EXCEPTION 'Revoke failed';END IF;
 r:=vilqa.access_manage(180753266,'{"action":"access_revoke","resolved_user_id":180753266}');IF r->>'status'<>'400' OR NOT vilqa.access_check(180753266) THEN RAISE EXCEPTION 'Owner revoke protection failed';END IF;
 r:=vilqa.private_api(uid,'{"action":"day"}');IF r->>'status'<>'403' THEN RAISE EXCEPTION 'API bypassed access gate';END IF;
 r:=vilqa.private_api(180753266,jsonb_build_object('action','profile','user_id',uid));IF r->>'status'<>'403' THEN RAISE EXCEPTION 'Revoked target exposed';END IF;
 r:=vilqa.access_manage(180753266,'{"action":"access_lookup","username":"never_seen_vqa_user"}');IF r->>'status'<>'404' THEN RAISE EXCEPTION 'Unknown identity guessed';END IF;
 r:=vilqa.access_observe(other,'vqa_test_user','Name',false,true);IF (r->>'allowed')::boolean OR (r->>'should_reply')::boolean THEN RAISE EXCEPTION 'Group context admitted';END IF;
 r:=vilqa.private_api(180753266,'{"action":"day","user_id":"invalid"}');IF r->>'status'<>'400' THEN RAISE EXCEPTION 'Bad target not rejected cleanly';END IF;
END $test$;
ROLLBACK;
SELECT true AS passed,21 AS checks;
