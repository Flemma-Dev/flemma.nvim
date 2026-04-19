---
"@flemma-dev/flemma.nvim": minor
---

Route all user-facing notifications through the new `flemma.notify` module, centralising dispatch, implicit `vim.schedule` wrapping, `once`-dedup, and lazy nvim-notify backend detection. All `vim.notify` callsites across 23 production files are migrated; spec files updated to use `notify._set_impl`/`_reset_impl` for test isolation.
