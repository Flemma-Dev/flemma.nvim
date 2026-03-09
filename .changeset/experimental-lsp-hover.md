---
"@flemma-dev/flemma.nvim": minor
---

Added experimental in-process LSP server for chat buffers with hover support. Enable with `experimental = { lsp = true }` in setup. Hovering over any AST node (expressions, thinking blocks, tool use/result, text) shows a structured dump of the segment, proving correct cursor-to-node detection. This is the foundation for future LSP features like goto-definition for includes.
