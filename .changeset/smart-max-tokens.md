---
"@flemma-dev/flemma.nvim": minor
---

Smart max_tokens: default is now "50%" (half the model's max output), percentage strings are resolved automatically, and integers exceeding the model limit are clamped with a warning. `:Flemma status` shows the resolved value alongside the percentage.
