---
"@flemma-dev/flemma.nvim": minor
---

Added `<Space><Space>` keymap to toggle conceallevel between the configured level and 0 in chat buffers. Configurable via `keymaps.normal.conceal_toggle`; only registered when `editing.conceal` is active. The toggle re-opens the frontmatter fold to prevent it from auto-collapsing during the transition.
