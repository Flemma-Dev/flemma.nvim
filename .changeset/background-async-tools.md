---
"@flemma-dev/flemma.nvim": minor
---

Added background job support for async tools. Any async tool can now run in the background without blocking the conversation, with completions delivered as appended `@You` blocks when the conversation reaches idle.

- Auto-injected a `background` parameter into async tool schemas
- Added `:Flemma tool:background` and `<M-b>` for mid-flight backgrounding
- Added `conversation:idle` and `job:completed` hooks
- Added orphan detection and recovery for interrupted background jobs
