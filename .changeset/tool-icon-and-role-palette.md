---
"@flemma-dev/flemma.nvim": patch
---

Refreshed the default visuals:

- Tool fold icons now distinguish request from response: `⬡` (hollow hexagon) for tool_use and `⬢` (filled hexagon) for tool_result, replacing the shared `◆` glyph. Both share the `FlemmaToolIcon` highlight group.
- `@System` and `@You` messages now carry subtle background tints by default (`#101112` / `#202122`), making role transitions legible even when rulers are hidden. `@Assistant` stays on `Normal` so the eye rests on the LLM output.
- Thinking blocks softened to dark gray on near-black (`bg:#000000 fg:#333333`), replacing the prior teal-tinted palette.

Override any of these under `highlights.*` and `line_highlights.*` to restore the previous look.
