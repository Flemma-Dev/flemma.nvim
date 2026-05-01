---
"@flemma-dev/flemma.nvim": minor
---

Added `editing.conceal` with default `"2nv"` — Flemma now hides markdown syntax (bold, italic, link markers, etc.) in chat windows while reading or selecting, and reveals it when you move the cursor onto a line in Insert or Command mode. The value is a compact `{conceallevel}{concealcursor}` string; set it to `false` to opt out and keep whatever conceal settings your colorscheme/config provides. See `docs/conceal.md` for the format and the intentionally-unfixed `line_highlights` + `Conceal` interaction (a Neovim drawline design, documented inline).

This is the first of a series of "reduce noise by default" changes — chat buffers already carry role markers, tool blocks, thinking blocks, rulers, and usage bars; removing visible markdown markup on top of that makes assistant prose much easier to read. The old behaviour is one line away: `editing = { conceal = false }`.
