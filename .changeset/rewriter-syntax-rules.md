---
"@flemma-dev/flemma.nvim": minor
---

Preprocessor rewriter modules can now declare their own Vim syntax rules and highlight groups via `get_vim_syntax(config)`, removing the need to modify the main syntax file when adding new rewriters.
