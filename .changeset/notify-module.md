---
"@flemma-dev/flemma.nvim": patch
---

Routed all internal notifications through the new `flemma.notify` module — centralising dispatch, implicit `vim.schedule` wrapping, `once`-dedup, and lazy nvim-notify backend detection. Users with rcarriga/nvim-notify installed automatically get rich notifications (titles, icons, replace-in-place, dedup); users on vanilla `vim.notify` see no behavior change.
