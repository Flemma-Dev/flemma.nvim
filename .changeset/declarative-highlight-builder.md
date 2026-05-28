---
"@flemma-dev/flemma.nvim": minor
---

Replace string-based highlight DSL with composable `flemma.hl` builder API. All highlight construction — config defaults and internal derivations — now uses lazy ops (`h.link`, `h.from`, `h.themed`, `h.coalesce`, `h.diff`, `h.attrs`, `h.hex`) with chainable methods (`:blend`, `:pick`, `:omit`, `:contrast`, `:tint`, `:mute`, `:style`, `:merge`) and terminal `:get()`/`:set()`. The old string syntax (`"Normal+bg:#101010"`, `"Folded!bg"`, `{ dark = "...", light = "..." }`) is removed entirely. `highlights.role_style` replaced by `highlights.role_name` (an HlOp). `highlights.defaults` removed.
