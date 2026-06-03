---
"@flemma-dev/flemma.nvim": minor
---

Auto-scroll viewport during streaming responses. The cursor follows new content to the bottom (tail mode), disengages when the user moves away (breakaway), and re-engages when the user navigates back to the last line (re-attach). All non-forced cursor moves respect breakaway state so the user can freely explore the buffer during autopilot.
