const fs=require('fs'),path=require('path');
const base=path.resolve(__dirname,'..'),fiber=require('../src/fiber.cjs'),telegram=require('../src/telegram.cjs'),statistics=require('../src/statistics.cjs');
const buttons=require('../src/button-policy.cjs');
function replacePrefix(code,marker,prefix){const at=code.indexOf(marker);if(at<0)throw Error('Missing wrapper '+marker);return prefix+'\n'+code.slice(at+1);}
function desired(kind,node){const code=node.parameters.jsCode;
 if(kind==='stats'&&node.name==='📝 Format Stats Message')return statistics.statisticsArticle.toString()+'\nreturn {json:statisticsArticle($json)};';
 if(['Split Stats Message','Статистика порции · разделить сообщение'].includes(node.name))return "const data=$input.first().json;if(!data.rich_html)throw new Error('Rich statistics content is missing');return [{json:data,pairedItem:{item:0}}];";
 if(kind==='api'&&code.includes('function verifyDiaryRequest'))return fs.readFileSync(path.join(base,'src/diary-verify-node.js'),'utf8');
 if(kind==='main'&&code.includes('function validateRegistration'))return fs.readFileSync(path.join(base,'src/registration-validator.js'),'utf8');
 if(kind==='fiber'){
  if(node.name==='02 · Проверить кэш и состав')return replacePrefix(code,'\nreturn ',fiber.prepareFiber.toString());
  if(node.name==='04 · Проверить ответ модели')return replacePrefix(code,'\nconst p=',fiber.parseFiber.toString());
  if(node.name==='06 · Собрать итог и варианты еды')return replacePrefix(code,'\nconst s=',fiber.fiberMessage.toString());
 }
 if(['Разбить ответ на части','Разбить рекомендации на части','Split Stats Message','Статистика порции · разделить сообщение'].includes(node.name))return replacePrefix(code,'\nreturn telegramChunks',telegram.telegramChunks.toString());
 if(['Собрать квитанцию сохранения','Собрать квитанцию отмены или повтора'].includes(node.name))return replacePrefix(code,'\nconst data=',telegram.mealCard.toString());
 if(['Собрать экран текущего шага рецепта','Mini App · экран создания рецепта'].includes(node.name))return replacePrefix(code,'\nconst row=',telegram.escapeHTML.toString()+'\n'+telegram.recipeScreen.toString());
 return code;
}
function run(check=false){let changed=0;for(const kind of ['main','fiber','api','stats']){
 const file=path.join(base,'workflows',kind+'.json'),w=JSON.parse(fs.readFileSync(file,'utf8'));
 for(const n of w.nodes.filter(n=>n.type==='n8n-nodes-base.telegram'))if(buttons.applyButtonPolicy(n)){changed++;if(check)throw Error('Button policy drift: '+kind+'/'+n.name);}
 for(const n of w.nodes){if(n.type!=='n8n-nodes-base.code')continue;const code=desired(kind,n);new Function(code);if(code!==n.parameters.jsCode){changed++;if(check)throw Error('Generated code drift: '+kind+'/'+n.name);n.parameters.jsCode=code;}}
 if(!check)fs.writeFileSync(file,JSON.stringify(w,null,2));
 }return changed;}
module.exports={run,desired};if(require.main===module)console.log((process.argv.includes('--check')?'Checked':'Generated')+' workflows; changes='+run(process.argv.includes('--check')));
