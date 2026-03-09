---
"@flemma-dev/flemma.nvim": minor
---

Added experimental in-process LSP server for chat buffers with hover support. Enable with `experimental = { lsp = true }` in setup. Every buffer position returns a hover result: segments (expressions, thinking blocks, tool use/result, text) show structured dumps, role markers show message summaries with segment breakdowns, and frontmatter shows language and code. This is the foundation for future LSP features like goto-definition for includes.
