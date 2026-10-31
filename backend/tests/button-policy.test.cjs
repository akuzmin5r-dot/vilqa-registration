const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {telegramButtonStyle:style,applyButtonPolicy}=require('../src/button-policy.cjs');
for(const [text,action,expected]of [
 ['📔 Открыть дневник','','success'],['📔 Дневник','','success'],['✅ Да, записать','meal_confirm:abc','success'],['✅ Всё-таки записать','meal_restore:abc','success'],['⏸ Сохранить и выйти','recipe_pause','success'],['📝 Записать еду','menu_food_entry',''],['📝 Записать еду','n:42:menu_food_entry',''],['📝 Записать еду','',''],
 ['❌ Отменить','meal_cancel:abc','danger'],['Отмена','n:12:recipe_cancel','danger'],['🗑 Удалить черновик','recipe_delete_confirm',''],['📊 Статистика','menu_stats',''],['Профиль','menu_profile',''],['💡 Рекомендация','menu_recommendation',''],['Регистрация','',''],['Главное меню','menu_main',''],['✏️ Проверить запись','','']])assert.equal(style(text,action),expected,text);
const dynamic={parameters:{inlineKeyboard:{rows:[{row:{buttons:[{text:'={{ $json.text }}',additionalFields:{callback_data:'={{ $json.action }}'}}]}}]}}};
applyButtonPolicy(dynamic);const code=dynamic.parameters.inlineKeyboard.rows[0].row.buttons[0].additionalFields.style.slice(3,-2);
assert.equal(new Function('$json','return '+code)({text:'Отменить',action:'meal_cancel:a'}),'danger');
assert.equal(new Function('$json','return '+code)({text:'Рецепты',action:'menu_recipes'}),'');
for(const kind of ['main','api']){const w=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../workflows',kind+'.json'),'utf8'));for(const node of w.nodes.filter(n=>n.type==='n8n-nodes-base.telegram'))assert.equal(applyButtonPolicy(node),false,'Policy drift: '+kind+'/'+node.name);}
console.log('PASS: green diary/save, red cancel, default remaining actions and dynamic expressions');
