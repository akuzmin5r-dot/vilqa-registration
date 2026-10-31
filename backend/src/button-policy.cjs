// Only positive write actions and opening the diary are green. Cancel is red.
function telegramButtonStyle(text='',action='') {
 text=String(text);action=String(action).replace(/^n:\d+:/,'');
 if(/^(meal_cancel|recipe_cancel)(:|$)/.test(action)||/отмен/i.test(text))return 'danger';
 if(action==='menu_food_entry'||/^[^а-яёa-z]*записать\s+еду[^а-яёa-z]*$/i.test(text))return '';
 if(/^(meal_confirm|meal_restore|recipe_save|recipe_pause)(:|$)/.test(action)||/сохран|записать/i.test(text))return 'success';
 if(/открыть\s+дневник|^[^а-яёa-z]*дневник[^а-яёa-z]*$/i.test(text))return 'success';
 return '';
}
function expression(value){return typeof value==='string'&&value.startsWith('={{')?value.slice(3,-2).trim():JSON.stringify(value||'');}
function applyButtonPolicy(node) {
 let changed=false;
 for(const row of node.parameters.inlineKeyboard?.rows||[])for(const b of row.row.buttons||[]){
  const f=b.additionalFields||={},text=b.text||'',action=f.callback_data||'';
  const dynamic=[text,action].some(v=>typeof v==='string'&&v.startsWith('={{'));
  const style=dynamic?'={{ ('+telegramButtonStyle.toString()+')('+expression(text)+','+expression(action)+') }}':telegramButtonStyle(text,action);
  if(f.style!==style){b.additionalFields={...f,style};changed=true;}
 }
 return changed;
}
module.exports={telegramButtonStyle,applyButtonPolicy};
