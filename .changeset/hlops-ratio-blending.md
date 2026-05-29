---
"@flemma-dev/flemma.nvim": minor
---

HlOps `tint`, `mute`, and `blend` now accept an optional ratio parameter and an HlOp color source, enabling expressions like `h.from("Normal"):tint("bg", h.from("DiagnosticWarn"):pick("fg"), 0.10)`
