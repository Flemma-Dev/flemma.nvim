---
"@flemma-dev/flemma.nvim": minor
---

Promoted LSP and exploration tools (find, grep, ls) out of experimental. LSP is now configured via `lsp = { enabled = true }` (top-level). The three exploration tools are enabled by default. The `experimental` config section is now empty and strict — any keys passed to it will produce a validation error.
