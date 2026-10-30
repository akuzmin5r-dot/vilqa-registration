WITH persisted AS (INSERT INTO public.vilqa_meal_drafts AS d(draft_id,user_id,chat_id,payload)
VALUES ($1,$2::bigint,$3::bigint,$4::jsonb)
ON CONFLICT(draft_id) DO UPDATE SET draft_id=EXCLUDED.draft_id
WHERE d.user_id=EXCLUDED.user_id AND d.chat_id=EXCLUDED.chat_id AND d.status='pending' AND d.expires_at>now()
RETURNING draft_id,chat_id::double precision AS chat_id,payload->>'text' AS text) SELECT * FROM persisted;
