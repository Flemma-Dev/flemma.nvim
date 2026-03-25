---
"@flemma-dev/flemma.nvim": minor
---

Added `print()` support in template code blocks — `{% print("text") %}` now emits directly into the template output instead of going to stdout. Arguments are concatenated with no separators and no trailing newline, giving full whitespace control to the template author.
