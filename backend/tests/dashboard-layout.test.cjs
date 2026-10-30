const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{chromium,webkit}=require('playwright');
(async()=>{
 const browser=process.env.DASHBOARD_ENGINE==='webkit'?await webkit.launch({headless:true}):await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:440,height:956},deviceScaleFactor:3});
  await page.route('**/*',async route=>{
   const u=new URL(route.request().url());
   if(u.pathname==='/__diary/api')return route.fulfill({json:{success:true,actor_id:1,user_id:1,date:'2026-10-30',is_admin:true,entries:[],profile:{daily_calories:2188,daily_protein:164,daily_fats:61,daily_carbs:246},totals:{count:0,calories:0,protein:0,fats:0,carbs:0}}});
   if(u.hostname!=='127.0.0.1')return route.abort();
   const file=path.resolve(__dirname,'../../diary',u.pathname==='/'?'index.html':'.'+u.pathname);
   if(!fs.existsSync(file))return route.fulfill({status:404,body:''});
   return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.html')?'text/html':file.endsWith('.js')?'text/javascript':'text/css'});
  });
  await page.goto('http://127.0.0.1:8877/');await page.locator('.nutrition-dashboard').waitFor();
  const widths=process.env.DASHBOARD_BEFORE?[440]:[320,390,440,560];
  for(const width of widths){
   await page.setViewportSize({width,height:956});
   const result=await page.evaluate(()=>{
    const get=s=>{const el=document.querySelector(s),r=el.getBoundingClientRect(),c=getComputedStyle(el);return {x:r.x,right:r.right,width:r.width,height:r.height,background:c.backgroundColor,color:c.color,border:c.border,borderWidth:c.borderTopWidth,columns:c.gridTemplateColumns,maxWidth:c.maxWidth};};
    return {left:get('.nutrition-dashboard .summary'),right:get('.macro-grid'),grid:get('.nutrition-dashboard'),fiber:get('.fiber-summary'),recipe:get('.recipe-day-add'),bot:get('.empty a'),overflow:document.documentElement.scrollWidth>innerWidth};
   });
   console.log(JSON.stringify({engine:process.env.DASHBOARD_ENGINE||'chromium',width,gap:result.right.x-result.left.right,square:result.left.width,height:result.left.height}));
   if(width===440){await page.waitForFunction(()=>!document.querySelector('#dayContent').getAnimations().some(a=>a.playState==='running'));await page.screenshot({path:path.resolve(__dirname,'../../../artifacts/dashboard-'+(process.env.DASHBOARD_BEFORE?'before':'after')+'-440.png'),fullPage:true});}
   if(process.env.DASHBOARD_BEFORE)continue;
   assert.ok(result.right.x-result.left.right<=12,'actual tile gap exceeds the grid gutter');
   assert.ok(Math.abs(result.left.width-result.left.height)<2,'calorie tile must stay square');
   assert.ok(Math.abs(result.right.height-result.left.height)<2,'macros must span the square height');
   assert.equal(result.fiber.background,'rgba(0, 0, 0, 0)');assert.equal(result.fiber.borderWidth,'1px');
   assert.equal(result.recipe.background,result.bot.background);assert.equal(result.recipe.color,result.bot.color);
   assert.equal(result.overflow,false);
  }
  console.log('PASS: dashboard geometry and information/action hierarchy');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
