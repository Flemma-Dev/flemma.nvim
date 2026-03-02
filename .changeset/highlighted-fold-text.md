---
"@flemma-dev/flemma.nvim": minor
---

Added per-segment syntax highlighting to fold text lines. Fold lines now return `{text, hl_group}` tuples so each part (icon, title, tool name, preview, line count) uses its own highlight group. New config keys: `tool_icon`, `tool_name`, `fold_preview`, `fold_meta`. Renamed `tool_use` to `tool_use_title` and `tool_result` to `tool_result_title` for 1:1 correspondence with highlight groups. Added shared `roles.lua` utility for centralised role name mapping.
