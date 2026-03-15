---
"@flemma-dev/flemma.nvim": minor
---

Added template code blocks (`{% lua code %}`) for conditionals, loops, and logic in @System and @You messages. Added optional whitespace trimming (`{%- -%}`, `{{- -}}`). Added parameterized includes: `include('file.md', { name = "Alice" })`. Included files now support full template syntax at any depth. Binary include mode now uses symbol keys (`[symbols.BINARY]`, `[symbols.MIME]`) instead of reserved string keys, so `binary` and `mime` can be used as template variable names.
