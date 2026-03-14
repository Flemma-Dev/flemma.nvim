---
"@flemma-dev/flemma.nvim": patch
---

Fixed parser producing per-line text segments for assistant and user messages, fixed text segments missing column positions causing wrong segment lookup, and fixed find_segment_at_position failing on multi-line segments where end_col belongs to a different line
