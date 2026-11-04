# Restore food calculations after poisoned tool-history window

## Cause and evidence

Executions 9994, 10000 and 12838 did not contain malformed model output. The agent returned an error object after Gemini through OpenRouter rejected the request with HTTP 400. All three loaded the same ten-message window beginning with a ToolMessage whose matching assistant tool call was outside the window. Failed requests did not advance the stored history, so subsequent messages reproduced the same failure. The output-preparation node discarded the error object and tried to validate its missing output, producing the misleading `model_output_invalid` alert.

Related upstream report: https://github.com/n8n-io/n8n/issues/34187 . The installed memory node uses BufferWindowMemory and a Postgres history store; its sliding window can cut intermediate tool interactions.

## Change

- Migration `20261104_food_dialog_memory.sql` creates a projection over the original `public.n8n_chat_histories`. It replays only nonempty human messages and completed assistant text, strips tool metadata, and excludes tool responses/planning calls. Tool interactions during a current agent run stay intact in the agent's working context.
- An INSTEAD OF INSERT trigger forwards new messages to the original history table unchanged. Historical data, including raw tool traces, is preserved. The projection accepts food sessions beginning with `log:`. Other recipe/recommendation memory nodes keep their original configuration.
- `Log Postgres Chat Memory` uses `vilqa_food_dialog_memory` with an explicit five-interaction context window. It can no longer replay an orphaned tool call/result, regardless of window position.
- Canonical `src/meal-response.cjs` retains the existing meal validator and source idempotency. It checks the agent error object before reading output. Provider errors produce no rows or confirmation button; user-facing text stays friendly and contains no raw provider details. Valid calculations and numeric limits remain unchanged.
- Error reporting distinguishes `model_request_failed` from `model_output_invalid`, with safe provider-bad-request/timeout/error categories. The sanitizer is canonical in `src/error-alert-node.js`.

## Verification

- SQL rollback tests in execution 12867 verified filtered reads, stripped tool metadata and write-through inserts. No test rows survived the rollback.
- The initial attempt to replay a copied personal conversation was rejected by automatic approval review because it could send sensitive chat content to the model. It was not executed. The diagnostic was replaced with entirely synthetic messages and no personal user data.
- Synthetic replay A, execution 12874: original raw history, same model/provider/parser, HTTP 400 reproduced.
- Synthetic replay B, execution 12875: only memory table changed to the safe projection; returned valid structured `{message: "TEST OK", items: []}`. Native Postgres memory read/write worked through the projection.
- Ten maintained local suites passed, including provider-vs-format classification, valid calculations, clarification preservation, numeric-string rejection and no writes on provider failure.
- All four changed production nodes validated. Published parameters were compared with canonical exports.
- Execution 12879 removed only the isolated synthetic session (12 rows), then compared all 62 original backed-up messages with the original JSON: exactly unchanged.
- Maintenance workflow restored to its original two nodes. No real food request was replayed externally for the diagnostic, no Telegram test message was sent, and no diary entry was created.

## Release and recovery

Published main version: `554ae9b6-f875-471e-94a8-9b932af23494`.
Published shared error handler: `70225d3b-b59b-4d25-9ca8-334459232780`.

Private application backups (not committed): workspace `backups/2026-11-04-ai-memory/`, including main/error/maintenance workflow exports and original food-memory rows. This is an application backup, not a full server image.

To install elsewhere: apply the migration, run its rollback SQL tests, run `node backend/tools/prepare-food-memory-fix.cjs`, and publish the changed main/error nodes. To revert, restore the backed-up workflow versions. Migration objects can remain unused; no history restoration or deletion is necessary.

The view intentionally has no DELETE trigger: the ordinary agent path only reads and appends. Future explicit memory deletion must target the original store through the existing authorized cleanup flow.
