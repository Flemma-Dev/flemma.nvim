---
"@flemma-dev/flemma.nvim": minor
---

Add `:tint(attr, hex)` and `:mute(attr, hex)` theme-aware blend methods to the `flemma.hl` builder. `:tint()` offsets away from the theme background (making colours more distinct), `:mute()` offsets toward it (making colours more subdued). Both automatically flip blend direction based on `vim.o.background`, replacing verbose `h.themed()` + flipped `+`/`-` patterns with single-line calls.
