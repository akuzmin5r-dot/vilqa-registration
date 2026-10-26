'use strict';
const paths={plus:'<path d="M12 5v14M5 12h14"/>',recipes:'<path d="M4 4h6a3 3 0 0 1 2 2 3 3 0 0 1 2-2h6v16h-6a3 3 0 0 0-2 2 3 3 0 0 0-2-2H4ZM12 6v16M7 8h2m6 0h2M7 12h2m6 0h2"/>',left:'<path d="m14 6-6 6 6 6"/>',right:'<path d="m10 6 6 6-6 6"/>',close:'<path d="m6 6 12 12M18 6 6 18"/>',diary:'<rect x="5" y="3" width="15" height="18" rx="3"/><path d="M8 3v18M12 8h4m-4 4h4"/>',calendar:'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4m10-4v4M3 11h18m-13 4h1m4 0h1"/>',profile:'<circle cx="12" cy="8" r="4"/><path d="M4 21v-1a8 8 0 0 1 16 0v1"/>',settings:'<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3" fill="white"/><circle cx="15" cy="17" r="3" fill="white"/>',edit:'<path d="m14 5 5 5M4 20l4-1L20 7a2 2 0 0 0-3-3L5 16Z"/>',trash:'<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7"/>',history:'<path d="M3 11a9 9 0 1 1 2 7M3 4v7h7m2-5v6l4 2"/>',restore:'<path d="M4 10a8 8 0 1 1 0 6M4 4v6h6"/>',check:'<path d="m5 12 4 4L19 6"/>',bowl:'<path d="M3 10h18c0 7-4 10-9 10S3 17 3 10Zm6-6v3m6-3v3"/>'};
const icon=name=>`<svg viewBox="0 0 24 24" aria-hidden="true">${paths[name]||paths.diary}</svg>`;
const $=selector=>document.querySelector(selector);
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const kcal=n=>new Intl.NumberFormat('ru-RU',{maximumFractionDigits:0}).format(Number(n)||0);
const fmt=n=>new Intl.NumberFormat('ru-RU',{maximumFractionDigits:1}).format(Number(n)||0);
const telegram=()=>window.Telegram?.WebApp;
const initialData=()=>telegram()?.initData||new URLSearchParams(location.hash.slice(1)).get('tgWebAppData')||'';
const local=['127.0.0.1','localhost'].includes(location.hostname);
const endpoint=local?'/__diary/api':'https://n8n.svoidigital.ru/webhook/vilqa-diary';
const launchParams=new URLSearchParams(location.search);
const launchDate=launchParams.get('date')||'';
const validLaunchDate=/^\d{4}-\d{2}-\d{2}$/.test(launchDate)&&!Number.isNaN(Date.parse(launchDate+'T12:00:00'))&&new Date(launchDate+'T12:00:00Z').toISOString().slice(0,10)===launchDate;
const state={date:validLaunchDate?launchDate:'',actor:null,user:null,admin:false,adminMode:false,profile:null,entries:[],deleted:launchParams.get('deleted')==='1',focusEntry:Number(launchParams.get('entry'))||null,tab:'day',editing:null,busy:false,loadId:0};
function installIcons(root=document){root.querySelectorAll('[data-icon]').forEach(el=>{el.innerHTML=icon(el.dataset.icon);});}
let noticeTimer=null;
function dismissNotice(){clearTimeout(noticeTimer);noticeTimer=null;const el=$('#message');el.hidden=true;el.textContent='';el.classList.remove('success');}
function notify(text,success=false){dismissNotice();const el=$('#message');el.textContent=text;el.classList.toggle('success',success);el.hidden=false;if(success)noticeTimer=setTimeout(dismissNotice,4000);}
function errorMessage(error){return error?.message||'Не удалось загрузить дневник. Попробуй ещё раз.';}
async function waitForTelegram(){
 if(local||initialData()||telegram())return;
 await new Promise(resolve=>{const script=$('#telegramSdk');let timer;const done=()=>{clearTimeout(timer);script?.removeEventListener('load',done);script?.removeEventListener('error',done);resolve();};script?.addEventListener('load',done,{once:true});script?.addEventListener('error',done,{once:true});timer=setTimeout(done,8000);});
}
async function api(data,options={}){
 if(window.VILQA_DEMO)return window.VILQA_DEMO.request(data);
 await waitForTelegram();
 if(!initialData()&&!local)throw new Error('Открой дневник через кнопку в @vilqa_bot');
 let last;
 for(let attempt=0;attempt<2;attempt++){
  if(options.signal?.aborted)throw new DOMException('Cancelled','AbortError');
  const controller=new AbortController();const abort=()=>controller.abort();options.signal?.addEventListener('abort',abort,{once:true});const timeout=setTimeout(abort,options.timeout||12000);
  try{
   const response=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},credentials:'omit',signal:controller.signal,body:JSON.stringify({...data,initData:initialData()})});
   const result=await response.json();
   if(!response.ok||result.success!==true){const error=new Error(result.message||'Не удалось выполнить запрос');error.status=response.status;throw error;}
   return result;
  }catch(error){if(options.signal?.aborted)throw new DOMException('Cancelled','AbortError');last=error;if(error.status||attempt===1)break;}finally{clearTimeout(timeout);options.signal?.removeEventListener('abort',abort);}
 }
 if(last?.name==='AbortError'||last instanceof TypeError)throw new Error(['edit','delete','restore','revert','profile_edit','recipe_delete','recipe_add','recipe_start','access_grant','access_revoke'].includes(data.action)?'Связь прервалась. Изменение могло сохраниться — обнови дневник перед повторной правкой.':'Не удалось загрузить данные. Проверь соединение и попробуй ещё раз.');
 throw last;
}
function russianCount(value,forms){const n=Math.max(0,Number(value)||0),a=n%100,b=n%10;return n+' '+forms[a>=11&&a<=14?2:b===1?0:b>=2&&b<=4?1:2];}
const entryCount=n=>russianCount(n,['запись','записи','записей']);
function timezoneLabel(zone){return zone==='Europe/Moscow'?'Москва · UTC+3':zone||'—';}
function target(){return state.user!==null?{user_id:state.user}:{};}
function dateTitle(date){const d=new Date(date+'T12:00:00');return new Intl.DateTimeFormat('ru-RU',{day:'numeric',month:'long',weekday:'short'}).format(d);}
function progress(value,goal){return Math.min(100,Math.max(0,Number(goal)>0?value/goal*100:0));}
function entryCard(row){return `<article class="entry${row.deleted_at?' deleted':''}" data-entry="${Number(row.id)}"><div class="entry-top"><div>${row.deleted_at?'<span class="deleted-tag">Удалено</span>':''}<span class="entry-time">${esc(row.time||'')} · ${esc(row.meal_type||'Приём пищи')}</span><h3>${esc(row.item_name)}</h3></div><span class="weight">${fmt(row.weight)} г</span></div><div class="entry-values"><strong>${kcal(row.calories)} ккал</strong><span>Б ${fmt(row.protein)}</span><span>Ж ${fmt(row.fats)}</span><span>У ${fmt(row.carbs)}</span></div><div class="entry-actions">${row.deleted_at?`<button class="text-button" data-action="restore">${icon('restore')}Восстановить</button>`:`<button class="text-button" data-action="edit">${icon('edit')}Изменить</button>`}<button class="text-button" data-action="audit" aria-label="История изменений записи">${icon('history')}История</button>${row.deleted_at?'':`<button class="text-button danger" data-action="delete" aria-label="Удалить запись">${icon('trash')}</button>`}</div></article>`;}
function renderDay(data){
 const totals=data.totals||{};const p=data.profile||{};const goal=Number(p.daily_calories)||0;const remaining=goal-Number(totals.calories||0);
 const macro=(name,field)=>`<div class="macro"><label>${name}</label><strong>${fmt(totals[field])}</strong> <small>/ ${fmt(p['daily_'+field])} г</small><div class="progress-track"><span style="width:${progress(totals[field],p['daily_'+field])}%"></span></div></div>`;
 $('#dayContent').innerHTML=`<div class="nutrition-dashboard"><section class="summary" aria-label="Прогресс за день"><div class="summary-top"><span class="calorie-label"><svg class="calorie-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3c1 4-3 5-3 8 0 1 .5 2 1.5 2.5C9 9 14 8 14 6c3 3 5 6 5 9a7 7 0 0 1-14 0c0-3 2-6 4-8-1 3 0 4 0 4"/></svg><span>Калории за день</span></span><span class="day-badge">${entryCount(totals.count)}</span></div><div class="calorie-value"><strong>${kcal(totals.calories)}</strong><span>${goal?'/ '+kcal(goal):''} ккал</span></div><p class="remaining">${goal?(remaining>=0?'Осталось '+kcal(remaining)+' ккал':'Выше ориентира на '+kcal(-remaining)+' ккал'):'Дневной ориентир пока не задан'}</p><div class="progress-track"><span style="width:${progress(totals.calories,goal)}%"></span></div></section><div class="macro-grid">${macro('Белки','protein')}${macro('Жиры','fats')}${macro('Углеводы','carbs')}</div></div><div class="section-heading"><h2>Записи за день</h2><span>${data.entries.filter(x=>!x.deleted_at).length} в дневнике</span></div><button type="button" class="recipe-day-add" id="openRecipesForDiary">${icon('recipes')}<span>Добавить из рецептов</span>${icon('right')}</button>${data.entries.length?data.entries.map(entryCard).join(''):`<div class="empty">${icon('bowl')}<h3>Здесь пока пусто</h3><p>Добавь еду текстом или голосом в чате с VILQA</p><a href="https://t.me/vilqa_bot">Перейти в бот</a></div>`}<label class="deleted-toggle"><input type="checkbox" id="showDeleted" ${state.deleted?'checked':''}>Показать удалённые записи</label>`;
 $('#showDeleted').addEventListener('change',e=>{state.deleted=e.target.checked;loadDay();});$('#openRecipesForDiary').addEventListener('click',()=>showTab('recipes'));
}
const dayCache=new Map();let cacheEpoch=0,foregroundRead=null,prefetchRead=null,prefetchTimer=null;
function dayKey(user,date,deleted){return String(user)+'|'+date+'|'+Boolean(deleted);}
function cachedDay(user,date,deleted){const value=dayCache.get(dayKey(user,date,deleted));return value&&Date.now()-value.at<30000?value.data:null;}
function rememberDay(data,deleted,epoch){if(epoch!==cacheEpoch)return;dayCache.set(dayKey(data.user_id,data.date,deleted),{data,at:Date.now()});while(dayCache.size>20)dayCache.delete(dayCache.keys().next().value);}
function invalidateDays(){cacheEpoch++;dayCache.clear();prefetchRead?.abort();clearTimeout(prefetchTimer);}
function offsetDate(date,offset){const d=new Date(date+'T12:00:00');d.setDate(d.getDate()+offset);return [d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-');}
function syncDateLabel(){if(!state.date)return;$('#dateInput').value=state.date;$('#dateLabel').textContent=dateTitle(state.date);}
function prefetchDays(data){
 clearTimeout(prefetchTimer);prefetchRead?.abort();const epoch=cacheEpoch,deleted=state.deleted;
 prefetchTimer=setTimeout(()=>{if(state.busy||state.tab==='history'||document.hidden)return;const controller=new AbortController();prefetchRead=controller;
  for(const offset of [-1,1]){const date=offsetDate(data.date,offset);if(cachedDay(data.user_id,date,deleted))continue;
   api({action:'day',date,user_id:data.user_id,include_deleted:deleted},{signal:controller.signal,timeout:8000}).then(result=>rememberDay(result,deleted,epoch)).catch(()=>{});
  }
 },250);
}
function acceptDay(result,id,epoch,deleted){
 if(id!==state.loadId||epoch!==cacheEpoch)return;
 state.actor=result.actor_id;state.user=result.user_id;state.date=result.date;state.admin=result.is_admin;state.profile=result.profile||{};state.entries=result.entries||[];
 syncDateLabel();$('#adminTab').hidden=!state.admin;rememberDay(result,deleted,epoch);renderDay(result);
 if(state.focusEntry){const selected=$('[data-entry="'+state.focusEntry+'"]');if(selected){state.focusEntry=null;selected.classList.add('entry-link-target');requestAnimationFrame(()=>selected.scrollIntoView({block:'center',behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'}));}}
 const content=$('#dayContent');content.classList.remove('day-enter');void content.offsetWidth;content.classList.add('day-enter');prefetchDays(result);
}
async function loadDay(options={}){
 const id=++state.loadId,epoch=cacheEpoch,deleted=state.deleted;foregroundRead?.abort();prefetchRead?.abort();clearTimeout(prefetchTimer);syncDateLabel();
 const content=$('#dayContent'),dateBar=$('.date-bar');const cached=!options.force&&state.date?cachedDay(state.user,state.date,deleted):null;
 if(cached){acceptDay(cached,id,epoch,deleted);content.removeAttribute('aria-busy');dateBar.classList.remove('is-loading');return;}
 state.entries=[];content.setAttribute('aria-busy','true');dateBar.classList.add('is-loading');
 if(state.actor){content.innerHTML='<div class="day-loading" role="status"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 12a8 8 0 1 1-8-8"/></svg><span>Загружаем записи за выбранный день</span></div><div class="skeleton"></div><div class="skeleton small"></div>';}
 const controller=new AbortController();foregroundRead=controller;
 try{
  if(options.debounce){await new Promise(resolve=>setTimeout(resolve,100));if(id!==state.loadId)return;}
  const result=await api({action:'day',...(state.date?{date:state.date}:{}),...target(),include_deleted:deleted},{signal:controller.signal});
  acceptDay(result,id,epoch,deleted);
 }catch(error){if(id!==state.loadId||error.name==='AbortError')return;notify(errorMessage(error));if(error.status===403){content.innerHTML='<div class="empty"><h3>Доступ по приглашению</h3><p>Чтобы пользоваться VILQA, напиши в поддержку</p><a href="https://t.me/vilqa_support_bot" target="_blank" rel="noopener noreferrer">Получить доступ</a></div>';}else{content.innerHTML='<div class="empty"><h3>Не удалось загрузить день</h3><p>Проверь соединение и попробуй ещё раз</p><button class="text-button" id="retryLoad">Повторить загрузку</button></div>';$('#retryLoad').addEventListener('click',()=>loadDay({force:true}));}}
 finally{if(id===state.loadId){content.removeAttribute('aria-busy');dateBar.classList.remove('is-loading');$('#initialLoader').hidden=true;document.body.classList.remove('booting');$('#dayView').hidden=!['day','admin'].includes(state.tab);}}
}
function changeDay(offset){
 if(state.busy||!state.date)return;dismissNotice();state.date=offsetDate(state.date,offset);const button=$(offset<0?'#prevDay':'#nextDay');
 if(!matchMedia('(prefers-reduced-motion: reduce)').matches)button.animate?.([{transform:'translateX(0) scale(1)'},{transform:'translateX('+(offset*4)+'px) scale(.92)'},{transform:'translateX(0) scale(1)'}],{duration:190,easing:'ease-out'});
 loadDay({debounce:true});
}
function historyEndDate(){
 const parts=new Intl.DateTimeFormat('en-CA',{timeZone:state.profile?.timezone||'Europe/Moscow',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());
 const value=key=>parts.find(p=>p.type===key).value;return value('year')+'-'+value('month')+'-'+value('day');
}
let historyPlotDays=[];
function historyChart(days,end){
 const byDate=new Map(days.map(d=>[d.date,d]));historyPlotDays=Array.from({length:30},(_,i)=>{const date=offsetDate(end,i-29),r=byDate.get(date);return {date,has:Number(r?.count)>0,calories:Number(r?.calories)||0};});
 const recorded=historyPlotDays.filter(d=>d.has),total=recorded.reduce((s,d)=>s+d.calories,0),ceiling=Math.ceil(Math.max(1,...recorded.map(d=>d.calories))/500)*500;
 const short=d=>d.slice(8)+'.'+d.slice(5,7),selected=29;
 const bars=historyPlotDays.map((d,i)=>{const h=d.has?Math.max(2,d.calories/ceiling*112):2;return '<rect data-history-bar="'+i+'" class="'+(d.has?'':'missing ')+(i===selected?'selected':'')+'" x="'+(35+i*9)+'" y="'+(150-h)+'" width="6" height="'+h+'" rx="3"><title>'+short(d.date)+': '+(d.has?kcal(d.calories)+' ккал':'нет записей')+'</title></rect>';}).join('');
 return '<div class="history-summary-grid"><div class="chart-stat"><span>Калории за 30 дней</span><strong>'+kcal(total)+' <small>ккал</small></strong><small>'+russianCount(recorded.length,['день','дня','дней'])+' с записями</small></div><div class="chart-stat"><span>Среднее за день с записями</span><strong>'+(recorded.length?kcal(Math.round(total/recorded.length)):'—')+' <small>ккал</small></strong><small>По заполненным дням</small></div></div><section class="history-chart" aria-label="График калорий за 30 дней"><div class="history-plot-heading"><h3>Калории по дням</h3><span>30 дней</span></div><div class="history-interaction"><svg class="history-plot" viewBox="0 0 312 182" role="img" aria-label="'+esc('Калории по дням. Нажми на столбец или используй клавиши со стрелками.')+'"><text x="0" y="24">'+kcal(ceiling)+'</text><path d="M33 38H306M33 94H306M33 150H306" stroke="#bdcda9" stroke-opacity=".65" fill="none"/>'+bars+'<text x="35" y="176">'+short(historyPlotDays[0].date)+'</text><text x="170" y="176" text-anchor="middle">'+short(historyPlotDays[15].date)+'</text><text x="303" y="176" text-anchor="end">'+short(end)+'</text></svg><input id="historyRange" class="chart-range" type="range" min="0" max="29" value="29" step="1" aria-label="Выбрать день на графике"></div><p class="chart-gesture-hint">Нажми на столбец или проведи по графику</p><div class="history-selected" id="historySelected" aria-live="polite"></div></section>';
}
function selectHistoryDay(index){
 const i=Math.max(0,Math.min(29,Number(index)||0)),day=historyPlotDays[i];if(!day)return;
 const slider=$('#historyRange');if(!slider)return;slider.value=i;slider.setAttribute('aria-valuetext',dateTitle(day.date)+': '+(day.has?kcal(day.calories)+' ккал':'нет записей'));
 $('#historySelected').innerHTML='<span>'+esc(dateTitle(day.date))+'</span><strong>'+(day.has?kcal(day.calories)+' ккал':'Нет записей')+'</strong>';
 document.querySelectorAll('[data-history-bar]').forEach(el=>el.classList.toggle('selected',Number(el.dataset.historyBar)===i));
}
async function showTab(tab){
 if(state.busy)return;dismissNotice();state.tab=tab;state.adminMode=['admin','admin-profile','admin-access'].includes(tab);
 if(!state.adminMode&&state.actor&&state.user!==state.actor){state.user=state.actor;await loadDay();}
 $('#dayView').hidden=!['day','admin'].includes(tab);$('#historyView').hidden=tab!=='history';$('#profileView').hidden=!['profile','admin-profile'].includes(tab);$('#recipesView').hidden=tab!=='recipes';$('#adminBar').hidden=!state.adminMode||tab==='admin-access';$('#adminNavigation').hidden=!state.adminMode;$('#adminAccessView').hidden=tab!=='admin-access';document.querySelectorAll('[data-admin-tab]').forEach(el=>{const active=el.dataset.adminTab===tab;el.classList.toggle('active',active);el.setAttribute('aria-current',active?'page':'false');});
 $('#pageTitle').textContent=({day:'Дневник питания',history:'История питания',profile:'Профиль',recipes:'Рецепты',admin:'Админка','admin-profile':'Профиль пользователя','admin-access':'Доступ к боту'})[tab];
 document.querySelectorAll('[data-tab]').forEach(el=>{const active=el.dataset.tab===(['admin-profile','admin-access'].includes(tab)?'admin':tab);el.classList.toggle('active',active);el.setAttribute('aria-current',active?'page':'false');});
 try{
  if(tab==='admin'){
   if(!state.admin)throw new Error('Нет доступа к админке');const result=await api({action:'users'});
   $('#userSelect').innerHTML=result.users.map(u=>`<option value="${Number(u.user_id)}">${esc(u.name||u.username||u.user_id)}${u.username?' · @'+esc(u.username):''}</option>`).join('');$('#userSelect').value=String(state.user);
  }else if(tab==='admin-access'){
   if(!state.admin)throw new Error('Нет доступа к админке');await loadAccessAccounts();
  }else if(tab==='history'){
   $('#historyDays').innerHTML='<div class="skeleton"></div>';const end=historyEndDate();const result=await api({action:'history',date:end,...target()});if(state.tab!=='history')return;
   $('#historyDays').innerHTML=historyChart(result.days,end)+(result.days.length?result.days.map(day=>`<button class="day-row" data-date="${esc(day.date)}"><span><strong>${esc(dateTitle(day.date))}</strong><small>${entryCount(day.count)} · Б ${fmt(day.protein)} · Ж ${fmt(day.fats)} · У ${fmt(day.carbs)}</small></span><span><b>${kcal(day.calories)}</b><small>ккал</small></span></button>`).join(''):'<div class="empty"><h3>История ещё впереди</h3><p>Записи за последние 30 дней появятся здесь</p></div>');selectHistoryDay(29);
  }else if(tab==='recipes'){await loadRecipes();
  }else if(['profile','admin-profile'].includes(tab)){
   await renderProfile();
  }
 }catch(error){notify(errorMessage(error));}
}
function openEdit(row){
 state.editing={...row};const form=$('#editForm');for(const field of ['item_name','weight','calories','protein','fats','carbs'])form.elements[field].value=field==='calories'?Math.round(Number(row[field])):row[field];form.elements.date.value=row.date||'';form.elements.time.value=(row.time||'').slice(0,5);$('#autoScale').checked=true;$('#editError').hidden=true;$('#editDialog').showModal();
}
function ask(title,text,label,options={}){return new Promise(resolve=>{const dialog=$('#confirmDialog');$('#confirmTitle').textContent=title;$('#confirmText').textContent=text;$('#acceptConfirm').textContent=label;$('#acceptConfirm').classList.toggle('danger-primary',options.danger===true);let accepted=false;const close=()=>{dialog.removeEventListener('close',close);resolve(accepted);};dialog.addEventListener('close',close);$('#acceptConfirm').onclick=()=>{accepted=true;dialog.close();};$('#cancelConfirm').onclick=()=>dialog.close();dialog.showModal();});}
async function mutate(action,row,extra={}){
 if(state.busy)return null;invalidateDays();state.busy=true;document.querySelectorAll('button').forEach(el=>el.disabled=true);
 try{return await api({action,id:row.id,version:row.version,user_id:row.user_id,request_id:crypto.randomUUID(),...extra});}
 finally{invalidateDays();state.busy=false;document.querySelectorAll('button').forEach(el=>el.disabled=false);}
}
async function destructive(action,row){
 const restore=action==='restore';if(!await ask(restore?'Восстановить запись?':'Удалить запись?',restore?'Запись снова появится в дневнике и войдёт в итог дня.':'Она исчезнет из итогов, но останется в истории. Удаление можно отменить.',restore?'Восстановить':'Удалить',{danger:!restore}))return;
 try{await mutate(action,row);await loadDay();notify(restore?'Запись восстановлена':'Запись удалена. Её можно восстановить.',true);}catch(error){notify(errorMessage(error));await loadDay();}
}
async function openAudit(row){
 $('#auditContent').innerHTML='<div class="skeleton"></div>';$('#auditDialog').showModal();
 try{const result=await api({action:'audit',id:row.id,user_id:row.user_id});const labels={import:'Исходная запись',create:'Добавлено из бота',edit:'Исправлено',delete:'Удалено',restore:'Восстановлено',revert:'Возвращена прежняя версия'};
  $('#auditContent').innerHTML=result.events.length?result.events.map(event=>`<article class="audit-event"><h3>${esc(labels[event.action]||event.action)}</h3><small>${esc(new Date(event.created_at).toLocaleString('ru-RU'))} · ${event.actor_id===state.actor?'вы':'пользователь '+event.actor_id}</small>${event.before_data?`<div class="audit-values">До: ${esc(event.before_data.date||"Дата не указана")} ${esc(event.before_data.time||"")}<br>${esc(event.before_data.item_name)} · ${fmt(event.before_data.weight)} г · ${kcal(event.before_data.calories)} ккал<br>Б ${fmt(event.before_data.protein)} · Ж ${fmt(event.before_data.fats)} · У ${fmt(event.before_data.carbs)}</div>`:''}${event.after_data?`<div class="audit-values">После: ${esc(event.after_data.date||"Дата не указана")} ${esc(event.after_data.time||"")}<br>${esc(event.after_data.item_name)} · ${fmt(event.after_data.weight)} г · ${kcal(event.after_data.calories)} ккал</div>`:''}${event.before_data&&!row.deleted_at&&['edit','revert'].includes(event.action)?`<button class="text-button" data-revert="${Number(event.id)}" data-entry-id="${Number(row.id)}">${icon('restore')}Вернуть значения «до»</button>`:''}</article>`).join(''):'<p class="profile-note">Изменений пока нет. Исходная запись сохранена.</p>';
 }catch(error){$('#auditContent').textContent=errorMessage(error);}
}
$('#editWeight').addEventListener('input',()=>{if(!$('#autoScale').checked||!state.editing)return;const weight=Number($('#editWeight').value);if(!Number.isFinite(weight)||weight<=0)return;for(const field of ['calories','protein','fats','carbs'])$('#editForm').elements[field].value=field==='calories'?Math.round(state.editing[field]*weight/state.editing.weight):Math.round(state.editing[field]*weight/state.editing.weight*10)/10;});
for(const field of ['calories','protein','fats','carbs'])$('#editForm').elements[field].addEventListener('input',()=>{$('#autoScale').checked=false;});
$('#editForm').addEventListener('submit',async event=>{event.preventDefault();if(state.busy)return;const form=event.currentTarget;const patch={item_name:form.elements.item_name.value.trim(),date:form.elements.date.value,time:form.elements.time.value};for(const field of ['weight','calories','protein','fats','carbs'])patch[field]=Number(form.elements[field].value);$('#editError').hidden=true;try{const result=await mutate('edit',state.editing,{patch});state.date=result.entry.date;$('#editDialog').close();await loadDay();notify('Изменения сохранены',true);}catch(error){$('#editError').textContent=errorMessage(error);$('#editError').hidden=false;}});
$('#dayContent').addEventListener('click',event=>{const button=event.target.closest('[data-action]');if(!button||state.busy)return;const row=state.entries.find(r=>r.id===Number(button.closest('[data-entry]').dataset.entry));if(!row)return;if(button.dataset.action==='edit')openEdit(row);else if(button.dataset.action==='audit')openAudit(row);else destructive(button.dataset.action,row);});
$('#auditContent').addEventListener('click',async event=>{const button=event.target.closest('[data-revert]');if(!button)return;const row=state.entries.find(r=>r.id===Number(button.dataset.entryId));if(!row)return;$('#auditDialog').close();if(!await ask('Вернуть прежние значения?','Текущие значения тоже сохранятся в истории.','Вернуть'))return;try{const result=await mutate('revert',row,{audit_id:Number(button.dataset.revert)});if(result?.entry?.date)state.date=result.entry.date;await loadDay();notify('Прежние значения восстановлены',true);}catch(error){notify(errorMessage(error));await loadDay();}});
$('#historyDays').addEventListener('click',event=>{const el=event.target.closest('[data-date]');if(!el)return;state.date=el.dataset.date;showTab('day');loadDay();});
$('#prevDay').addEventListener('click',()=>changeDay(-1));$('#nextDay').addEventListener('click',()=>changeDay(1));$('#dateInput').addEventListener('change',event=>{if(event.target.value){dismissNotice();state.date=event.target.value;loadDay();}});
$('#userSelect').addEventListener('change',async event=>{dismissNotice();state.user=Number(event.target.value);state.profile=null;if(state.user===0)notify('Старые записи без владельца и даты показаны все вместе. Они не входят в дневники пользователей.');await loadDay({force:true});if(state.tab==='admin-profile')await renderProfile();});
document.querySelectorAll('[data-tab]').forEach(el=>el.addEventListener('click',()=>showTab(el.dataset.tab)));
document.querySelectorAll('.close-dialog').forEach(el=>el.addEventListener('click',()=>{if(!state.busy)el.closest('dialog').close();}));
document.querySelectorAll('dialog').forEach(el=>el.addEventListener('cancel',event=>{if(state.busy)event.preventDefault();}));

async function renderProfile(){
 const user=state.user;$('#profileContent').innerHTML='<div class="skeleton"></div>';
 const result=await api({action:'profile',...target()});if(user!==state.user)return;state.profile=result.profile||{};
 const p=state.profile;const line=(label,value)=>'<div class="profile-line"><span>'+label+'</span><strong>'+esc(value??'—')+'</strong></div>';
 $('#profileContent').innerHTML='<div class="profile-card"><h2>'+esc(p.name||'Профиль питания')+'</h2><div class="profile-grid">'+line('Цель',p.goal_ru)+line('Пол',p.gender==='male'?'Мужской':p.gender==='female'?'Женский':null)+line('Возраст',p.age?fmt(p.age)+' лет':null)+line('Рост',p.height?fmt(p.height)+' см':null)+line('Вес',p.weight?fmt(p.weight)+' кг':null)+line('Калории',p.daily_calories?kcal(p.daily_calories)+' ккал':null)+line('Активность',activityName(p.activity_level))+line('Часовой пояс',timezoneLabel(p.timezone))+'</div>'+(state.user>0?'<button class="primary profile-edit-button" id="openProfileEdit">'+icon('edit')+'Изменить параметры</button><button class="text-button profile-history-button" id="openProfileHistory">'+icon('history')+'История изменений</button>':'')+'<p class="profile-note">Новый ориентир действует после сохранения. Записи питания остаются на месте.</p><a class="profile-bot-link" href="https://t.me/vilqa_bot">@vilqa_bot</a></div>';
 $('#openProfileEdit')?.addEventListener('click',openProfileEdit);$('#openProfileHistory')?.addEventListener('click',openProfileHistory);
}
function activityName(value){return ({'1.2':'Сидячая','1.375':'Низкая','1.55':'Умеренная','1.725':'Высокая','1.9':'Очень высокая'})[String(Number(value))]||'—';}
function openProfileEdit(){
 const p=state.profile,f=$('#profileForm');state.editingProfile={user_id:state.user,version:p.profile_version||0};
 for(const key of ['name','gender','age','height','weight','goal'])f.elements[key].value=p[key]??'';
 f.elements.activity.value=String(Number(p.activity_level));$('#profileError').hidden=true;$('#profileDialog').showModal();
}
$('#profileForm').addEventListener('submit',async event=>{
 event.preventDefault();if(state.busy)return;const f=event.currentTarget,patch={name:f.elements.name.value.trim(),gender:f.elements.gender.value,goal:f.elements.goal.value};
 for(const key of ['age','height','weight','activity'])patch[key]=Number(f.elements[key].value);
 invalidateDays();state.busy=true;$('#saveProfile').disabled=true;$('#saveProfile').textContent='Сохраняем…';$('#profileError').hidden=true;
 try{await api({action:'profile_edit',user_id:state.editingProfile.user_id,version:state.editingProfile.version,request_id:crypto.randomUUID(),patch});invalidateDays();$('#profileDialog').close();await loadDay({force:true});await renderProfile();notify('Профиль сохранён, дневная норма пересчитана',true);}
 catch(error){$('#profileError').textContent=errorMessage(error);$('#profileError').hidden=false;}
 finally{state.busy=false;$('#saveProfile').disabled=false;$('#saveProfile').textContent='Сохранить и пересчитать';}
});
async function openProfileHistory(){
 $('#auditContent').innerHTML='<div class="skeleton"></div>';$('#auditDialog').showModal();
 try{const result=await api({action:'profile_history',...target()});$('#auditContent').innerHTML=result.events.length?result.events.map(e=>'<article class="audit-event"><h3>'+(({registration:'Регистрация',import:'Перенос профиля',edit:'Профиль изменён'}[e.action]||'Профиль изменён'))+'</h3><small>'+esc(new Date(e.created_at).toLocaleString('ru-RU'))+' · '+(e.actor_id===state.actor?'вы':'администратор/пользователь '+e.actor_id)+'</small>'+(e.before_data?'<div class="audit-values">До: '+esc(e.before_data.name)+' · '+fmt(e.before_data.weight)+' кг · '+kcal(e.before_data.daily_calories)+' ккал</div>':'')+'<div class="audit-values">После: '+esc(e.after_data.name)+' · '+fmt(e.after_data.weight)+' кг · '+kcal(e.after_data.daily_calories)+' ккал<br>Цель: '+esc(e.after_data.goal_ru)+'<br>Рост '+fmt(e.after_data.height)+' см · возраст '+fmt(e.after_data.age)+'</div></article>').join(''):'<p class="profile-note">Профиль ещё не изменялся</p>';}
 catch(error){$('#auditContent').textContent=errorMessage(error);}
}

function setupTelegram(){const app=telegram();app?.ready();app?.expand();app?.onEvent?.('activated',()=>{if(state.actor&&!state.busy)loadDay({force:true});});}
$('#telegramSdk')?.addEventListener('load',setupTelegram,{once:true});setupTelegram();
document.addEventListener('visibilitychange',()=>{if(document.hidden){prefetchRead?.abort();clearTimeout(prefetchTimer);}else if(state.actor&&!state.busy)loadDay({force:true});});
installIcons();if(local||window.VILQA_DEMO)$('#demoNote').hidden=false;loadDay().then(()=>{if(launchParams.get('tab')==='profile'&&state.actor)showTab('profile');});

// Membership administration is checked again by the authenticated server API.
let accessCandidate=null,accessBusy=false;
function accessError(message){$('#accessError').textContent=message||'';$('#accessError').hidden=!message;}
function accountCaption(a){return esc(a.name||a.username||'Telegram-аккаунт')+(a.username?' <small>@'+esc(a.username)+'</small>':'')+'<small>ID '+Number(a.user_id)+'</small>';}
async function loadAccessAccounts(){
 if(!state.admin)return;
 const result=await api({action:'access_list'});
 const active=result.accounts.filter(a=>a.active),waiting=result.accounts.filter(a=>!a.active);
 const row=a=>'<div class="access-account"><div>'+accountCaption(a)+'</div>'+(a.is_owner?'<span class="access-owner">Владелец</span>':a.active?'<button class="text-button danger" data-access-revoke="'+Number(a.user_id)+'" data-access-name="'+esc(a.username||a.name||a.user_id)+'">Отключить</button>':a.username?'<button class="text-button" data-access-lookup="'+esc(a.username)+'">Выбрать</button>':'<span class="access-owner">Нет @ника</span>')+'</div>';
 $('#accessAccounts').innerHTML='<h3>Есть доступ · '+active.length+'</h3>'+active.map(row).join('')+(waiting.length?'<h3>Открывали бота · '+waiting.length+'</h3>'+waiting.map(row).join(''):'');
}
async function findAccessAccount(username){
 if(accessBusy||state.busy)return;accessBusy=true;$('#accessFind').disabled=true;accessCandidate=null;$('#accessCandidate').replaceChildren();accessError('');
 try{const result=await api({action:'access_lookup',username:username.trim()});accessCandidate=result.account;$('#accessCandidate').innerHTML='<div class="access-found"><div>'+accountCaption(result.account)+'</div>'+(result.account.active?'<p>Уже есть доступ</p>':'<button type="button" class="primary" id="grantAccess">Открыть доступ</button>')+'</div>';}
 catch(error){accessError(errorMessage(error));}
 finally{accessBusy=false;$('#accessFind').disabled=false;}
}
$('#accessLookupForm').addEventListener('submit',e=>{e.preventDefault();if(state.admin)findAccessAccount($('#accessUsername').value);});
$('#accessCandidate').addEventListener('click',async e=>{
 if(!e.target.closest('#grantAccess')||!accessCandidate||accessBusy||state.busy||!state.admin)return;
 const account={...accessCandidate};accessBusy=true;state.busy=true;e.target.disabled=true;accessError('');
 try{const result=await api({action:'access_grant',username:account.username,resolved_user_id:Number(account.user_id),identity_version:Number(account.identity_version),request_id:crypto.randomUUID()});$('#accessCandidate').replaceChildren();accessCandidate=null;invalidateDays();await loadAccessAccounts();notify(result.message,true);}
 catch(error){accessError(errorMessage(error));}
 finally{accessBusy=false;state.busy=false;const button=$('#grantAccess');if(button)button.disabled=false;}
});
$('#accessAccounts').addEventListener('click',async e=>{
 const lookup=e.target.closest('[data-access-lookup]');if(lookup){$('#accessUsername').value='@'+lookup.dataset.accessLookup;await findAccessAccount(lookup.dataset.accessLookup);return;}
 const button=e.target.closest('[data-access-revoke]');if(!button||accessBusy||state.busy||!state.admin)return;
 const uid=Number(button.dataset.accessRevoke);if(!await ask('Отключить доступ?','@'+button.dataset.accessName+' больше не сможет пользоваться ботом и дневником. Сохранённые записи останутся.','Отключить'))return;
 accessBusy=true;state.busy=true;button.disabled=true;accessError('');
 try{const result=await api({action:'access_revoke',resolved_user_id:uid,request_id:crypto.randomUUID()});invalidateDays();if(state.user===uid)state.user=state.actor;accessCandidate=null;$('#accessCandidate').replaceChildren();await loadAccessAccounts();const users=await api({action:'users'});$('#userSelect').innerHTML=users.users.map(u=>'<option value="'+Number(u.user_id)+'">'+esc(u.name||u.username||u.user_id)+'</option>').join('');$('#userSelect').value=String(state.user);await loadDay({force:true});notify(result.message,true);}
 catch(error){accessError(errorMessage(error));}
 finally{accessBusy=false;state.busy=false;button.disabled=false;}
});


let recipeLibrary=[];
function recipeValue(recipe,field){
 const direct=recipe['per_100g_'+field];if(direct!==null&&direct!==undefined&&direct!==''&&Number.isFinite(Number(direct))&&Number(direct)>=0)return Number(direct);
 const total=recipe['total_'+field],weight=Number(recipe.total_weight);return total!==null&&total!==undefined&&Number.isFinite(Number(total))&&Number(total)>=0&&weight>0?Number(total)*100/weight:null;
}
function portionValues(recipe,weight){
 const value=field=>{const n=recipeValue(recipe,field);return n===null?'—':(field==='calories'?kcal:fmt)(n*weight/100);};
 return [['calories','Калории','ккал'],['protein','Белки','г'],['fats','Жиры','г'],['carbs','Углеводы','г']].map(([field,label,unit])=>'<span class="nutrition-metric"><span class="nutrition-metric-label">'+label+'</span><strong>'+value(field)+' <small>'+unit+'</small></strong></span>').join('');
}
function parseRecipeIngredients(raw){
 let value=raw;for(let i=0;i<2&&typeof value==='string';i++){try{value=JSON.parse(value);}catch{break;}}
 if(Array.isArray(value))return {items:value,partial:false};
 const text=typeof value==='string'?value.trim():'';
 if(!text.startsWith('['))return {items:[],text:text&&!/^[{]/.test(text)?text:'',partial:false};
 const items=[];let depth=0,start=-1,quoted=false,escaped=false;
 for(let i=0;i<Math.min(text.length,100000);i++){
  const c=text[i];if(quoted){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c==='"')quoted=false;continue;}
  if(c==='"'){quoted=true;continue;}if(c==='{'){if(depth===0)start=i;depth++;}else if(c==='}'&&depth>0){depth--;if(depth===0&&start>=0){try{const item=JSON.parse(text.slice(start,i+1));if(item&&typeof item==='object'&&typeof (item.name||item.item_name)==='string')items.push(item);}catch{}start=-1;}}
 }
 return {items,partial:true};
}
function recipeIngredients(recipe){
 const result=parseRecipeIngredients(recipe.ingredients),items=result.items;
 if(items.length)return '<ul class="recipe-ingredients">'+items.map(item=>{if(typeof item==='string')return '<li>'+esc(item)+'</li>';if(!item||typeof item!=='object')return '';return '<li><span>'+esc(item.name||item.item_name||'Ингредиент')+'</span><span>'+ (item.weight!==null&&item.weight!==undefined&&Number.isFinite(Number(item.weight))?fmt(item.weight)+' г':'')+'</span></li>';}).join('')+'</ul>'+(result.partial?'<p class="recipe-data-note">Состав сохранён не полностью. Показаны доступные ингредиенты.</p>':'');
 return '<p class="recipe-description">'+esc(result.text||'Состав не указан или сохранён с ошибкой')+'</p>';
}
function renderRecipeList(){
 const query=$('#recipeSearch').value.trim().toLocaleLowerCase('ru');const filtered=recipeLibrary.filter(r=>String(r.recipe_name||'').toLocaleLowerCase('ru').includes(query));
 $('#recipeCount').textContent=query?filtered.length+' из '+recipeLibrary.length:russianCount(recipeLibrary.length,['рецепт','рецепта','рецептов']);
 $('#recipeList').innerHTML=filtered.length?filtered.map(r=>'<details class="recipe-card" data-recipe="'+Number(r.id)+'"><summary><span><strong>'+esc(r.recipe_name||'Без названия')+'</strong><small>'+ (recipeValue(r,'calories')===null?'Калорийность не указана':kcal(recipeValue(r,'calories'))+' ккал / 100 г')+'</small></span>'+icon('right')+'</summary><div class="recipe-details"><div class="recipe-heading"><h3>Состав</h3><span>'+ (Number(r.total_weight)>0?'Выход '+fmt(r.total_weight)+' г':'')+'</span></div>'+recipeIngredients(r)+'<div class="recipe-nutrition"><span>На 100 г</span><div class="entry-values">'+portionValues(r,100)+'</div></div><button type="button" class="primary recipe-save-portion" data-recipe-add="'+Number(r.id)+'">'+icon('check')+'Записать порцию</button><button class="text-button danger" data-recipe-delete="'+Number(r.id)+'">'+icon('trash')+'Удалить рецепт</button></div></details>').join(''):'<div class="empty"><h3>'+ (query?'Ничего не найдено':'Сохрани первый рецепт')+'</h3><p>'+ (query?'Попробуй другое название':'Создай рецепт в чате с VILQA — он появится здесь')+'</p>'+ (query?'':'<a href="https://t.me/vilqa_bot">Перейти в бот</a>')+'</div>';
}
async function loadRecipes(){
 $('#recipeList').innerHTML='<div class="skeleton"></div>';$('#recipeCount').textContent='';
 try{const result=await api({action:'recipes'});if(state.tab!=='recipes')return;recipeLibrary=result.recipes||[];renderRecipeList();}
 catch(error){if(state.tab!=='recipes')return;$('#recipeList').innerHTML='<div class="empty"><p>'+esc(errorMessage(error))+'</p><button class="text-button" id="retryRecipes">Повторить загрузку</button></div>';$('#retryRecipes').addEventListener('click',loadRecipes);}
}
$('#recipeSearch').addEventListener('input',renderRecipeList);
$('#recipeList').addEventListener('click',async event=>{const button=event.target.closest('[data-recipe-delete]');if(!button||state.busy)return;const recipe=recipeLibrary.find(r=>Number(r.id)===Number(button.dataset.recipeDelete));if(!recipe)return;if(!await ask('Удалить рецепт «'+(recipe.recipe_name||'Без названия')+'»?','Он исчезнет из библиотеки и списка в боте. Записи дневника сохранятся.','Удалить',{danger:true}))return;try{await mutate('recipe_delete',recipe);recipeLibrary=recipeLibrary.filter(r=>Number(r.id)!==Number(recipe.id));renderRecipeList();notify('Рецепт удалён',true);}catch(error){notify(errorMessage(error));await loadRecipes();}});

let activeRecipePortion=null;
function updateRecipePortionPreview(){if(!activeRecipePortion)return;const w=Number($('#recipePortionForm').elements.weight.value);$('#recipePortionPreview').innerHTML=w>=0.1&&w<=10000?portionValues(activeRecipePortion.recipe,w):'<span>Укажи вес от 0,1 до 10 000 г</span>';}
function openRecipePortion(recipe,weight){
 const form=$('#recipePortionForm');activeRecipePortion={recipe,requestId:crypto.randomUUID(),pending:null,completed:false};
 form.querySelectorAll('input').forEach(el=>el.disabled=false);form.elements.weight.value=weight||100;
 const parts=new Intl.DateTimeFormat('en-GB',{timeZone:state.profile?.timezone||'Europe/Moscow',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date());
 form.elements.date.value=state.date||historyEndDate();form.elements.time.value=parts.find(x=>x.type==='hour').value+':'+parts.find(x=>x.type==='minute').value;
 $('#recipePortionTitle').textContent=recipe.recipe_name||'Порция рецепта';$('#recipePortionError').hidden=true;updateRecipePortionPreview();$('#recipePortionDialog').showModal();
}
$('#recipeList').addEventListener('click',event=>{const button=event.target.closest('[data-recipe-add]');if(!button||state.busy)return;const r=recipeLibrary.find(r=>Number(r.id)===Number(button.dataset.recipeAdd));if(!r)return;openRecipePortion(r,100);});
$('#recipePortionForm').elements.weight.addEventListener('input',updateRecipePortionPreview);
$('#recipePortionForm').addEventListener('submit',async event=>{
 event.preventDefault();if(state.busy||!activeRecipePortion||activeRecipePortion.completed)return;
 const portion=activeRecipePortion,form=event.currentTarget;
 if(!portion.pending)portion.pending={weight:Number(form.elements.weight.value),date:form.elements.date.value,time:form.elements.time.value,request_id:portion.requestId};
 form.querySelectorAll('input').forEach(el=>el.disabled=true);$('#recipePortionError').hidden=true;
 try{const result=await mutate('recipe_add',portion.recipe,portion.pending);if(!result?.entry)throw new Error('Не удалось подтвердить запись. Проверь дневник');portion.completed=true;state.date=result.entry.date;state.user=state.actor;$('#recipePortionDialog').close();await showTab('day');await loadDay({force:true});notify('Порция записана: '+fmt(result.entry.weight)+' г · '+kcal(result.entry.calories)+' ккал',true);}
 catch(error){if([400,403,404,422].includes(error.status)){portion.pending=null;form.querySelectorAll('input').forEach(el=>el.disabled=false);}$('#recipePortionError').textContent=errorMessage(error);$('#recipePortionError').hidden=false;}
});

let recipeStartRequestId=null;
$('#createRecipeInBot').addEventListener('click',async()=>{
 if(state.busy)return;const button=$('#createRecipeInBot');state.busy=true;button.disabled=true;button.querySelector('span:last-child').textContent='Открываем бота…';
 recipeStartRequestId=recipeStartRequestId||crypto.randomUUID();
 try{await api({action:'recipe_start',request_id:recipeStartRequestId});const app=telegram();if(app?.close){try{app.close();}catch{notify('Создание рецепта открыто в боте. Закрой Mini App, чтобы продолжить',true);}}else location.href='https://t.me/vilqa_bot';}
 catch(error){notify(errorMessage(error));}
 finally{state.busy=false;button.disabled=false;button.querySelector('span:last-child').textContent='Создать';}
});

document.querySelectorAll('[data-admin-tab]').forEach(el=>el.addEventListener('click',()=>showTab(el.dataset.adminTab)));

function updateEditingViewport(){const v=window.visualViewport,h=v?.height||innerHeight,top=v?.offsetTop||0;document.documentElement.style.setProperty('--editing-height',h+'px');document.documentElement.style.setProperty('--keyboard-inset',Math.max(0,innerHeight-h-top)+'px');}
updateEditingViewport();window.visualViewport?.addEventListener('resize',updateEditingViewport);window.visualViewport?.addEventListener('scroll',updateEditingViewport);window.addEventListener('resize',updateEditingViewport);

$('#historyDays').addEventListener('input',event=>{if(event.target.id==='historyRange')selectHistoryDay(event.target.value);});
$('#historyDays').addEventListener('click',event=>{const plot=event.target.closest('.history-interaction');if(!plot)return;const box=plot.getBoundingClientRect();selectHistoryDay(Math.round(((event.clientX-box.left)/box.width*312-35)/9));});


let chartPointer=null;
const chartIndex=(event,plot)=>Math.round(((event.clientX-plot.getBoundingClientRect().left)/plot.getBoundingClientRect().width*312-38)/9);
$('#historyDays').addEventListener('pointerdown',event=>{const plot=event.target.closest('.history-interaction');if(!plot||event.button!==0)return;chartPointer={id:event.pointerId,plot};plot.setPointerCapture(event.pointerId);selectHistoryDay(chartIndex(event,plot));});
$('#historyDays').addEventListener('pointermove',event=>{if(chartPointer?.id===event.pointerId)selectHistoryDay(chartIndex(event,chartPointer.plot));});
for(const type of ['pointerup','pointercancel','lostpointercapture'])$('#historyDays').addEventListener(type,()=>{chartPointer=null;});
