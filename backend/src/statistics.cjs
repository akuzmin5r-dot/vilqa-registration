// Deterministic presentation of a database snapshot. No model-generated totals.
function statisticsArticle(data, now = new Date()) {
  const escape = value => String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const number = (value, integer = false) => new Intl.NumberFormat('ru-RU', {maximumFractionDigits:integer ? 0 : 1}).format(Number(value) || 0);
  const chatId = data.chat_id || data.user_id;
  if (!chatId) throw new Error('Statistics recipient is missing');
  const zone = data.timezone || 'Europe/Moscow';
  const date = data.date || new Intl.DateTimeFormat('en-CA', {timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).format(now);
  const dateLabel = new Intl.DateTimeFormat('ru-RU', {day:'numeric',month:'long',timeZone:'UTC'}).format(new Date(date + 'T12:00:00Z'));
  const s = data.stats;
  const logs = [...(data.logs || [])].sort((a,b)=>String(a.time || '').localeCompare(String(b.time || '')) || Number(a.id)-Number(b.id));
  const known = logs.filter(row=>row.fiber !== null && row.fiber !== undefined && Number.isFinite(Number(row.fiber)) && Number(row.fiber)>=0 && ['estimated','manual','known','verified'].includes(row.fiber_status));
  const pending = logs.some(row=>['pending','processing'].includes(row.fiber_status));
  const partial = known.length < logs.length;
  const fiberTotal = known.reduce((sum,row)=>sum+Number(row.fiber),0);
  const fiberTarget = Number(data.dailyFiber) > 0 ? Number(data.dailyFiber) : 25;
  const fiberValue = pending ? 'Считаю…' : partial ? (known.length ? '≈ '+number(fiberTotal)+' г · неполные данные' : 'Данные неполные') : '≈ '+number(fiberTotal)+' г';
  const diff = Math.round(s.dailyCalories)-Math.round(s.totalCalories);
  const balance = diff>=0 ? 'Осталось '+number(diff,true)+' ккал' : 'Выше ориентира на '+number(-diff,true)+' ккал';
  const rows = [['💪 Белки',number(s.totalProtein)+' г',number(s.dailyProtein)+' г'],['🥑 Жиры',number(s.totalFats)+' г',number(s.dailyFats)+' г'],['🍞 Углеводы',number(s.totalCarbs)+' г',number(s.dailyCarbs)+' г'],['🌾 Клетчатка',fiberValue,number(fiberTarget)+' г']];
  let html = '<h1>📊 Питание · '+escape(dateLabel)+'</h1>';
  const totals = '<h2>🎯 Итого за день</h2><p>🔥 <b>'+number(s.totalCalories,true)+' из '+number(s.dailyCalories,true)+' ккал</b><br>'+balance+'</p><table compact><tr><th>Показатель</th><th>За день</th><th>Ориентир</th></tr>'+rows.map(row=>'<tr>'+row.map(cell=>'<td>'+escape(cell)+'</td>').join('')+'</tr>').join('')+'</table>';
  const groups = new Map();
  for (const row of logs) {
    const key = row.draft_id || row.time || String(row.id);
    if (!groups.has(key)) groups.set(key,[]);
    groups.get(key).push(row);
  }
  if (!logs.length) html += '<p>Пока ничего не записано. Напиши, что съел — текстом или голосом.</p>';
  else {
    let content='', shown=0;
    for (const group of groups.values()) {
      const heading = '<h3>🕒 '+escape(String(group[0].time || '').slice(0,5))+(group[0].meal_type ? ' · '+escape(group[0].meal_type) : '')+'</h3>';
      let items='';
      for (const row of group) {
        const item='<p><b>'+escape(row.item_name)+'</b> · '+number(row.weight)+' г<br>'+number(row.calories,true)+' ккал · Б '+number(row.protein)+' г · Ж '+number(row.fats)+' г · У '+number(row.carbs)+' г</p>';
        if (shown>=140 || html.length+content.length+heading.length+items.length+item.length+totals.length>27000) break;
        items+=item; shown++;
      }
      if (items) content+=heading+'<blockquote>'+items+'</blockquote>';
      if (shown>=140 || (shown<logs.length && html.length+content.length+totals.length>26000)) break;
    }
    html+='<h2>🍽 Приёмы пищи · '+groups.size+'</h2>'+content;
    if (shown<logs.length) html+='<p>Все записи доступны в дневнике.</p>';
  }
  html+=totals+'<footer>🌾 Клетчатка — приблизительная оценка.'+(pending ? ' Итог придёт отдельным сообщением.' : '')+'</footer>';
  const text='Питание · '+dateLabel+'\n'+number(s.totalCalories,true)+' из '+number(s.dailyCalories,true)+' ккал\n'+balance+'\n'+rows.map(row=>row[0]+': '+row[1]+' / '+row[2]).join('\n')+'\n'+logs.map(row=>escape(row.item_name)+' · '+number(row.weight)+' г · '+number(row.calories,true)+' ккал').join('\n');
  return {chat_id:chatId,date,text,rich_html:html,fiber_pending:pending,show_buttons:true};
}
module.exports = {statisticsArticle};
