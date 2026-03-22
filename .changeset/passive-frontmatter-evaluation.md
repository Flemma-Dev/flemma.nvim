---
"@flemma-dev/flemma.nvim": minor
---

Passively evaluate frontmatter on InsertLeave, TextChanged, and BufEnter so integrations like lualine see up-to-date config values without waiting for a request send. On error, the last successful frontmatter parse is preserved.

Refactored `config.finalize()` to return validation failures as data instead of accepting a reporter callback, making codeblock parsers pure data functions with no `vim.notify` side effects. Callers now decide when and how to surface diagnostics.

`:Flemma status` renders frontmatter diagnostics (parse errors, runtime errors, and validation failures) as DiagnosticError lines in the status buffer.
