BEGIN;
DO $t$
DECLARE test_entry bigint;owner_id bigint:=8000000000000050;affected integer;
BEGIN
 INSERT INTO vilqa.diary(user_id,item_type,item_name,weight,calories,protein,fats,carbs) VALUES(owner_id,'recipe','TEMP NOTICE TEST',250,200,15,7.5,17.5) RETURNING vilqa.diary.id INTO test_entry;
 INSERT INTO vilqa.meal_notifications(entry_id,user_id,message_text) SELECT test_entry,owner_id,'TEST' WHERE EXISTS(SELECT 1 FROM vilqa.diary d WHERE d.id=test_entry AND user_id=owner_id AND deleted_at IS NULL AND item_type='recipe') ON CONFLICT(entry_id) DO NOTHING;
 INSERT INTO vilqa.meal_notifications(entry_id,user_id,message_text) SELECT test_entry,owner_id,'TEST REPLAY' WHERE EXISTS(SELECT 1 FROM vilqa.diary d WHERE d.id=test_entry AND user_id=owner_id AND deleted_at IS NULL AND item_type='recipe') ON CONFLICT(entry_id) DO NOTHING;
 IF (SELECT count(*) FROM vilqa.meal_notifications n WHERE n.entry_id=test_entry)<>1 OR (SELECT message_text FROM vilqa.meal_notifications n WHERE n.entry_id=test_entry)<>'TEST' THEN RAISE EXCEPTION 'Notification replay duplicated or overwritten';END IF;
 UPDATE vilqa.meal_notifications SET status='sent',telegram_message_id=12345,completed_at=now() WHERE entry_id=test_entry AND user_id=owner_id;
 IF (SELECT status FROM vilqa.meal_notifications n WHERE n.entry_id=test_entry)<>'sent' THEN RAISE EXCEPTION 'Notification status not recorded';END IF;
 DELETE FROM vilqa.meal_notifications n WHERE n.entry_id=test_entry;
 INSERT INTO vilqa.meal_notifications(entry_id,user_id,message_text) SELECT test_entry,owner_id+1,'FOREIGN' WHERE EXISTS(SELECT 1 FROM vilqa.diary d WHERE d.id=test_entry AND user_id=owner_id+1 AND deleted_at IS NULL AND item_type='recipe') ON CONFLICT(entry_id) DO NOTHING;
 GET DIAGNOSTICS affected=ROW_COUNT;IF affected<>0 THEN RAISE EXCEPTION 'Foreign notification claimed';END IF;
 UPDATE vilqa.diary d SET deleted_at=now() WHERE d.id=test_entry;
 INSERT INTO vilqa.meal_notifications(entry_id,user_id,message_text) SELECT test_entry,owner_id,'DELETED' WHERE EXISTS(SELECT 1 FROM vilqa.diary d WHERE d.id=test_entry AND user_id=owner_id AND deleted_at IS NULL AND item_type='recipe') ON CONFLICT(entry_id) DO NOTHING;
 GET DIAGNOSTICS affected=ROW_COUNT;IF affected<>0 THEN RAISE EXCEPTION 'Deleted meal notification claimed';END IF;
END $t$;
ROLLBACK;
SELECT to_regclass('vilqa.meal_notifications')::text AS installed,'Notice claim, replay, ownership and deletion checks passed' AS result;
