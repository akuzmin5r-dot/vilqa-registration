WITH claimed AS (
UPDATE public.vilqa_meal_drafts SET status=CASE WHEN $4='confirm' THEN 'saving' ELSE 'cancelled' END,
claim_execution=$5,updated_at=now()
WHERE draft_id=$1 AND user_id=$2::bigint AND chat_id=$3::bigint AND status='pending' AND expires_at>now() AND $4 IN ('confirm','cancel')
RETURNING draft_id,payload,status)
SELECT draft_id,payload,status,($4='confirm') AS should_write,
CASE WHEN $4='cancel' THEN 'Расчёт отменён. Ничего не записано.' ELSE '' END AS feedback FROM claimed
UNION ALL SELECT $1,NULL,NULL,false,'Эта кнопка уже обработана или устарела. Если запись ещё обрабатывается, подожди. Для нового расчёта отправь продукты снова.' WHERE NOT EXISTS(SELECT 1 FROM claimed);
