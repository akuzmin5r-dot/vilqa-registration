CREATE TABLE IF NOT EXISTS public.vilqa_meal_drafts (
  draft_id text PRIMARY KEY,
  user_id bigint NOT NULL,
  chat_id bigint NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','saving','saved','cancelled','uncertain')),
  claim_execution text,
  saved_row_ids jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '24 hours',
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS vilqa_meal_drafts_user_status ON public.vilqa_meal_drafts(user_id, status);
