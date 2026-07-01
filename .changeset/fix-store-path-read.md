---
"@flemma-dev/flemma.nvim": patch
---

Fixed `read`/`write`/`edit` so `$FLEMMA_TOOLS_STORE_PATH/<file>` resolves to the buffer's store directory — the same place `flemma.save_to` writes. Previously a tool could save a file with `flemma.save_to: "$FLEMMA_TOOLS_STORE_PATH/…"` and then get "File not found" reading it back.
