---
"@flemma-dev/flemma.nvim": patch
---

Refreshed the default visuals:

- Tool fold icon changed from `◆` to `◉` across tool_use and tool_result folds — slightly heavier glyph that reads better at small sizes.
- `@System` and `@You` messages now carry subtle background tints by default (`#101112` / `#202122`), making role transitions legible even when rulers are hidden. `@Assistant` stays on `Normal` so the eye rests on the LLM output.
- Thinking blocks softened to dark gray on near-black (`bg:#000000 fg:#333333`), replacing the prior teal-tinted palette.

Override any of these under `highlights.*` and `line_highlights.*` to restore the previous look.
