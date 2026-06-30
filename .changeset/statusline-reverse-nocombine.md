---
"@flemma-dev/flemma.nvim": patch
---

Fix statusline muted text rendering with colorschemes that use `reverse` on StatusLine (e.g., wildcharm). Derived groups now strip `reverse`/`bold`/`cterm` via `:pick()` and use `nocombine` to prevent attribute bleedthrough in `%#Group#` statusline escapes. Remove `ExpectOp` — replaced by `:pick(..., { strict = true })`.
