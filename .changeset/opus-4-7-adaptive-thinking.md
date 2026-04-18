---
"@flemma-dev/flemma.nvim": minor
---

Added support for Claude Opus 4.7 (`claude-opus-4-7`) with adaptive thinking. Opus 4.7 is adaptive-only (manual `budget_tokens` is rejected), and its default thinking display is `"omitted"` — Flemma now sends `display: "summarized"` explicitly on all adaptive requests so thinking text is returned.
