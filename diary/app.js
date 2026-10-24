'use strict';
const paths={left:'<path d="m14 6-6 6 6 6"/>',right:'<path d="m10 6 6 6-6 6"/>',close:'<path d="m6 6 12 12M18 6 6 18"/>',diary:'<rect x="5" y="3" width="15" height="18" rx="3"/><path d="M8 3v18M12 8h4m-4 4h4"/>',calendar:'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4m10-4v4M3 11h18m-13 4h1m4 0h1"/>',profile:'<circle cx="12" cy="8" r="4"/><path d="M4 21v-1a8 8 0 0 1 16 0v1"/>',settings:'<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3" fill="white"/><circle cx="15" cy="17" r="3" fill="white"/>',edit:'<path d="m14 5 5 5M4 20l4-1L20 7a2 2 0 0 0-3-3L5 16Z"/>',trash:'<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7"/>',history:'<path d="M3 11a9 9 0 1 1 2 7M3 4v7h7m2-5v6l4 2"/>',restore:'<path d="M4 10a8 8 0 1 1 0 6M4 4v6h6"/>',check:'<path d="m5 12 4 4L19 6"/>',bowl:'<path d="M3 10h18c0 7-4 10-9 10S3 17 3 10Zm6-6v3m6-3v3"/>'};
const icon=name=>`<svg viewBox="0 0 24 24" aria-hidden="true">${paths[name]||paths.diary}</svg>`;
const $=selector=>document.querySelector(selector);
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmt=n=>new Intl.NumberFormat('ru-RU',{maximumFractionDigits:1}).format(Number(n)||0);
const tg=window.Telegram?.WebApp;
const local=['127.0.0.1','localhost'].includes(location.hostname);
const endpoint=local?'/__diary/api':'https://n8n.svoidigital.ru/webhook/vilqa-diary';
const state={date:'',actor:null,user:null,admin:false,adminMode:false,profile:null,entries:[],deleted:false,tab:'day',editing:null,busy:false,loadId:0};
function installIcons(root=document){root.querySelectorAll('[data-icon]').forEach(el=>{el.innerHTML=icon(el.dataset.icon);});}
function notify(text,success=false){const el=$('#message');el.textContent=text;el.classList.toggle('success',success);el.hidden=false;}
function errorMessage(error){return error?.message||'Не удалось загрузить дневник. Попробуй ещё раз.';}
async function api(data){
 if(!tg?.initData&&!local)throw new Error('Открой дневник через кнопку в @vilqa_bot');
 let last;
 for(let attempt=0;attempt<2;attempt++){
  const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),18000);
  try{
   const response=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},credentials:'omit',signal:controller.signal,body:JSON.stringify({...data,initData:tg?.initData||''})});
   const result=await response.json();
   if(!response.ok||result.success!==true){const error=new Error(result.message||'Не удалось выполнить запрос');error.status=response.status;throw error;}
   return result;
  }catch(error){last=error;if(error.status||attempt===1)break;}finally{clearTimeout(timeout);}
 }
 if(last?.name==='AbortError'||last instanceof TypeError)throw new Error('Связь прервалась. Изменение могло сохраниться — обнови дневник перед повторной правкой.');
 throw last;
}
function target(){return state.user!==null?{user_id:state.user}:{};}
function dateTitle(date){const d=new Date(date+'T12:00:00');return new Intl.DateTimeFormat('ru-RU',{day:'numeric',month:'long',weekday:'short'}).format(d);}
function progress(value,goal){return Math.min(100,Math.max(0,Number(goal)>0?value/goal*100:0));}
function entryCard(row){return `<article class="entry${row.deleted_at?' deleted':''}" data-entry="${Number(row.id)}"><div class="entry-top"><div>${row.deleted_at?'<span class="deleted-tag">Удалено</span>':''}<span class="entry-time">${esc(row.time||'')} · ${esc(row.meal_type||'Приём пищи')}</span><h3>${esc(row.item_name)}</h3></div><span class="weight">${fmt(row.weight)} г</span></div><div class="entry-values"><strong>${fmt(row.calories)} ккал</strong><span>Б ${fmt(row.protein)}</span><span>Ж ${fmt(row.fats)}</span><span>У ${fmt(row.carbs)}</span></div><div class="entry-actions">${row.deleted_at?`<button class="text-button" data-action="restore">${icon('restore')}Восстановить</button>`:`<button class="text-button" data-action="edit">${icon('edit')}Изменить</button>`}<button class="text-button" data-action="audit" aria-label="История изменений записи">${icon('history')}История</button>${row.deleted_at?'':`<button class="text-button danger" data-action="delete" aria-label="Удалить запись">${icon('trash')}</button>`}</div></article>`;}
function renderDay(data){
 const totals=data.totals||{};const p=data.profile||{};const goal=Number(p.daily_calories)||0;const remaining=goal-Number(totals.calories||0);
 const macro=(name,field)=>`<div class="macro"><label>${name}</label><strong>${fmt(totals[field])}</strong> <small>/ ${fmt(p['daily_'+field])} г</small><div class="progress-track"><span style="width:${progress(totals[field],p['daily_'+field])}%"></span></div></div>`;
 $('#dayContent').innerHTML=`<section class="summary" aria-label="Прогресс за день"><div class="summary-top"><span>Калории за день</span><span class="day-badge">${Number(totals.count)||0} записей</span></div><div class="calorie-value"><strong>${fmt(totals.calories)}</strong><span>${goal?'/ '+fmt(goal):''} ккал</span></div><p class="remaining">${goal?(remaining>=0?'Осталось '+fmt(remaining)+' ккал':'Выше ориентира на '+fmt(-remaining)+' ккал'):'Дневной ориентир пока не задан'}</p><div class="progress-track"><span style="width:${progress(totals.calories,goal)}%"></span></div></section><div class="macro-grid">${macro('Белки','protein')}${macro('Жиры','fats')}${macro('Углеводы','carbs')}</div><div class="section-heading"><h2>Записи за день</h2><span>${data.entries.filter(x=>!x.deleted_at).length} в дневнике</span></div>${data.entries.length?data.entries.map(entryCard).join(''):`<div class="empty">${icon('bowl')}<h3>Здесь пока пусто</h3><p>Добавь еду текстом или голосом в чате с VILQA</p><a href="https://t.me/vilqa_bot">Перейти в бот</a></div>`}<label class="deleted-toggle"><input type="checkbox" id="showDeleted" ${state.deleted?'checked':''}>Показать удалённые записи</label>`;
 $('#showDeleted').addEventListener('change',e=>{state.deleted=e.target.checked;loadDay();});
}
async function loadDay(){
 const id=++state.loadId;$('#dayContent').setAttribute('aria-busy','true');
 try{
  const result=await api({action:'day',...(state.date?{date:state.date}:{}),...target(),include_deleted:state.deleted});if(id!==state.loadId)return;
  state.actor=result.actor_id;state.user=result.user_id;state.date=result.date;state.admin=result.is_admin;state.profile=result.profile||{};state.entries=result.entries||[];
  $('#dateInput').value=state.date;$('#dateLabel').textContent=dateTitle(state.date);$('#adminTab').hidden=!state.admin;renderDay(result);
 }catch(error){if(id!==state.loadId)return;notify(errorMessage(error));$('#dayContent').innerHTML='<div class="empty"><h3>Дневник недоступен</h3><p>Проверь соединение и открой приложение заново</p><button class="text-button" id="retryLoad">Повторить загрузку</button></div>';$('#retryLoad').addEventListener('click',loadDay);}finally{if(id===state.loadId)$('#dayContent').removeAttribute('aria-busy');}
}
function changeDay(offset){if(state.busy)return;const d=new Date(state.date+'T12:00:00');d.setDate(d.getDate()+offset);state.date=[d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-');loadDay();}
async function showTab(tab){
 if(state.busy)return;state.tab=tab;state.adminMode=tab==='admin';
 if(!state.adminMode&&state.actor&&state.user!==state.actor){state.user=state.actor;await loadDay();}
 $('#dayView').hidden=!['day','admin'].includes(tab);$('#historyView').hidden=tab!=='history';$('#profileView').hidden=tab!=='profile';$('#adminBar').hidden=!state.adminMode;
 $('#pageTitle').textContent=({day:'Дневник питания',history:'История питания',profile:'Профиль',admin:'Админка'})[tab];
 document.querySelectorAll('[data-tab]').forEach(el=>el.classList.toggle('active',el.dataset.tab===tab));
 try{
  if(tab==='admin'){
   if(!state.admin)throw new Error('Нет доступа к админке');const result=await api({action:'users'});
   $('#userSelect').innerHTML=result.users.map(u=>`<option value="${Number(u.user_id)}">${esc(u.name||u.username||u.user_id)}${u.username?' · @'+esc(u.username):''}</option>`).join('');$('#userSelect').value=String(state.user);
  }else if(tab==='history'){
   $('#historyDays').innerHTML='<div class="skeleton"></div>';const result=await api({action:'history',date:state.date,...target()});
   $('#historyDays').innerHTML=result.days.length?result.days.map(day=>`<button class="day-row" data-date="${esc(day.date)}"><span><strong>${esc(dateTitle(day.date))}</strong><small>${Number(day.count)} записей · Б ${fmt(day.protein)} · Ж ${fmt(day.fats)} · У ${fmt(day.carbs)}</small></span><span><b>${fmt(day.calories)}</b><small>ккал</small></span></button>`).join(''):'<div class="empty"><h3>История ещё впереди</h3><p>Записи за последние 30 дней появятся здесь</p></div>';
  }else if(tab==='profile'){
   const p=state.profile;const line=(label,value)=>`<div class="profile-line"><span>${label}</span><strong>${esc(value??'—')}</strong></div>`;
   $('#profileContent').innerHTML=`<div class="profile-card"><h2>${esc(p.name||'Профиль питания')}</h2>${line('Цель',p.goal_ru)}${line('Возраст',p.age?fmt(p.age)+' лет':null)}${line('Рост',p.height?fmt(p.height)+' см':null)}${line('Вес',p.weight?fmt(p.weight)+' кг':null)}${line('Калории',p.daily_calories?fmt(p.daily_calories)+' ккал':null)}${line('Часовой пояс',p.timezone)}<p class="profile-note">Параметры и цель можно изменить через повторную регистрацию в боте.</p></div>`;
  }
 }catch(error){notify(errorMessage(error));}
}
function openEdit(row){
 state.editing={...row};const form=$('#editForm');for(const field of ['item_name','weight','calories','protein','fats','carbs'])form.elements[field].value=row[field];$('#autoScale').checked=true;$('#editError').hidden=true;$('#editDialog').showModal();
}
function ask(title,text,label){return new Promise(resolve=>{const dialog=$('#confirmDialog');$('#confirmTitle').textContent=title;$('#confirmText').textContent=text;$('#acceptConfirm').textContent=label;let accepted=false;const close=()=>{dialog.removeEventListener('close',close);resolve(accepted);};dialog.addEventListener('close',close);$('#acceptConfirm').onclick=()=>{accepted=true;dialog.close();};$('#cancelConfirm').onclick=()=>dialog.close();dialog.showModal();});}
async function mutate(action,row,extra={}){
 if(state.busy)return null;state.busy=true;document.querySelectorAll('button').forEach(el=>el.disabled=true);
 try{return await api({action,id:row.id,version:row.version,user_id:row.user_id,request_id:crypto.randomUUID(),...extra});}
 finally{state.busy=false;document.querySelectorAll('button').forEach(el=>el.disabled=false);}
}
async function destructive(action,row){
 const restore=action==='restore';if(!await ask(restore?'Восстановить запись?':'Удалить запись?',restore?'Запись снова появится в дневнике и войдёт в итог дня.':'Она исчезнет из итогов, но останется в истории. Удаление можно отменить.',restore?'Восстановить':'Удалить'))return;
 try{await mutate(action,row);await loadDay();notify(restore?'Запись восстановлена':'Запись удалена. Её можно восстановить.',true);}catch(error){notify(errorMessage(error));await loadDay();}
}
async function openAudit(row){
 $('#auditContent').innerHTML='<div class="skeleton"></div>';$('#auditDialog').showModal();
 try{const result=await api({action:'audit',id:row.id,user_id:row.user_id});const labels={import:'Исходная запись',create:'Добавлено из бота',edit:'Исправлено',delete:'Удалено',restore:'Восстановлено',revert:'Возвращена прежняя версия'};
  $('#auditContent').innerHTML=result.events.length?result.events.map(event=>`<article class="audit-event"><h3>${esc(labels[event.action]||event.action)}</h3><small>${esc(new Date(event.created_at).toLocaleString('ru-RU'))} · ${event.actor_id===state.actor?'вы':'пользователь '+event.actor_id}</small>${event.before_data?`<div class="audit-values">До: ${esc(event.before_data.item_name)} · ${fmt(event.before_data.weight)} г · ${fmt(event.before_data.calories)} ккал<br>Б ${fmt(event.before_data.protein)} · Ж ${fmt(event.before_data.fats)} · У ${fmt(event.before_data.carbs)}</div>`:''}${event.after_data?`<div class="audit-values">После: ${esc(event.after_data.item_name)} · ${fmt(event.after_data.weight)} г · ${fmt(event.after_data.calories)} ккал</div>`:''}${event.before_data&&!row.deleted_at&&['edit','revert'].includes(event.action)?`<button class="text-button" data-revert="${Number(event.id)}" data-entry-id="${Number(row.id)}">${icon('restore')}Вернуть значения «до»</button>`:''}</article>`).join(''):'<p class="profile-note">Изменений пока нет. Исходная запись сохранена.</p>';
 }catch(error){$('#auditContent').textContent=errorMessage(error);}
}
$('#editWeight').addEventListener('input',()=>{if(!$('#autoScale').checked||!state.editing)return;const weight=Number($('#editWeight').value);if(!Number.isFinite(weight)||weight<=0)return;for(const field of ['calories','protein','fats','carbs'])$('#editForm').elements[field].value=Math.round(state.editing[field]*weight/state.editing.weight*10)/10;});
for(const field of ['calories','protein','fats','carbs'])$('#editForm').elements[field].addEventListener('input',()=>{$('#autoScale').checked=false;});
$('#editForm').addEventListener('submit',async event=>{event.preventDefault();if(state.busy)return;const form=event.currentTarget;const patch={item_name:form.elements.item_name.value.trim()};for(const field of ['weight','calories','protein','fats','carbs'])patch[field]=Number(form.elements[field].value);$('#editError').hidden=true;try{await mutate('edit',state.editing,{patch});$('#editDialog').close();await loadDay();notify('Изменения сохранены',true);}catch(error){$('#editError').textContent=errorMessage(error);$('#editError').hidden=false;}});
$('#dayContent').addEventListener('click',event=>{const button=event.target.closest('[data-action]');if(!button||state.busy)return;const row=state.entries.find(r=>r.id===Number(button.closest('[data-entry]').dataset.entry));if(!row)return;if(button.dataset.action==='edit')openEdit(row);else if(button.dataset.action==='audit')openAudit(row);else destructive(button.dataset.action,row);});
$('#auditContent').addEventListener('click',async event=>{const button=event.target.closest('[data-revert]');if(!button)return;const row=state.entries.find(r=>r.id===Number(button.dataset.entryId));if(!row)return;$('#auditDialog').close();if(!await ask('Вернуть прежние значения?','Текущие значения тоже сохранятся в истории.','Вернуть'))return;try{await mutate('revert',row,{audit_id:Number(button.dataset.revert)});await loadDay();notify('Прежние значения восстановлены',true);}catch(error){notify(errorMessage(error));await loadDay();}});
$('#historyDays').addEventListener('click',event=>{const el=event.target.closest('[data-date]');if(!el)return;state.date=el.dataset.date;showTab('day');loadDay();});
$('#prevDay').addEventListener('click',()=>changeDay(-1));$('#nextDay').addEventListener('click',()=>changeDay(1));$('#dateInput').addEventListener('change',event=>{if(event.target.value){state.date=event.target.value;loadDay();}});
$('#userSelect').addEventListener('change',event=>{state.user=Number(event.target.value);if(state.user===0)notify('Старые записи без владельца и даты показаны все вместе. Они не входят в дневники пользователей.');loadDay();});
document.querySelectorAll('[data-tab]').forEach(el=>el.addEventListener('click',()=>showTab(el.dataset.tab)));
document.querySelectorAll('.close-dialog').forEach(el=>el.addEventListener('click',()=>{if(!state.busy)el.closest('dialog').close();}));
document.querySelectorAll('dialog').forEach(el=>el.addEventListener('cancel',event=>{if(state.busy)event.preventDefault();}));
installIcons();tg?.ready();tg?.expand();if(local)$('#demoNote').hidden=false;loadDay();
