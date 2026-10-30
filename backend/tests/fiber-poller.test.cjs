const assert=require('node:assert/strict');
const create=require('../../diary/fiber-poller.js');
(async()=>{
 let pending=['1:1'],enabled=true,calls=0,fail=false,timers=new Map(),next=0;
 const poller=create({snapshot:()=>({key:'123:2026-10-30',pending,enabled}),refresh:async()=>{calls++;if(fail)throw Error('offline');},schedule:fn=>{timers.set(++next,fn);return next;},cancel:id=>timers.delete(id)});
 const tick=async()=>{const [id,fn]=timers.entries().next().value;timers.delete(id);await fn();};
 poller.sync();for(let i=0;i<12;i++)await tick();assert.equal(calls,12);assert.equal(timers.size,0);
 pending=['1:1','2:1'];poller.sync();assert.equal(timers.size,1);await tick();assert.equal(calls,13);
 fail=true;await tick();assert.equal(timers.size,1,'network error must schedule another attempt');fail=false;
 enabled=false;poller.sync();assert.equal(timers.size,0);enabled=true;poller.sync();assert.equal(timers.size,1);
 pending=[];poller.sync();assert.equal(timers.size,0);pending=['2:2'];poller.sync();assert.equal(timers.size,1);
 poller.stop();assert.equal(timers.size,0);console.log('PASS: per-pending-set budget, new meal, revision, transient failure, visibility and stop');
})().catch(e=>{console.error(e);process.exitCode=1;});
