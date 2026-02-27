---
"@flemma-dev/flemma.nvim": patch
---

Fixed E565 textlock errors when visual-mode plugins (e.g., targets.vim) hold textlock while streaming responses complete. All async buffer modifications now go through a per-buffer FIFO write queue that retries on textlock.
