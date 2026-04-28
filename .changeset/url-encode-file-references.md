---
"@flemma-dev/flemma.nvim": patch
---

Fixed file references with spaces in filenames (e.g., `image (1).png`) breaking the preprocessor — the read tool now URL-encodes paths before emitting `@./path;type=mime` references
