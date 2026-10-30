BEGIN;PREPARE vilqa_test_persist(text,bigint,bigint,jsonb) AS WITH persisted AS (INSERT INTO public.vilqa_meal_drafts AS d(draft_id,user_id,chat_id,payload)
VALUES ($1,$2::bigint,$3::bigint,$4::jsonb)
ON CONFLICT(draft_id) DO UPDATE SET draft_id=EXCLUDED.draft_id
WHERE d.user_id=EXCLUDED.user_id AND d.chat_id=EXCLUDED.chat_id AND d.status='pending' AND d.expires_at>now()
RETURNING draft_id,chat_id::double precision AS chat_id,payload->>'text' AS text) SELECT * FROM persisted;

EXECUTE vilqa_test_persist('maint-persist-a',9000000000000123,9000000000000123,'{"text":"original","rows":[]}');
EXECUTE vilqa_test_persist('maint-persist-a',9000000000000123,9000000000000123,'{"text":"changed","rows":[]}');
EXECUTE vilqa_test_persist('maint-persist-b',9000000000000123,9000000000000123,'{"text":"original","rows":[]}');
DO $t$ BEGIN IF (SELECT count(*) FROM public.vilqa_meal_drafts WHERE draft_id IN ('maint-persist-a','maint-persist-b'))<>2 THEN RAISE EXCEPTION 'Source identity dedup failed';END IF;IF (SELECT payload->>'text' FROM public.vilqa_meal_drafts WHERE draft_id='maint-persist-a')<>'original' THEN RAISE EXCEPTION 'Retry changed original payload';END IF;END $t$;
UPDATE public.vilqa_meal_drafts SET status='saved' WHERE draft_id='maint-persist-a';
EXECUTE vilqa_test_persist('maint-persist-a',9000000000000123,9000000000000123,'{"text":"resurrected","rows":[]}');
DO $t$ BEGIN IF (SELECT status FROM public.vilqa_meal_drafts WHERE draft_id='maint-persist-a')<>'saved' THEN RAISE EXCEPTION 'Saved draft reset';END IF; END $t$;
DEALLOCATE vilqa_test_persist;SELECT 'Immutable source draft checks passed' AS result;ROLLBACK;
