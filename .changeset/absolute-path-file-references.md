---
"@flemma-dev/flemma.nvim": minor
---

Added `@//path` file reference syntax for absolute paths — `@//tmp/image.png` resolves to `/tmp/image.png`. The read tool now emits `@//` references for absolute paths instead of incorrectly prepending `./`.
