---
"@flemma-dev/flemma.nvim": minor
---

Added treesitter-powered syntax highlighting for tool preview virt_lines. Bash commands now render with per-token syntax coloring. Any tool can opt in by returning `highlight = { lang = "language_name" }` from its `format_preview` method. Falls back silently to flat highlighting when the treesitter grammar is unavailable.
