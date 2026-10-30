(function(root,factory){
 'use strict';
 const create=factory();
 if(typeof module==='object'&&module.exports)module.exports=create;
 else root.createFiberPoller=create;
})(typeof globalThis==='object'?globalThis:this,function(){
 'use strict';
 return function createFiberPoller({snapshot,refresh,schedule=setTimeout,cancel=clearTimeout,delay=5000,maxAttempts=12}){
  let timer=null,key='',attempts=0,inFlight=false,stopped=false;
  function clear(){if(timer!==null)cancel(timer);timer=null;}
  function sync(){
   if(stopped)return;
   const current=snapshot();
   const next=current.pending.length?current.key+':'+[...current.pending].sort().join(','):'';
   if(next!==key){clear();key=next;attempts=0;}
   if(!current.enabled||!key){clear();return;}
   if(inFlight||timer!==null||attempts>=maxAttempts)return;
   timer=schedule(async()=>{
    timer=null;
    if(stopped||!snapshot().enabled)return;
    inFlight=true;attempts++;
    try{await refresh();}catch{/* Retry transient failures within this pending set's budget. */}
    finally{inFlight=false;sync();}
   },delay);
  }
  return {sync,stop(){stopped=true;clear();}};
 };
});
