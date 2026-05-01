---
"@flemma-dev/flemma.nvim": patch
---

Fixed preset parameter merge bypassing schema coercion (e.g., `thinking = "low"` staying as a raw string instead of being normalized to `{ level = "low", foreign = "preserve" }`)
