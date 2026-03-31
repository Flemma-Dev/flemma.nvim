---
"@flemma-dev/flemma.nvim": minor
---

`<Space>` now toggles the entire message fold instead of the fold under the cursor. Nested folds (thinking, tool use/result) are closed along the way so the message reopens cleanly. Frontmatter folds are also toggled when the cursor is outside any message. Use `za` for the previous per-fold toggle behavior.
