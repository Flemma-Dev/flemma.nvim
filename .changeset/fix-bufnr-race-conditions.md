---
"@flemma-dev/flemma.nvim": patch
---

Fixed race conditions where nvim_get_current_buf() could resolve to the wrong buffer during async operations
