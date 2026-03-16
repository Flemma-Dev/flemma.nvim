---
"@flemma-dev/flemma.nvim": patch
---

Fixed preprocessor runner producing structurally different ASTs for untouched text segments by adding a pre-scan early return and accumulating non-matching lines into single segments instead of splitting per-line
