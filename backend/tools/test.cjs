const path=require('node:path'),{spawnSync}=require('node:child_process');
process.chdir(path.resolve(__dirname,'../..'));
const files=['fiber-poller.test.cjs','fiber.test.cjs','workflows.test.cjs','test-diary-auth.cjs','test-frontend.cjs','test-telegram-html.cjs','test-recipe-ingredients.cjs'];
if(process.argv.includes('--ui')||process.argv.includes('--webkit'))files.push('test-recipe-portion-ui.cjs','dashboard-layout.test.cjs');
for(const file of files){const env={...process.env};if(process.argv.includes('--webkit')&&file==='dashboard-layout.test.cjs')env.DASHBOARD_ENGINE='webkit';const r=spawnSync(process.execPath,['backend/tests/'+file],{stdio:'inherit',env});if(r.status!==0)process.exit(r.status||1);}
console.log('PASS: '+files.length+' maintained test suites');
