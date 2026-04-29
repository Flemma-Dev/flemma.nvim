---
"@flemma-dev/flemma.nvim": patch
---

Fixed `thinking = false` on OpenAI reasoning models to send `reasoning.effort = "none"` instead of silently defaulting to the model's default effort level
