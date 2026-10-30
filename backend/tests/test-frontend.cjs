const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html=fs.readFileSync('index.html','utf8');
const scripts=[...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(x=>x[1]).filter(x=>x.trim());
assert.equal(scripts.length,1);
async function scenario(response, hold=false){
 const els={};const events={};let closed=0;let requests=0;let sent;let release;
 const make=id=>els[id]||(els[id]={value:({name:'Иван',age:'30',height:'180',weight:'80',activity:'1.55',goal:'maintain'})[id]||'',textContent:'',classList:{add(){},remove(){},toggle(){}},checkValidity:()=>true,setAttribute(){},addEventListener(type,fn){events[id+':'+type]=fn;}});
 const form=make('registrationForm');
 const context={console,URLSearchParams,Intl,Date,Error,setTimeout:fn=>fn(),location:{reload(){}},window:{location:{search:''},Telegram:{WebApp:{initData:'signed-telegram-data',initDataUnsafe:{user:{id:123,first_name:'Иван'}},ready(){},expand(){},MainButton:{hide(){}},close(){closed++;}}}},document:{getElementById:make,querySelector:()=>({value:'male'}),querySelectorAll:()=>[],addEventListener(type,fn){if(type==='DOMContentLoaded')fn();}},FormData:class{constructor(){return new Map([['name',make('name').value],['gender','male'],['age','30'],['height','180'],['weight','80'],['activity','1.55'],['goal','maintain'],['timezone','Europe/Moscow']]);}},fetch:async(url,opt)=>{requests++;sent=JSON.parse(opt.body);if(hold)await new Promise(r=>release=r);return {ok:response.ok,status:response.ok?200:400,statusText:'',json:async()=>response.body};}};
 vm.runInNewContext(scripts[0],context);
 const pending=events['registrationForm:submit']({preventDefault(){}});
 if(hold){await events['registrationForm:submit']({preventDefault(){}});assert.equal(requests,1);release();}
 await pending;return {sent,closed,requests,disabled:make('submitButton').disabled};
}
(async()=>{
 const ok=await scenario({ok:true,body:{success:true}},true);assert.equal(ok.sent.initData,'signed-telegram-data');assert.equal(ok.closed,1);
 const logicalError=await scenario({ok:true,body:{success:false,message:'Ошибка'}});assert.equal(logicalError.closed,0);assert.equal(logicalError.disabled,false);
 const serverError=await scenario({ok:false,body:{success:false,message:'Ошибка'}});assert.equal(serverError.closed,0);
 assert(!html.includes('debugDiv.innerHTML'));
 console.log(JSON.stringify({passed:6}));
})().catch(e=>{console.error(e);process.exitCode=1;});
