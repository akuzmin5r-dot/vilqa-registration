function telegramChunks(raw, limit = 3500) {
  const escape = value => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const text = String(raw ?? '').replace(/<br\s*\/?\s*>/gi, '\n').replace(/<\/?(?:p|div)>/gi, '\n').replace(/<\/?span[^>]*>/gi, '');
  const tokens = text.match(/<\/?(?:b|i|code|blockquote)>|&(?:amp|lt|gt|quot|apos|#\d+|#x[\da-f]+);|[\s\S]/giu) || [];
  const stack = [], chunks = [];
  const close = () => stack.slice().reverse().map(tag => '</' + tag + '>').join('');
  const open = () => stack.map(tag => '<' + tag + '>').join('');
  let current = '', hasText = false;
  const flush = () => { if (hasText) chunks.push(current + close()); current = open(); hasText = false; };
  for (let token of tokens) {
    const tag = token.match(/^<(\/?)(b|i|code|blockquote)>$/i);
    if (tag) {
      const name = tag[2].toLowerCase();
      if (tag[1]) {
        if (stack[stack.length - 1] !== name) continue;
        current += '</' + stack.pop() + '>';
      } else if (stack.length < 8) {
        if (current.length + token.length + close().length + name.length + 3 > limit) flush();
        current += '<' + name + '>'; stack.push(name);
      }
      continue;
    }
    if (token === '&' || token === '<' || token === '>') token = escape(token);
    if (current.length + token.length + close().length > limit) flush();
    current += token; hasText = true;
  }
  flush();
  return chunks.length ? chunks : ['Сообщение пустое. Попробуйте ещё раз.'];
}

function escapeHTML(s){return String(s??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function recipeScreen(row) {
 let d={};try{d=JSON.parse(row.state_data||'{}').recipe_draft||{};}catch{}
 const button=(text,callback_data)=>({row:{buttons:[{text,additionalFields:{callback_data}}]}});
 const rows=[];let text;
 if(row.existing_draft){text='Уже есть сохранённый черновик. Продолжить его или удалить перед созданием нового?';rows.push(button('📝 Продолжить','recipe_continue'),button('🗑 Удалить черновик','recipe_delete_draft'));}
 else if(row.current_state==='recipe_naming')text='📖 <b>Новый рецепт</b>\n\nКак назовём блюдо?';
 else if(row.current_state==='recipe_weight')text='Сколько весит готовое блюдо?\n\nНапиши вес в граммах.';
 else if(row.current_state==='recipe_ai_processing')text='Рецепт ждёт уточнения. Напиши, что нужно исправить или дополнить.';
 else if(row.current_state==='recipe_ingredients'){
  text='📖 <b>'+escapeHTML(d.recipe_name||'Рецепт')+'</b>\n\nДобавляй ингредиенты текстом или голосом.';
  if((d.ingredients_raw||[]).length)rows.push(button('✅ Ингредиенты добавлены','recipe_ready'));
 }else {text='Черновик сохранён. Можно продолжить позже.';if(d.recipe_name!==undefined)rows.push(button('📝 Продолжить','recipe_continue'));}
 if(row.current_state)rows.push(button('⏸ Сохранить и выйти','recipe_pause'));
 rows.push(button('📖 К рецептам','menu_recipes'),button('⬅️ Главное меню','menu_main'));
 return {kind:'text',screen:row.current_state||'recipe_paused',text,keyboard:rows};
}
function mealCard(update, result, feedback) {
  const q=update?.callback_query,m=q?.message;
  if (!m || m.chat?.type !== 'private' || m.chat.id !== q.from?.id || m.from?.id !== 8294670391 || m.from?.is_bot !== true || !Number.isSafeInteger(m.message_id) || m.message_id <= 0 || typeof m.text !== 'string') return null;
  if (!/^meal_(confirm|cancel|restore):[\w-]{1,48}$/.test(q.data || '')) return null;
  const outcome = result?.outcome;
  if (!['saved','already_saved','cancelled'].includes(outcome)) return null;
  const escape = s => String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  const body=m.text.replace(/\n\nЗаписать этот расчёт\?\s*$/, '').replace(/\n\n(?:✅ Добавлено в дневник|❌ Расчёт отменён)[\s\S]*$/, '').replace(/^(?:❌\s*)?Расчёт отменён\. Ничего не записано\.\s*$/, '');
  return {chat_id:m.chat.id,message_id:m.message_id,is_text:true,text:(body?escape(body)+'\n\n':'')+(outcome==='cancelled'?'❌ Расчёт отменён. Ничего не записано.':'✅ Добавлено в дневник'),saved:outcome!=='cancelled',draft_id:result?.draft_id||q.data.split(':')[1],can_restore:outcome==='cancelled'&&result?.can_restore===true};
}
module.exports={telegramChunks,recipeScreen,escapeHTML,mealCard};
