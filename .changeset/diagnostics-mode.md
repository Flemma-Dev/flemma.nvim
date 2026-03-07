---
"@flemma-dev/flemma.nvim": minor
---

Added diagnostics mode for debugging prompt caching issues. When enabled via `diagnostics = { enabled = true }`, Flemma compares consecutive API requests per buffer and warns when the prefix diverges (breaking caching). Includes byte-level analysis, structural change detection, and a side-by-side diff view (`:Flemma diagnostics:open`).
