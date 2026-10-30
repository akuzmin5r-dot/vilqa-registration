CREATE TABLE IF NOT EXISTS vilqa.profile_notifications (
 user_id bigint NOT NULL,
 profile_version integer NOT NULL,
 actor_id bigint NOT NULL,
 message_text text NOT NULL,
 status text NOT NULL DEFAULT 'claimed' CHECK (status IN ('claimed','sent','failed')),
 telegram_message_id bigint,
 created_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 PRIMARY KEY (user_id,profile_version)
);
