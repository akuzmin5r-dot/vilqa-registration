# Telegram Rich Message statistics

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
