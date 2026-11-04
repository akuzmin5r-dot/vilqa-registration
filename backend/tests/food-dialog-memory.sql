BEGIN;
DO $test$
DECLARE sid text:='log:test_memory_'||txid_current();raw_count integer;safe_count integer;r jsonb;
BEGIN
 INSERT INTO public.n8n_chat_histories(session_id,message) VALUES
 (sid,'{"type":"tool","content":"orphaned lookup","tool_call_id":"lost"}'),
 (sid,'{"type":"ai","content":[],"tool_calls":[{"id":"call1"}]}'),
 (sid,'{"type":"human","content":"Хлеб 17 г"}'),
 (sid,'{"type":"ai","content":"Уточни сорт?","additional_kwargs":{"tool_calls":[{"id":"hidden"}]}}');
 SELECT count(*) INTO raw_count FROM public.n8n_chat_histories WHERE session_id=sid;
 SELECT count(*) INTO safe_count FROM public.vilqa_food_dialog_memory WHERE session_id=sid;
 IF raw_count<>4 OR safe_count<>2 THEN RAISE EXCEPTION 'Wrong projection counts %, %',raw_count,safe_count;END IF;
 SELECT message INTO r FROM public.vilqa_food_dialog_memory WHERE session_id=sid ORDER BY id DESC LIMIT 1;
 IF r->>'content'<>'Уточни сорт?' OR r->'additional_kwargs'<>'{}'::jsonb OR r ? 'tool_calls' THEN RAISE EXCEPTION 'Unsafe dialog message %',r;END IF;
 INSERT INTO public.vilqa_food_dialog_memory(session_id,message) VALUES(sid,'{"type":"human","content":"Проверка записи через view"}');
 IF (SELECT count(*) FROM public.n8n_chat_histories WHERE session_id=sid)<>5 THEN RAISE EXCEPTION 'Write-through failed';END IF;
 IF (SELECT count(*) FROM public.vilqa_food_dialog_memory WHERE session_id=sid)<>3 THEN RAISE EXCEPTION 'Read after write failed';END IF;
 IF EXISTS(SELECT 1 FROM public.vilqa_food_dialog_memory WHERE session_id='log:207093928' AND (message->>'type' NOT IN ('human','ai') OR message ? 'tool_calls')) THEN RAISE EXCEPTION 'Unsafe real-user replay';END IF;
END;
$test$;
ROLLBACK;
SELECT true AS food_memory_tests_passed;
