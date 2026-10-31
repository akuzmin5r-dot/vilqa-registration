# Default food-entry menu button

The main-menu `Записать еду` button opens navigation rather than saving a record, so it now uses Telegram's default style. Actual meal confirmation/restoration and save actions remain green; diary opening stays green; cancellation stays red. Updated the shared classifier and generated both static/dynamic renderer parameters. Stored the exception in the existing n8n user preference.

Behavioral tests cover plain and revision-prefixed menu actions, label fallback, and the unchanged save/cancel/default policy. The test failed before the classifier change and passed afterward; generated workflow checks pass. All 19 affected Telegram node configurations validated. Backup: workspace `backups/2026-10-31-before-menu-food-default/main.json`. Existing chat messages retain their prior keyboard until Telegram receives a new/edited menu.
