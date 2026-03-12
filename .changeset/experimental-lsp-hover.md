---
"@flemma-dev/flemma.nvim": minor
---

Added experimental in-process LSP server for chat buffers with hover and goto-definition support. Enable with `experimental = { lsp = true }` in setup. Every buffer position returns a hover result: segments (expressions, thinking blocks, tool use/result, text) show structured dumps, role markers show message summaries with segment breakdowns, and frontmatter shows language and code. Goto-definition (`gd`, `<C-]>`, etc.) on `@./file` references and `{{ include() }}` expressions jumps to the referenced file, reusing the navigation module's path resolution.
