BEGIN;
CREATE TABLE IF NOT EXISTS vilqa.meal_notifications(
 entry_id bigint PRIMARY KEY REFERENCES vilqa.diary(id),user_id bigint NOT NULL,message_text text NOT NULL,
 status text NOT NULL DEFAULT 'claimed' CHECK(status IN ('claimed','sent','failed','unknown')),
 telegram_message_id bigint,created_at timestamptz NOT NULL DEFAULT now(),completed_at timestamptz
);
COMMIT;
