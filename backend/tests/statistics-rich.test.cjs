const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const w=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../workflows/stats.json'),'utf8'));
const code=w.nodes.find(n=>n.name==='📝 Format Stats Message').parameters.jsCode;
const base={chat_id:123,date:'2026-10-30',timezone:'Europe/Moscow',stats:{totalCalories:1170,dailyCalories:2188,totalProtein:80,dailyProtein:164,totalFats:50,dailyFats:61,totalCarbs:100,dailyCarbs:246},dailyFiber:25,logs:[{id:1,time:'09:15',item_name:'Овсянка <img src=x onerror=alert(1)>',weight:250,calories:430,protein:20,fats:14,carbs:56,fiber:5,fiber_status:'estimated'},{id:2,time:'14:00',item_name:'Курица с рисом',weight:350,calories:740,protein:60,fats:36,carbs:44,fiber:7.4,fiber_status:'estimated'}]};
const run=data=>new Function('$json',code)(data).json;
const totals=html=>[...html.matchAll(/<table compact>([\s\S]*?)<\/table>/g)].at(-1)[1];
const nutrientRow=(html,label)=>totals(html).match(/<tr>[\s\S]*?<\/tr>/g).find(row=>row.includes(label));
let r=run(base),html=r.rich_html;
assert.match(html,/^<p>📊 <b>Статистика • 30 октября<\/b> 🍴<\/p>/);
assert.equal((html.match(/<table\b/g)||[]).length,1);
assert.doesNotMatch(html,/<hr|<details|<h[1-6]>|приблизительная оценка/);assert.equal((html.match(/<blockquote>/g)||[]).length,1);assert.ok(html.indexOf('</blockquote>')<html.indexOf('<table compact>'));
assert.doesNotMatch(html,/striped|Время|09:15|14:00|<th\b/);assert.match(html,/<b>Белки<\/b>/);assert.match(html,/<b>Жиры<\/b>/);assert.match(html,/<b>Углеводы<\/b>/);assert.match(html,/<b>Калории<\/b>/);assert.match(html,/<b>Клетчатка<\/b>/);assert.match(html,/430 ккал · Б 20 · Ж 14 · У 56/);assert.match(html,/&lt;img/);assert.doesNotMatch(html,/<img src/);
assert.ok(html.indexOf('Овсянка')<html.lastIndexOf('<table compact>'));
assert.doesNotMatch(totals(html),/<th\b/);assert.equal((totals(html).match(/<td align="left">\u00a0<\/td>/g)||[]).length,6);
assert.match(nutrientRow(html,'Калории'),/🟩🟩⬜⬜<br>Ещё 1[\s\u00a0]018 ккал/);
r=run({...base,logs:[]});assert.match(r.rich_html,/Пока ничего не записано/);assert.equal((r.rich_html.match(/<table\b/g)||[]).length,1);
for(const status of ['pending','unknown']){r=run({...base,logs:[{...base.logs[0],fiber:null,fiber_status:status}]});assert.match(r.rich_html,status==='pending'?/Считаю/:/Данные неполные/);assert.equal(r.fiber_pending,status==='pending');assert.match(nutrientRow(r.rich_html,'Клетчатка'),/>—<\/td>/);}
r=run({...base,logs:Array.from({length:400},(_,i)=>({...base.logs[0],id:i,item_name:'Длинное название '.repeat(30)}))});assert.ok(r.rich_html.length<32000);assert.match(r.rich_html,/Все записи/);
r=run({...base,logs:[base.logs[0],base.logs[0]]});assert.equal((r.rich_html.match(/&lt;img/g)||[]).length,2,'Never drop duplicate rows from the snapshot');
for(const [value,expected]of [[0,'⬜⬜⬜⬜'],[24.9,'⬜⬜⬜⬜'],[25,'🟩⬜⬜⬜'],[50,'🟩🟩⬜⬜'],[75,'🟩🟩🟩⬜'],[99.9,'🟩🟩🟩⬜'],[100,'🟩🟩🟩🟩'],[101,'🟨🟨🟨🟨'],[120,'🟨🟨🟨🟨'],[120.1,'🟥🟥🟥🟥']]){
 const stats={...base.stats};for(const key of ['Calories','Protein','Fats','Carbs']){stats['total'+key]=value;stats['daily'+key]=100;}
 html=run({...base,stats}).rich_html;
 for(const label of ['Калории','Белки','Жиры','Углеводы'])assert.ok(nutrientRow(html,label).includes(expected),label+' at '+value+'%');
}
for(const [value,expected]of [[0,'⬜⬜⬜⬜'],[0.1,'🟥⬜⬜⬜'],[25,'🟥⬜⬜⬜'],[49.9,'🟥🟥⬜⬜'],[50,'🟨🟨⬜⬜'],[75,'🟨🟨🟨⬜'],[99.9,'🟨🟨🟨🟨'],[100,'🟩🟩🟩🟩'],[150,'🟩🟩🟩🟩']]){
 html=run({...base,dailyFiber:100,logs:[{...base.logs[0],fiber:value,fiber_status:'manual'}]}).rich_html;
 assert.ok(nutrientRow(html,'Клетчатка').includes(expected),'Fiber at '+value+'%');
}
r=run({...base,stats:{...base.stats,totalCalories:2500}});assert.match(r.rich_html,/Сверх 312 ккал/);
console.log('PASS: food table, aligned totals with spacer rows, safe content, limits, shared macro bars and red-to-green fiber');
