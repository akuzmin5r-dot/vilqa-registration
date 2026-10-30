// One-time, idempotent migration of the exported workflow configurations.
const fs=require('node:fs'),path=require('node:path');
const base=path.resolve(__dirname,'../workflows');
for(const kind of ['stats','main','api']) {
 const file=path.join(base,kind+'.json'),w=JSON.parse(fs.readFileSync(file,'utf8'));
 for(const n of w.nodes) {
  if(kind==='stats'&&n.name==='🧮 Calculate Stats'&&!n.parameters.jsCode.includes('dailyFiber:'))n.parameters.jsCode=n.parameters.jsCode.replace('logs: logs,','logs: logs,\n    dailyFiber: userProfile.daily_fiber || 25,');
  if(kind==='stats'&&n.name==='Read Today Diary')n.parameters.query=n.parameters.query.replace('carbs,created_at','carbs,fiber,fiber_status,draft_id,created_at');
  if(kind==='stats'&&n.name==='Resolve Stats Profile')n.parameters.query="SELECT vilqa.ensure_profile($1::jsonb) || jsonb_build_object('daily_fiber',COALESCE((SELECT daily_target FROM vilqa.fiber_settings WHERE user_id=($1::jsonb->>'user_id')::bigint),25)) AS profile;";
  if(kind==='stats'&&n.name==='Статистика — прочитать единый снимок')n.parameters.query=n.parameters.query.replace("data->'snapshot' AS snapshot", "jsonb_set(data->'snapshot','{profile,daily_fiber}',to_jsonb(COALESCE((SELECT daily_target FROM vilqa.fiber_settings WHERE user_id=$1::bigint),25)),true) AS snapshot");
  if(kind==='main'&&n.name==='Подготовить ответ статистики')n.parameters={mode:'raw',jsonOutput:'={{ {...$json,today_stats:$json.text} }}',options:{}};
  if((kind==='main'&&n.name==='📤 Send Stats')||(kind==='api'&&n.name==='Статистика порции · отправить')) {
   const p=n.parameters;
   n.parameters={resource:'message',operation:'sendRichMessage',chatId:p.chatId,richFormat:'html',richMessageText:'={{ $json.rich_html }}',replyMarkup:p.replyMarkup,inlineKeyboard:p.inlineKeyboard,additionalFields:{}};
   for(const row of n.parameters.inlineKeyboard.rows)for(const b of row.row.buttons) {
    if(b.additionalFields.web_app)b.additionalFields.style='primary';
    else if(b.additionalFields.callback_data==='menu_recommendation')b.additionalFields.style='success';
   }
  }
 }
 fs.writeFileSync(file,JSON.stringify(w,null,2));
}
require('./generate-workflows.cjs').run();
