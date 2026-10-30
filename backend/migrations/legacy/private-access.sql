CREATE TABLE IF NOT EXISTS vilqa.access_members(
 user_id bigint PRIMARY KEY,granted_by bigint NOT NULL,granted_at timestamptz NOT NULL DEFAULT now(),revoked_at timestamptz
);
CREATE TABLE IF NOT EXISTS vilqa.access_identities(
 user_id bigint PRIMARY KEY,username text,name text NOT NULL DEFAULT '',last_seen timestamptz NOT NULL DEFAULT now(),identity_version integer NOT NULL DEFAULT 1,last_intro_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS access_current_username ON vilqa.access_identities(lower(username)) WHERE username IS NOT NULL;
CREATE TABLE IF NOT EXISTS vilqa.access_audit(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,actor_id bigint NOT NULL,user_id bigint NOT NULL,action text NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO vilqa.access_members(user_id,granted_by) VALUES(180753266,180753266),(207093928,180753266) ON CONFLICT DO NOTHING;
-- These two numeric IDs were explicitly confirmed by the owner.
INSERT INTO vilqa.access_identities(user_id,username,name) VALUES(180753266,'kuzminru','Андрей'),(207093928,'mois_smm','Екатерина') ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION vilqa.access_check(p_user bigint) RETURNS boolean LANGUAGE sql STABLE AS $f$
 SELECT p_user=180753266 OR EXISTS(SELECT 1 FROM vilqa.access_members WHERE user_id=p_user AND revoked_at IS NULL)
$f$;

CREATE OR REPLACE FUNCTION vilqa.access_observe(p_user bigint,p_username text,p_name text,p_private boolean DEFAULT true,p_intro boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE u text:=lower(trim(leading '@' from trim(COALESCE(p_username,''))));allowed boolean;reply boolean:=false;i vilqa.access_identities%ROWTYPE;
BEGIN
 IF p_user IS NULL OR p_user<=0 OR p_private IS DISTINCT FROM true THEN RETURN jsonb_build_object('user_id',p_user,'allowed',false,'should_reply',false);END IF;
 IF u !~ '^[a-z0-9_]{5,32}$' THEN u:=NULL;END IF;
 -- Serialize username reassignment; membership itself is always bound to the numeric ID.
 PERFORM pg_advisory_xact_lock(hashtextextended('vilqa-access-identity',0));
 IF u IS NOT NULL THEN UPDATE vilqa.access_identities SET username=NULL,identity_version=identity_version+1 WHERE lower(username)=u AND user_id<>p_user;END IF;
 INSERT INTO vilqa.access_identities(user_id,username,name) VALUES(p_user,u,left(COALESCE(p_name,''),100))
 ON CONFLICT(user_id) DO UPDATE SET username=EXCLUDED.username,name=EXCLUDED.name,last_seen=now(),identity_version=vilqa.access_identities.identity_version+CASE WHEN vilqa.access_identities.username IS DISTINCT FROM EXCLUDED.username THEN 1 ELSE 0 END;
 SELECT * INTO i FROM vilqa.access_identities WHERE user_id=p_user FOR UPDATE;
 allowed:=vilqa.access_check(p_user);
 IF NOT allowed AND p_intro AND (i.last_intro_at IS NULL OR i.last_intro_at<now()-interval '15 minutes') THEN
  UPDATE vilqa.access_identities SET last_intro_at=now() WHERE user_id=p_user;reply:=true;
 END IF;
 RETURN jsonb_build_object('user_id',p_user,'allowed',allowed,'should_reply',reply);
END $f$;

CREATE OR REPLACE FUNCTION vilqa.access_manage(p_actor bigint,p_req jsonb) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE a text:=p_req->>'action';u text:=lower(trim(leading '@' from trim(COALESCE(p_req->>'username',''))));i vilqa.access_identities%ROWTYPE;uid bigint;items jsonb;changed integer;
BEGIN
 IF p_actor IS DISTINCT FROM 180753266 OR NOT COALESCE(vilqa.access_check(p_actor),false) THEN RETURN jsonb_build_object('success',false,'status',403,'message','Управлять доступом может только владелец');END IF;
 IF a='access_list' THEN
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.is_owner DESC,x.active DESC,x.last_seen DESC),'[]') INTO items FROM (
   SELECT ident.user_id,ident.username,ident.name,ident.last_seen,ident.identity_version,(ident.user_id=180753266) AS is_owner,
    (m.user_id IS NOT NULL AND m.revoked_at IS NULL) AS active,m.granted_at,m.revoked_at
   FROM vilqa.access_identities ident LEFT JOIN vilqa.access_members m USING(user_id)
   WHERE m.user_id IS NOT NULL OR ident.last_seen>now()-interval '30 days' ORDER BY ident.last_seen DESC LIMIT 200
  ) x;
  RETURN jsonb_build_object('success',true,'accounts',items);
 END IF;
 IF a IN ('access_lookup','access_grant') THEN
  IF u !~ '^[a-z0-9_]{5,32}$' THEN RETURN jsonb_build_object('success',false,'status',400,'message','Введи Telegram-ник, например @username');END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('vilqa-access-identity',0));
  SELECT * INTO i FROM vilqa.access_identities WHERE lower(username)=u AND last_seen>now()-interval '30 days' FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'status',404,'message','Бот ещё не видел этот аккаунт или сведения устарели. Попроси человека открыть @vilqa_bot и нажать «Начать», затем найди его снова.');END IF;
  IF a='access_lookup' THEN RETURN jsonb_build_object('success',true,'account',jsonb_build_object('user_id',i.user_id,'username',i.username,'name',i.name,'identity_version',i.identity_version,'active',vilqa.access_check(i.user_id),'is_owner',i.user_id=180753266));END IF;
  IF p_req->>'resolved_user_id' IS NULL OR (p_req->>'resolved_user_id')::bigint<>i.user_id OR (p_req->>'identity_version')::integer IS DISTINCT FROM i.identity_version THEN RETURN jsonb_build_object('success',false,'status',409,'message','Аккаунт изменился. Найди его по нику ещё раз.');END IF;
  INSERT INTO vilqa.access_members(user_id,granted_by) VALUES(i.user_id,p_actor) ON CONFLICT(user_id) DO UPDATE SET revoked_at=NULL,granted_by=p_actor,granted_at=CASE WHEN vilqa.access_members.revoked_at IS NOT NULL THEN now() ELSE vilqa.access_members.granted_at END WHERE vilqa.access_members.revoked_at IS NOT NULL;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed>0 THEN INSERT INTO vilqa.access_audit(actor_id,user_id,action) VALUES(p_actor,i.user_id,'grant');END IF;
  RETURN jsonb_build_object('success',true,'user_id',i.user_id,'message','Доступ открыт. Пользователь может вернуться в бот и нажать /start.');
 END IF;
 IF a='access_revoke' THEN
  uid:=(p_req->>'resolved_user_id')::bigint;
  IF uid IS NULL OR uid<=0 OR uid=180753266 THEN RETURN jsonb_build_object('success',false,'status',400,'message','Нельзя отключить доступ владельцу');END IF;
  UPDATE vilqa.access_members SET revoked_at=now() WHERE user_id=uid AND revoked_at IS NULL;GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed>0 THEN INSERT INTO vilqa.access_audit(actor_id,user_id,action) VALUES(p_actor,uid,'revoke');END IF;
  RETURN jsonb_build_object('success',true,'user_id',uid,'message','Доступ отключён. Сохранённые записи не удалены.');
 END IF;
 RETURN jsonb_build_object('success',false,'status',400,'message','Неизвестная операция доступа');
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('success',false,'status',400,'message','Некорректный аккаунт');
END $f$;

CREATE OR REPLACE FUNCTION vilqa.private_api(p_actor bigint,p_req jsonb,p_profiles jsonb DEFAULT '[]') RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE target bigint;filtered jsonb;
BEGIN
 IF NOT COALESCE(vilqa.access_check(p_actor),false) THEN RETURN jsonb_build_object('success',false,'status',403,'message','VILQA работает по приглашению. Получить доступ: @vilqa_support_bot','support_url','https://t.me/vilqa_support_bot');END IF;
 IF p_req->>'action' LIKE 'access_%' THEN RETURN vilqa.access_manage(p_actor,p_req);END IF;
 target:=COALESCE((p_req->>'user_id')::bigint,p_actor);
 IF target<>0 AND NOT COALESCE(vilqa.access_check(target),false) THEN RETURN jsonb_build_object('success',false,'status',403,'message','Доступ к этому аккаунту закрыт');END IF;
 SELECT COALESCE(jsonb_agg(p),'[]') INTO filtered FROM jsonb_array_elements(p_profiles) p WHERE vilqa.access_check((p->>'user_id')::bigint);
 RETURN vilqa.api(p_actor,p_req,filtered);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('success',false,'status',400,'message','Некорректный аккаунт');
END $f$;
