---
"@flemma-dev/flemma.nvim": patch
---

Notification recall now derives segments from session data on demand instead of caching them locally, enabling `:Flemma notification:recall` to work after importing a session via `session:load()`
