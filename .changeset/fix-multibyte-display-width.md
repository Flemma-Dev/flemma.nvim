---
"@flemma-dev/flemma.nvim": patch
---

Fixed preview truncation (fold text, tool indicators) using byte length instead of display width, which caused incorrect truncation and potential UTF-8 splitting with multibyte content (CJK, accented characters, Unicode symbols)
