---
"@flemma-dev/flemma.nvim": minor
---

Added inline rejection popup that replaces `vim.ui.input` for tool rejection feedback. The floating window overlays the tool result fence block with `╌` borders, supports multi-line editing via Vim motions, and is fully configurable (`ui.rejection.enabled`, `ui.rejection.winblend`, `highlights.rejection_input`, `highlights.rejection_border`). Set `ui.rejection.enabled = false` to revert to the original command-line prompt.
