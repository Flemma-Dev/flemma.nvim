---
"@flemma-dev/flemma.nvim": minor
---

`statusline.format` now accepts either a single string or a list of strings. When a list is provided, entries are concatenated with `""` at render time, letting you break the default into readable pieces without manual `table.concat` calls.
