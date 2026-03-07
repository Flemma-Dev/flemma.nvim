---
"@flemma-dev/flemma.nvim": patch
---

Fixed missing warning when pressing `<C-]>` while a request is already in progress — the keypress was silently ignored instead of showing the "Use `<C-c>` to cancel" message
