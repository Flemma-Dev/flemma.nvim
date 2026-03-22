---
"@flemma-dev/flemma.nvim": patch
---

Fixed diagnostics accumulating across repeated requests (doubling, tripling, etc.) due to mutating the AST snapshot's error list in-place.
