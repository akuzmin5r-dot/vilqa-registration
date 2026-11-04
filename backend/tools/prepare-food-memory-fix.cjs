const fs=require('node:fs'),path=require('node:path');
const file=path.resolve(__dirname,'../workflows/main.json'),w=JSON.parse(fs.readFileSync(file,'utf8'));
const mem=w.nodes.find(n=>n.name==='Log Postgres Chat Memory');
mem.parameters={...mem.parameters,tableName:'vilqa_food_dialog_memory',contextWindowLength:5};
const report=w.nodes.find(n=>n.name==='Report model_output_invalid');
report.parameters.jsonOutput='={{ ({workflow_id:$workflow.id,event:$json.response_error_code === "model_request_failed" ? "model_request_failed" : "model_output_invalid",error_code:$json.response_error_kind || null,stage:"Подготовить расчёт еды · "+$json.response_error_code,execution_id:$execution.id}) }}';
fs.writeFileSync(file,JSON.stringify(w,null,2));
require('./generate-workflows.cjs').run();
