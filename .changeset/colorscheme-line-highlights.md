---
"@flemma-dev/flemma.nvim": patch
---

Fix line highlight groups (`FlemmaLine*`) being lost after a colorscheme change. Groups are now re-established on every `apply_syntax()` call instead of once at setup time.
