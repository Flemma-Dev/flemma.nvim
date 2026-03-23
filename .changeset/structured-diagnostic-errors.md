---
"@flemma-dev/flemma.nvim": patch
---

Improved diagnostic error messages: config proxy, eval, and JSON parser errors now use structured error tables instead of plain strings, producing cleaner user-facing output without noisy Lua source locations and redundant context wrappers.
