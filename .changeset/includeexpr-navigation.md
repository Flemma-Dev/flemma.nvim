---
"@flemma-dev/flemma.nvim": minor
---

Added `gf` navigation for file references and include expressions in chat buffers. Cursor on `@./file` or `{{ include('path') }}` and press `gf` to open the file or `<C-w>f` for a split. Paths are resolved using the same logic as the expression evaluator, including frontmatter variables and buffer-relative resolution.
