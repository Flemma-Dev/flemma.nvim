---
"@flemma-dev/flemma.nvim": minor
---

Added `@~/path` file reference syntax for home-directory relative paths, alongside the existing `@./` and `@../`. The `~` is expanded at evaluation time, keeping `.chat` files portable across machines.
