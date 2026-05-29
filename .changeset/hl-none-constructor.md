---
"@flemma-dev/flemma.nvim": minor
---

Add `h.none()` to the `flemma.hl` highlight builder — a no-op op whose `:get()` resolves to nothing and `:set()` does nothing. Use it as a config value to leave a highlight group unmanaged by Flemma (e.g. `highlights = { thinking_tag = h.none() }`), so the colorscheme or your own definition stands.
