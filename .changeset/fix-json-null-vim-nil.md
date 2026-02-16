---
"@flemma-dev/flemma.nvim": patch
---

Fixed JSON null values decoding as vim.NIL (truthy userdata) instead of Lua nil, causing crashes in tool definitions when LLMs send null for optional parameters like offset, limit, timeout, and delay
