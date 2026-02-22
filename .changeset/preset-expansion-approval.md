---
"@flemma-dev/flemma.nvim": minor
---

Auto-approve policy now expands $-prefixed preset references, allowing `auto_approve = { "$default", "$readonly" }` to union approve/deny lists from the preset registry. Config-level resolvers defer to frontmatter when it sets auto_approve, enabling per-buffer override of global presets.
