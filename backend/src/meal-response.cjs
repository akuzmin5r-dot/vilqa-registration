function prepareMeal(raw, context, executionId) {
  const escape = value => String(value).replace(/\\n/g,'\n').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  const fallback = {chat_id:context.chat_id,show_confirm_buttons:false,response_error_code:'model_output_invalid',text:'Не удалось подготовить расчёт. Напиши продукты и вес ещё раз — пока ничего не записано.'};
  let data;
  try {data = typeof raw === 'string' ? JSON.parse(raw.trim().replace(/^```(?:json)?\s*/i,'').replace(/\s*```$/,'')) : raw;} catch {
    const question=typeof raw==='string'?raw.trim():'';
    // Preserve a readable clarification, never interpret prose as a calculation or permission to write.
    if(question.length>0&&question.length<=2000&&question.includes('?')&&!/[{}\[\]]/.test(question)&&!/сохран(?:ил|ен|я)|запис(?:ал|ан|ыва)|добав(?:ил|лен).*дневник|\d\s*(?:ккал|кдж)|api.?key|token|stack.?trace/i.test(question))return {...fallback,text:escape(question),response_error_code:'model_output_recovered_question'};
    return fallback;
  }
  if (!data || typeof data !== 'object' || !Array.isArray(data.items)) return fallback;
  if (data.items.length === 0) {if(typeof data.message!=='string'||!data.message.trim())return fallback;return {chat_id:context.chat_id,show_confirm_buttons:false,text:escape(data.message.slice(0,3000))};}
  if (data.items.length > 10) return {...fallback,text:'Раздели, пожалуйста, список на части до 10 продуктов — так сможем проверить каждый.'};
  const userId = Number(context.user_id), chatId = Number(context.chat_id);
  if (!Number.isSafeInteger(userId) || userId <= 0 || !Number.isSafeInteger(chatId) || !chatId || !/^[\w-]{1,48}$/.test(String(executionId))) throw new Error('Invalid trusted meal context');
  const hour = Number(String(context.time).slice(0,2));
  const mealType = hour >= 6 && hour < 11 ? 'завтрак' : hour >= 11 && hour < 16 ? 'обед' : hour >= 16 && hour < 21 ? 'ужин' : 'перекус';
  const rows = [];
  for (const item of data.items) {
    if (!item || typeof item.item_name !== 'string' || !item.item_name.trim() || item.item_name.length > 100) return fallback;
    const row = {user_id:userId,item_name:item.item_name.trim(),item_type:item.item_type === 'recipe' ? 'recipe' : 'product',date:context.today,time:context.time,datetime:context.now,meal_type:mealType};
    for (const field of ['weight','calories','protein','fats','carbs']) {
      const value = item[field];
      if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > (field === 'calories' ? 100000 : 10000) || (field === 'weight' && value === 0)) return fallback;
      row[field] = Math.round(value*10)/10;
    }
    rows.push(row);
  }
  const totals = rows.reduce((sum,row) => {for(const field of ['calories','protein','fats','carbs'])sum[field]+=row[field];return sum;},{calories:0,protein:0,fats:0,carbs:0});
  const round = value => Math.round(value*10)/10;
  const assumptions=typeof data.message==='string'&&/предполож|примерн|около|принят|оцен|этикет|источник|https?:/i.test(data.message)?escape(data.message.slice(0,1000))+'\n\n':'';
  const text = assumptions + rows.map(row => `<b>${escape(row.item_name)}</b> · ${row.weight} г\n${Math.round(row.calories)} ккал · Б ${row.protein} · Ж ${row.fats} · У ${row.carbs}`).join('\n\n') + `\n\n<b>Итого: ${Math.round(totals.calories)} ккал</b>\nБ ${round(totals.protein)} г · Ж ${round(totals.fats)} г · У ${round(totals.carbs)} г\n\nЗаписать этот расчёт?`;
  if (text.length > 3500) return fallback;
  return {chat_id:chatId,user_id:userId,draft_id:String(executionId),show_confirm_buttons:true,text,rows};
}
function mealSourceId(userId, updateId, messageId) {
 if(!Number.isSafeInteger(Number(userId))||Number(userId)<=0)throw Error('Invalid meal source user');
 const source=updateId ?? messageId;
 if(!Number.isSafeInteger(Number(source))||Number(source)<0||source===null||source===undefined)throw Error('Missing Telegram meal source');
 return 'tg_'+userId+'_'+(updateId!=null?'u':'m')+source;
}
function prepareMealAgentResult(agent,context,executionId) {
 if(agent?.error) {
  const description=String(agent.error?.message||agent.error);
  return {chat_id:context.chat_id,show_confirm_buttons:false,response_error_code:"model_request_failed",response_error_kind:/400|bad request/i.test(description)?"provider_bad_request":/timeout|timed out/i.test(description)?"provider_timeout":"provider_error",text:"Не смогла получить ответ от AI 😕 Попробуй ещё раз немного позже. Пока ничего не записано."};
 }
 return prepareMeal(agent?.output,context,executionId);
}
module.exports={prepareMeal,mealSourceId,prepareMealAgentResult};


