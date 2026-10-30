# Telegram Rich Message statistics

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
