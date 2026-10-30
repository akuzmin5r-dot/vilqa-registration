# Telegram Rich Message statistics

## Follow-up: collapsed food details below totals

Moved the food quotation below the daily-summary table into a closed native details block, `🍽 Что съедено`. Restored timestamps as footer lines inside the quotation, once per successive time group, without arrows or meal labels. Empty days have no empty disclosure. The summary remains unchanged. Updated behavioral tests, observed the expected failure, then regenerated and passed the formatter suite. Execution `5884` verified a closed details block after the table, containing the food quotation and time; maintenance restored to two nodes. Version `ec713e8f-40f7-472a-bd50-746196895943`; backup `backups/2026-10-30-before-collapsed-food-list/stats.json`.

## Follow-up: food quotation

Wrapped the compact food paragraphs in one non-collapsible quotation, as requested. The daily summary stays outside it with its existing spacing. Updated the behavioral assertion, observed the expected failure and then regenerated the formatter; the targeted suite passes. Backup: `backups/2026-10-30-before-quoted-food-list/stats.json`.

## Follow-up: remove the food table

Phone feedback showed that even a three-column food table stretched each entry into four lines and left large empty areas. Removed the food table entirely: each product is a bold name plus weight, followed by a compact calorie/B/F/C line in the same paragraph. The aligned daily-summary table, bold labels, progress policy and spacing are unchanged.

Nine maintained suites passed. Execution `5879` delivered actual owner data as food paragraphs and exactly one totals table. Maintenance restored to two nodes. Version `72ca5628-87b2-434b-8a42-9f9df2fe02b6`; backup `backups/2026-10-30-before-simple-food-list/stats.json`. Supersedes the previous food-table designs.

## Follow-up: plain food table, no time and bold nutrient names

Removed the time column and striped table background. Food now has three columns (product, weight, K/B/F/C); calories, protein, fats and carbs occupy separate lines within the nutrient cell instead of wrapping one packed line. Summary labels (Calories, Protein, Fats, Carbs, Fiber) are bold, with their existing emoji outside the bold span. No arbitrary background/color styling was introduced.

Nine suites passed. Execution `5875` verified actual owner data through Telegram: three food columns, no `is_striped`, individual macro lines and native bold rich-text labels in the summary. Maintenance restored to two nodes. Version `84dac7b1-65e4-403f-8f78-9b8c77f1dcb4`; backup `backups/2026-10-30-before-plain-food-table/stats.json`. Supersedes previous striped/time-column layout.

## Follow-up: aligned tables, fiber goal and bot-wide button policy

Food is now one compact striped table with separate time, product, weight and K/B/F/C cells. Product names are bold; long names are escaped and whole rows are capped within Telegram limits. The daily summary is one three-column table with full blank spacer rows after calories and before fiber, so all five nutrient rows share column sizing. Native dividers and meal quotations were removed. Calorie balance remains directly under its progress bar.

Fiber is a goal-oriented meter: known zero is four white squares; any positive amount fills at least one square; below 50% is red, from 50% to below 100% is yellow, at/above 100% is green. Filled fiber squares use ceiling to show that measurement has begun. Calorie/B/F/C progress retains completed-quarter filling and its previous excess thresholds. Pending or incomplete fiber has no estimated progress bar.

Button styling is generated from `src/button-policy.cjs` for every Telegram inline keyboard in the main and API workflows. Diary opening and write/save actions are green; cancellation is red; everything else is default, including delete, registration, profile and recommendations. Dynamic expressions evaluate the same classifier against actual rendered labels and callback actions, including revision-prefixed callbacks. The outgoing style is authoritative and overrides historical styles in cached navigation payloads; no database migration is needed. Policy saved in n8n user preferences (`e70e1c28-ccf5-443d-8b27-da42aa13bed6`). Other active workflows were inspected and have no inline keyboards.

Nine maintained suites passed, including generated-style drift, dynamic expression execution, diary/cancel/default scenarios and fiber boundaries at 0, 0.1, 25, 49.9, 50, 75, 99.9, 100 and 150 percent. All 30 modified node configurations validated. Execution `5811`, message `4456`, confirmed native striped food rows, the single aligned totals table with blank rows and red partial fiber, plus green diary/default recommendations. Dynamic keyboard message `4457` confirmed green save, red cancel and an unstyled statistics button; it was deleted after verification in execution `5814`. Maintenance returned to its original two nodes. Published parameters compared with local canonical exports. No diary data changed.

Versions: main `e6f28dd7-84e5-4ca8-89ce-61fa2777cc31`, API `b343f0fe-8abd-4cc2-8568-4c7deccb6b4f`, statistics `5a0c7a47-1e2c-4919-8d75-a6b8edd3ea52`. Backups: workspace `backups/2026-10-30-before-tables-buttons/`.

Telegram offers compact/bordered/striped table properties, but no arbitrary background color. The stripe color is chosen by the client/theme, not the VILQA brand palette. This section supersedes earlier table, fiber and button styling descriptions.

## Follow-up: progress logic audit and spacing

Audit found conflicting yellow semantics (low protein versus excess calories/fats/carbs) and rounding that displayed four squares at 87.5%. All calorie/B/F/C rows now share green through 100%, yellow above 100% through 120%, red above 120%. These are UI thresholds, not health-risk judgments. Fiber remains green toward/above its target and suppresses progress for pending/incomplete data. Filled squares represent completed 25% increments (`floor`, capped at four), so zero filled squares can mean less than 25%, not missing records; exact numbers remain visible.

Restored the remaining calories directly under the calorie progress bar in its cell. Removed the timestamp arrow, keeping time before food inside its quotation. Added one blank paragraph after the title and one before the calorie table. Retained native dividers.

Updated behavioral tests first and observed failure, then regenerated the workflow. Eight maintained suites passed; new integration assertions cover all calorie/B/F/C rows at 0%, 24.9%, 25%, 50%, 75%, 99.9%, 100%, 101%, 120% and 120.1%. Execution `5649`, message `4455`, confirmed actual owner data, both spacer paragraphs and the multiline calorie cell in Telegram. Maintenance restored to two nodes and published source verified against local formatter. Version `977353eb-fcb1-4362-a6e9-bac1a6d36fb3`; backup `backups/2026-10-30-before-progress-audit/stats.json`. Supersedes earlier layout/color notes.

## Follow-up: native dividers and plain heading

Replaced the article heading with a standard bold paragraph, `📊 Статистика • [date] 🍴`. Meal timestamps now end with the Unicode down arrow. Totals use three headerless tables (calories, B/F/C, fiber) separated by two native dividers. Remaining calories are a native footer directly below the calorie table, providing secondary typography controlled by the Telegram client/theme; the API has no custom opacity/color option. Separate tables may size their columns independently in clients.

Updated behavioral tests first, observed the expected failure, then regenerated the canonical workflow. Eight maintained suites passed. Execution `5645`, message `4454`: actual owner data delivered; Telegram returned a bold paragraph, timestamp footer `11:12 ↓`, three tables, two dividers and the separate remainder footer. No diary writes. Maintenance restored to two nodes and live formatter verified against local code. Published statistics version `2a6d0593-5152-4dc0-a564-19370d3e3969`; backup in workspace `backups/2026-10-30-before-statistics-dividers/stats.json`. This layout supersedes earlier notes below.

## Follow-up: headerless table and calorie progress

Removed table headers. Calories now have the same four-square progress indicator as the other rows; the remaining calories appear below it in the same cell as `Ещё … ккал`, or `Сверх … ккал` for excess. Cell text remains escaped before newline-to-break conversion. Existing meal blocks and nutrient semantics are unchanged.

Behavior test updated first and failed as expected, then the canonical formatter and generated workflow were updated. Eight maintained suites passed. Execution `5639` delivered actual owner data; Telegram confirmed no header cells and a multiline calorie progress/remainder cell. Maintenance returned to two nodes; live formatter matches local source. Published version `098f7b1a-fd65-4b5d-9ef7-fef47f3a0ac6`; backup in workspace `backups/2026-10-30-before-headerless-statistics/stats.json`. This layout supersedes the previous notes below.

## Follow-up: compact table and timestamps

Removed meal-count headings, meal-type labels, standalone time headings and the fiber disclaimer. Time is now a small footer inside each meal quotation. One compact table contains calories (actual / target, remaining or excess in column three) and nutrient rows (actual / target, four-square progress in column three). All header cells explicitly align left. Known zero, unknown and pending fiber stay distinct; pending/incomplete fiber has no progress estimate. Protein uses yellow below 70%, then green; fats/carbs use yellow over 100% and red over 120%, matching the previous statistics semantics. Fiber progress stays green toward its target.

Updated the formatter behavior test first and observed the expected failure, then changed the canonical source and regenerated the statistics node. Eight maintained suites passed, including progress overflow/zero checks. Execution `5634`, Telegram message `4452`: actual October 30 owner data delivered successfully; Telegram returned left-aligned header cells, four-square bars, and the timestamp footer nested inside a blockquote. Maintenance restored to two nodes; published formatter compared against local code. No diary changes.

Published statistics version: `d607f04b-e1ee-414d-b59b-6b3a6ad565ef`. Backup: workspace `backups/2026-10-30-before-compact-statistics/stats.json`. This section supersedes previous layout notes below.

## Follow-up: visible food list

User feedback: the collapsed list hid the essential information and the message looked too sparse. Meals now appear before daily totals, always expanded, with clock headings and quoted product blocks containing weight, calories and B/F/C grams. Added emoji to section headings and nutrient rows. Tables and the existing buttons remain.

Updated the behavioral test first and confirmed failure on the collapsed layout, then changed the canonical formatter and regenerated its workflow. All eight maintained suites pass. Execution `5624` sent actual owner data for October 30 as native rich blocks: chicken and rice are present inside a non-collapsible blockquote before the totals table. Telegram message `4451`; no fictional records and no diary writes. Maintenance restored to its two original nodes. Live code verified against the generated formatter.

Published statistics version: `3bf66d1e-e2db-4d1c-8f84-dc7649350bab`. Backup: workspace `backups/2026-10-30-before-visible-statistics/stats.json`. This section supersedes the original collapsed-list layout below.

Daily statistics now use Telegram's native Rich Message format: a heading, integer calories and remaining amount, a compact B/F/C/fiber table, and collapsed meal details. Values come from the existing database snapshot; no model is involved. The existing diary, recommendation and main-menu buttons remain, including their styles. The intentional delay after saving food remains.

Both the main bot and Mini App recipe-portion notification use this format. A plain text summary remains available for the recommendation workflow. User text is escaped; long days are truncated by complete items within Telegram character/block limits, with a link via the diary button. Pending, incomplete, manual and estimated fiber values remain distinct.

## Transport limitation

The installed Telegram node supports `sendRichMessage`, but its `editMessageText` action does not forward `rich_message`. Tested against Telegram; extra collection fields were ignored. Fiber completion therefore still uses the existing separate, acknowledged delivery workflow. The article is a snapshot and does not automatically update when fiber finishes. No credential extraction or unsupported editing workaround was introduced.

## Verification

- Eight maintained suites passed, including the new formatter tests: escaping, empty/long days, integer calories, pending and unknown fiber.
- Execution 5607: final template accepted as native heading/table/details/footer blocks with styled buttons. Test message removed afterward.
- Execution 5609: real owner diary for 2026-10-26; native Rich Message 4450 delivered. No diary records changed.
- Execution 5617: read-only current-day fast path returned the correct date, profile targets and estimated fiber.
- Temporary maintenance nodes and earlier test messages removed; maintenance restored to its two original nodes.
- Live parameters verified against canonical local exports.

Published versions:

- Statistics: `0ed4be5b-c219-4a53-a2bc-4f7a3dd7ac88`
- Main: `954fd148-8c2f-4983-a0b6-84ff758c83e2`
- Diary API: `138b03ec-2a1c-4627-b31a-82a98cd7db68`

Pre-change workflow backups: workspace `backups/2026-10-30-before-rich-statistics/`. No SQL migration was needed; the snapshot queries read the existing fiber settings and diary columns.
