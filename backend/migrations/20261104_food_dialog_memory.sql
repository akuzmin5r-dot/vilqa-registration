BEGIN;
-- Keep the original append-only transcript, including tool traces, intact.
-- Replay only conversational messages: a sliding window can never orphan a tool call.
CREATE OR REPLACE FUNCTION vilqa.food_dialog_message(p jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $fn$
 SELECT CASE WHEN p->>'type' IN ('human','ai')
   AND jsonb_typeof(p->'content')='string'
   AND length(btrim(p->>'content'))>0
   AND CASE WHEN jsonb_typeof(p->'tool_calls')='array' THEN jsonb_array_length(p->'tool_calls')=0 ELSE true END
 THEN jsonb_build_object('type',p->>'type','content',p->'content','additional_kwargs','{}'::jsonb,'response_metadata','{}'::jsonb)
 ELSE NULL END;
$fn$;

CREATE OR REPLACE VIEW public.vilqa_food_dialog_memory AS
 SELECT id,session_id,vilqa.food_dialog_message(message) AS message
 FROM public.n8n_chat_histories
 WHERE session_id LIKE 'log:%' AND vilqa.food_dialog_message(message) IS NOT NULL;

CREATE OR REPLACE FUNCTION vilqa.append_food_dialog_memory() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
 IF NEW.session_id NOT LIKE 'log:%' THEN RAISE EXCEPTION 'Invalid food memory session';END IF;
 INSERT INTO public.n8n_chat_histories(session_id,message)
 VALUES(NEW.session_id,NEW.message) RETURNING id INTO NEW.id;
 RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS append_food_dialog_memory ON public.vilqa_food_dialog_memory;
CREATE TRIGGER append_food_dialog_memory INSTEAD OF INSERT ON public.vilqa_food_dialog_memory
 FOR EACH ROW EXECUTE FUNCTION vilqa.append_food_dialog_memory();
COMMIT;
