---
"@flemma-dev/flemma.nvim": patch
---

Fixed parser treating inline fenced code (e.g., ` ```markdown Hello!``` `) as fence openers, which caused subsequent @Role: markers to be missed
