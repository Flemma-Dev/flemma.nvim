---
"@flemma-dev/flemma.nvim": patch
---

Removed vestigial `reset()` from provider lifecycle — providers are request-scoped and single-use, so initialization is inlined into `new()` and the redundant pre-request reset in client.lua is removed
