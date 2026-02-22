---
"@flemma-dev/flemma.nvim": minor
---

Refactor tool definitions to use ExecutionContext SDK — tools now code against `ctx.path`, `ctx.sandbox`, `ctx.truncate`, and `ctx:get_config()` instead of requiring internal Flemma modules directly
