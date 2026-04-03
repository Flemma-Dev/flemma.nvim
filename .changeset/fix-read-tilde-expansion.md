---
"@flemma-dev/flemma.nvim": patch
---

Fixed read tool failing on `~/` paths: `ctx.path.resolve()` now expands `~` via `vim.fn.expand()`, and binary file references derived from `~` paths are converted to correct relative `@./` references from the buffer directory.
