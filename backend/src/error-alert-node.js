const WORKFLOWS={"f0dMmWk0Mte7utYu":"VILQA — клетчатка","a08kQaFjSLUxlmpNlmV2J":"VILQA — бот","ZRjTZf8Dejt-wZDny90_8":"VILQA — статистика","9c44CeVZqqmXNebA":"VILQA — Mini App API","J4XikahpZkt8KYXo":"ПРОВЕРКА мониторинга VILQA"};
const EVENTS={"model_request_failed":"Не удалось получить ответ от AI","model_output_invalid":"Ответ AI не прошёл проверку формата","access_storage":"Не удалось проверить доступ к VILQA","registration_storage":"Не удалось сохранить регистрацию","meal_commit":"Не удалось подтвердить запись еды","diary_storage":"Ошибка чтения или сохранения дневника","voice_processing":"Не удалось обработать голосовое сообщение","profile_notification_claim":"Не удалось подготовить уведомление об изменении профиля","profile_notification_delivery":"Не удалось доставить уведомление об изменении профиля","profile_notification_status":"Не удалось сохранить результат доставки уведомления","meal_notification":"Не удалось отправить подтверждение записи еды","meal_stats":"Не удалось отправить статистику после записи еды"};
function errorAlert(data) {
  const id=String(data?.workflow?.id||data?.workflow_id||'');
  if(!WORKFLOWS[id])return null;
  const execution=data.execution||{};
  const executionId=String(execution.id||data.execution_id||'');
  const err=execution.error||data.trigger?.error||{};
  const raw=String(err.message||'');
  const modelCategory={provider_bad_request:'Провайдер отклонил запрос (400)',provider_timeout:'Превышено время ожидания AI',provider_error:'Ошибка запроса к AI'}[data.error_code];
  const category=modelCategory||(/429|rate.?limit|too many requests/i.test(raw)?'Ограничение частоты запросов':/timeout|timed out|ETIMEDOUT/i.test(raw)?'Превышено время ожидания':/credential|unauthorized|forbidden|401|403/i.test(raw)?'Доступ или авторизация':/connect|database|postgres|ECONN/i.test(raw)?'Соединение или база данных':'Технический сбой');
  const esc=v=>String(v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  const stage=String(execution.lastNodeExecuted||data.stage||data.trigger?.error?.node?.name||'Запуск workflow').slice(0,100);
  const title=EVENTS[data.event]||'Workflow завершился с ошибкой';
  const link=/^\d{1,20}$/.test(executionId)?`https://n8n.svoidigital.ru/workflow/${id}/executions/${executionId}`:`https://n8n.svoidigital.ru/workflow/${id}`;
  return {chat_id:180753266,text:`🚨 <b>${esc(title)}</b>\n\n${esc(WORKFLOWS[id])}\nУзел: <code>${esc(stage)}</code>\nТип: ${esc(category)}${executionId&&/^\d{1,20}$/.test(executionId)?'\nВыполнение: <code>'+executionId+'</code>':''}\n\n<a href="${link}">Открыть в n8n</a>`,workflow_id:id,workflow_name:WORKFLOWS[id],error_message:title+' · '+category,last_node:stage,execution_url:link,mode:EVENTS[data.event]?'handled':'unhandled',execution_id:/^\d{1,20}$/.test(executionId)?executionId:'',event:EVENTS[data.event]?data.event:'unhandled'};
}
const result=errorAlert($input.first().json);return result?[{json:result}]:[];

