BEGIN;
DO $t$
DECLARE u bigint:=180753266;r jsonb;o jsonb;v bigint;p jsonb;f jsonb;
BEGIN
 DELETE FROM vilqa.nav_messages WHERE user_id=u;DELETE FROM vilqa.nav_operations WHERE user_id=u;DELETE FROM vilqa.nav_state_events WHERE user_id=u;DELETE FROM vilqa.nav_events WHERE user_id=u;DELETE FROM vilqa.nav_sessions WHERE user_id=u;
 p:='{"kind":"text","screen":"main","text":"menu","keyboard":[{"row":{"buttons":[{"text":"Food","additionalFields":{"callback_data":"menu_food_entry"}},{"text":"Stats","additionalFields":{"callback_data":"menu_stats"}}]}}]}';
 f:='{"kind":"text","screen":"food","text":"food","keyboard":[{"row":{"buttons":[{"text":"Back","additionalFields":{"callback_data":"menu_main"}}]}}]}';
 r:=vilqa.fast_interface(u,-1,false,'1900000700','','0','/menu','Test','kuzminru',p,f,'test');IF r->>'route'<>'ignore' THEN RAISE EXCEPTION 'Group chat allowed';END IF;
 r:=vilqa.fast_interface(u,99,true,'1900000700','','0','/menu','Test','kuzminru',p,f,'test');IF r->>'route'<>'ignore' THEN RAISE EXCEPTION 'Wrong chat allowed';END IF;
 r:=vilqa.fast_interface(99999999,99999999,true,'1900000700','','0','/menu','Test','unknown',p,f,'test');IF r->>'route'<>'legacy' THEN RAISE EXCEPTION 'Invitation path lost';END IF;
 r:=vilqa.fast_interface(u,u,true,'1900000700','','0','/recipes','Test','kuzminru',p,f,'test');IF r->>'route'<>'legacy' THEN RAISE EXCEPTION 'Other commands changed';END IF;
 r:=vilqa.fast_interface(u,u,true,'1900000700','','0','/menu','Test','kuzminru',p,f,'test');IF r->>'route'<>'deliver' OR r->'op'->>'id' IS NULL THEN RAISE EXCEPTION 'Menu not queued';END IF;
 o:=r->'op';IF o->>'executor_id'<>'test' THEN RAISE EXCEPTION 'Executor not tracked';END IF;
 PERFORM vilqa.nav_finish((o->>'id')::bigint,900001);v:=(o->>'revision')::bigint;
 r:=vilqa.fast_interface(u,u,true,'1900000700','','0','/menu','Test','kuzminru',p,f,'test');IF r->'event'->>'reason'<>'duplicate' THEN RAISE EXCEPTION 'Update duplicate allowed';END IF;
 r:=vilqa.fast_interface(u,u,true,'1900000701','n:'||v||':menu_food_entry',900002,'','Test','kuzminru',p,f,'test');IF r->'event'->>'reason'<>'stale' THEN RAISE EXCEPTION 'Wrong message accepted';END IF;
 r:=vilqa.fast_interface(u,u,true,'1900000702','n:'||v||':menu_food_entry',900001,'','Test','kuzminru',p,f,'test');IF r->>'route'<>'deliver' OR r->'op'->'payload'->>'screen'<>'food' THEN RAISE EXCEPTION 'Food not queued';END IF;
 o:=r->'op';PERFORM vilqa.nav_finish((o->>'id')::bigint,900003);
 r:=vilqa.fast_interface(u,u,true,'1900000703','','0','/menu','Test','kuzminru',p,f,'test');o:=r->'op';PERFORM vilqa.nav_finish((o->>'id')::bigint,900004);v:=(o->>'revision')::bigint;
 r:=vilqa.fast_interface(u,u,true,'1900000704','n:'||v||':menu_stats',900004,'','Test','kuzminru',p,f,'test');IF r->>'route'<>'stats' OR (r->>'user_id')::bigint<>u OR r->>'timezone' IS NULL THEN RAISE EXCEPTION 'Stats context not resolved';END IF;
 r:=vilqa.fast_interface(u,u,true,'1900000704','n:'||v||':menu_stats',900004,'','Test','kuzminru',p,f,'test');IF r->'event'->>'reason'<>'duplicate' THEN RAISE EXCEPTION 'Stats duplicate allowed';END IF;
 DELETE FROM vilqa.profiles WHERE user_id=u;
 r:=vilqa.fast_interface(u,u,true,'1900000705','','0','/menu','Test','kuzminru',p,f,'test');IF r->>'route'<>'legacy' OR EXISTS(SELECT 1 FROM vilqa.nav_events WHERE user_id=u AND event_key='1900000705') THEN RAISE EXCEPTION 'Missing profile fallback consumed update';END IF;
END $t$;
SELECT 'Fast interface: access, registration fallback, stale controls, dedup, menu, food and stats passed; rolled back' AS result;
ROLLBACK;
