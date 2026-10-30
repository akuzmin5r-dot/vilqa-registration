const assert=require('node:assert/strict'),{prepareFiber,parseFiber,fiberMessage}=require('../src/fiber.cjs');
const job={items:[{id:1,name:'Apple',weight:100,signature:'a'},{id:2,name:'Chicken',weight:100,signature:'b',fiber:0}]},p=prepareFiber(job);
assert.deepEqual(parseFiber('{"items":[{"id":1,"fiber":2.4}]}',p).values.map(x=>x.fiber),[0,2.4]);
for(const raw of ['{',{error:'timeout'},{items:[]},{items:[{id:9,fiber:2}]},{items:[{id:1,fiber:101}]},{items:[{id:1,fiber:-1}]}]){const r=parseFiber(raw,p);assert.ok(r.model_error);assert.equal(r.values[0].fiber,0);assert.equal(r.values[1].fiber,null);assert.equal(r.values[1].signature,'a');}
assert.equal(prepareFiber({items:[{id:1,name:'хлеб Карельский',signature:'a',weight:250,cached_per100:8.5}]}).needs_model,true);
const summary={date:'2026-10-30',meal_fiber:6.2,meal_unknown:0,day_fiber:18.4,day_unknown:0,target:25,remaining:6.6,remaining_calories:300};
assert.match(fiberMessage(summary),/6,2 г/);assert.match(fiberMessage(summary),/Можно выбрать/);assert.doesNotMatch(fiberMessage({...summary,day_unknown:1}),/Можно выбрать/);
console.log('PASS: canonical fiber parser and formatter, errors preserve known values');
