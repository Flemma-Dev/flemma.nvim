---
"@flemma-dev/flemma.nvim": patch
---

HTTP request body files no longer litter `/tmp`. The client wrote every request body via `os.tmpname()`, which on LuaJIT `mkstemp()`s a `/tmp/lua_XXXXXX` file that nothing ever removed (one leaked, empty file per request), and the `flemma_lua_*` body beside it — world-readable — survived whenever Neovim was killed before the request's `on_exit` fired. Bodies now live in Neovim's private per-instance temp directory (`vim.fn.tempname()`, mode 0700), which Neovim removes wholesale on exit.
