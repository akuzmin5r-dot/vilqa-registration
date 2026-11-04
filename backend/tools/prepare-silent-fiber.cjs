const fs=require('node:fs'),path=require('node:path');
const file=path.resolve(__dirname,'../workflows/fiber.json'),w=JSON.parse(fs.readFileSync(file,'utf8'));
const removed=new Set(['06 · Собрать итог и варианты еды','07 · Защитить от повторной отправки','08 · Отправить клетчатку в Telegram','09 · Сохранить доставку','10 · Проверить подтверждение Telegram','Статус · начать клетчатку','Статус · закончить клетчатку','Уведомлять о новом приёме?','Закрыть статус нового приёма?']);
w.nodes=w.nodes.filter(n=>!removed.has(n.name));
for(const [name,c]of Object.entries(w.connections)){if(removed.has(name)){delete w.connections[name];continue;}for(const lanes of Object.values(c))for(let i=0;i<lanes.length;i++)lanes[i]=lanes[i].filter(e=>!removed.has(e.node));}
w.connections['Нужен расчёт ИИ?'].main[0]=[{node:'03 · Оценить клетчатку продуктов',type:'main',index:0}];
w.connections['03 · Оценить клетчатку продуктов']={main:[[{node:'04 · Проверить ответ модели',type:'main',index:0}]]};
w.nodeGroups=w.nodeGroups.map(g=>({...g,nodeNames:g.nodeNames.filter(n=>!removed.has(n)),description:'Фоновый расчёт клетчатки и сохранение в дневник. Без сообщений и индикаторов в Telegram.'})).filter(g=>g.nodeNames.length);
fs.writeFileSync(file,JSON.stringify(w,null,2));
