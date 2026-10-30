function prepareFiber(job){
 if(!job||!Array.isArray(job.items)||job.items.length>30)throw Error('Invalid fiber job');
 const values=[],unknown=[];
 for(const item of job.items){
  const base={id:Number(item.id),signature:item.signature};
  if(typeof item.fiber==='number'&&Number.isFinite(item.fiber))values.push({...base,fiber:item.fiber});
  else if(typeof item.cached_per100==='number'&&Number.isFinite(item.cached_per100)&&(item.recipe||!/(?:хлеб|батон|булоч|печенье|торт|колбас|сосиск|батончик)/i.test(item.name||'')))values.push({...base,fiber:Math.round(item.cached_per100*item.weight/100*10)/10});
  else unknown.push({id:Number(item.id),name:item.name,weight:item.weight,calories:item.calories,protein:item.protein,fats:item.fats,carbs:item.carbs,recipe:item.recipe||null});
 }
 return {job,values,unknown,needs_model:unknown.length>0,prompt:JSON.stringify({items:unknown})};
}

function parseFiber(raw,prepared){
 const fallback=reason=>({job:prepared.job,values:[...prepared.values,...prepared.unknown.map(x=>({id:x.id,signature:prepared.job.items.find(i=>Number(i.id)===Number(x.id)).signature,fiber:null}))],model_error:reason});
 let parsed;try{parsed=typeof raw==='string'?JSON.parse(raw.trim().replace(/^\x60\x60\x60(?:json)?\s*/i,'').replace(/\s*\x60\x60\x60$/,'')):raw;}catch{return fallback('invalid_json');}
 if(!parsed||!Array.isArray(parsed.items)||parsed.items.length!==prepared.unknown.length)return fallback('invalid_shape');
 const seen=new Set(),values=[...prepared.values];
 for(const row of parsed.items){
  if(!row||typeof row!=='object')return fallback('invalid_item');
  const id=Number(row.id),item=prepared.job.items.find(x=>Number(x.id)===id);
  if(!item||!prepared.unknown.some(x=>Number(x.id)===id)||seen.has(id))return fallback('invalid_id');seen.add(id);
  if(row.fiber!==null&&(typeof row.fiber!=='number'||!Number.isFinite(row.fiber)||row.fiber<0||row.fiber>item.weight))return fallback('invalid_quantity');
  values.push({id,signature:item.signature,fiber:row.fiber===null?null:Math.round(row.fiber*10)/10});
 }
 return {job:prepared.job,values};
}
function fiberMessage(s){
 const n=v=>new Intl.NumberFormat('ru-RU',{maximumFractionDigits:1}).format(v);
 const date=String(s.date||'').split('-').reverse().join('.');
 let text=s.deleted?'🌾 <b>Клетчатка · дневник обновлён</b>':s.meal_unknown?'🌾 <b>Клетчатка в приёме пищи: данные неполные</b>':'🌾 <b>Клетчатка в этом приёме пищи: ≈ '+n(s.meal_fiber)+' г</b>';
 text+='\n\n'+date+'\nЗа день: ≈ '+n(s.day_fiber)+' г';
 if(s.day_unknown){text+='\n<i>Итог неполный: без данных '+n(s.day_unknown)+' записей.</i>\nДневной ориентир: '+n(s.target)+' г';}
 else if(s.remaining>0){text+='\nДо дневного ориентира '+n(s.target)+' г осталось: ≈ '+n(s.remaining)+' г';}
 else text+='\nДневной ориентир '+n(s.target)+' г достигнут';
 if(!s.day_unknown&&s.remaining>0&&!s.deleted){
  const foods=[{name:'варёная чечевица',fiber:7.9,cal:116,max:150},{name:'малина',fiber:6.5,cal:52,max:150},{name:'брокколи на пару',fiber:3.3,cal:35,max:200},{name:'яблоко с кожурой',fiber:2.4,cal:52,max:200}];
  const options=foods.map(f=>{const grams=Math.min(f.max,Math.max(30,Math.round(s.remaining/f.fiber*100/10)*10));return {...f,grams,portionFiber:grams*f.fiber/100,portionCal:grams*f.cal/100};}).filter(f=>f.portionCal<=s.remaining_calories&&f.portionFiber<=s.remaining+1).sort((a,b)=>Math.abs(s.remaining-a.portionFiber)-Math.abs(s.remaining-b.portionFiber)).slice(0,2);
  if(options.length)text+='\n\nМожно выбрать один вариант:\n'+options.map(f=>'• '+f.name+' · '+f.grams+' г — ≈ '+n(f.portionFiber)+' г клетчатки, '+Math.round(f.portionCal)+' ккал').join('\n');
 }
 return text+'\n\n<i>Клетчатка и варианты продуктов — приблизительная оценка.</i>';
}
module.exports={prepareFiber,parseFiber,fiberMessage};
