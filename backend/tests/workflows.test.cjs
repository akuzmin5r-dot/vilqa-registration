const assert=require('node:assert/strict'),fs=require('fs'),path=require('path'),{run}=require('../tools/generate-workflows.cjs');
run(true);
const get=kind=>JSON.parse(fs.readFileSync(path.resolve(__dirname,'../workflows',kind+'.json'),'utf8'));
for(const kind of ['main','fiber','api']){const w=get(kind),names=new Set(w.nodes.map(n=>n.name));for(const n of w.nodes)if(n.type==='n8n-nodes-base.code')new Function(n.parameters.jsCode);for(const [name,c]of Object.entries(w.connections)){assert.ok(names.has(name));for(const lanes of Object.values(c))for(const lane of lanes||[])for(const e of lane||[])assert.ok(names.has(e.node));}}
const m=get('main'),f=get('fiber');
const normalize=update=>new Function('$','$execution',m.nodes.find(n=>n.name==='Нормализовать событие Telegram').parameters.jsCode)(()=>({first:()=>({json:update})}),{id:'test'})[0].json;
assert.equal(normalize({message:{from:{id:123,first_name:'А'},chat:{id:123},text:'/MENU'}}).message_text,'/menu');
assert.equal(normalize({callback_query:{id:'c',from:{id:123},message:{chat:{id:123}},data:'n:141:menu_food_entry'}}).callback_data,'menu_food_entry');
assert.equal(m.nodes.find(n=>n.name==='Нормализовать событие Telegram').type,'n8n-nodes-base.code');
assert.equal(f.nodes.find(n=>n.name==='Модель · оценка клетчатки').parameters.options.timeout,45000);
console.log('PASS: current generated graph, current menu normalizer and fiber timeout');
