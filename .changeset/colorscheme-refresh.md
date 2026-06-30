---
"@flemma-dev/flemma.nvim": patch
---

Highlight groups now refresh automatically when switching colorschemes mid-session. A `ColorScheme` autocmd re-runs `apply_syntax()`, and since builder operations resolve lazily with no cache, all groups pick up the new colorscheme's colours immediately.
