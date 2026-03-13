---
"@flemma-dev/flemma.nvim": patch
---

Fixed cross-buffer personality environment leak where a background buffer's system prompt could pick up the focused buffer's cached date/time during tool-calling loops
