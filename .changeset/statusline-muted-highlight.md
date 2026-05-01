---
"@flemma-dev/flemma.nvim": minor
---

Added `FlemmaStatusTextMuted` highlight group — a theme-neutral dim variant of `StatusLine` derived via Flemma's hl expression composer (`StatusLine±fg:#666666`). Use `%#FlemmaStatusTextMuted#…%*` in `statusline.format` to dim fragments while keeping the statusline background continuous.

When rendered through the bundled lualine component, both escapes are auto-rewritten at render time so they anchor to the active section hl rather than plain `StatusLine`:

- `%*` → section's default hl (restores `lualine_c_normal` etc. instead of falling back to `StatusLine`)
- `%#FlemmaStatusTextMuted#` → a memoised render-time group combining the section's bg with the muted fg, so embedded muted text keeps bg continuity across mode tints

The render-time group is cached on the component and only re-set when the section bg or muted fg actually changes (mode switch or colorscheme), keeping the statusline redraw hot path cheap. Outside lualine, both escapes pass through untouched — vim handles `%*` natively and the static `FlemmaStatusTextMuted` group (anchored to `StatusLine.bg`) is used directly.

The shipped `statusline.format` default now surfaces session request count + cost and the buffer token estimate alongside the model name, with muted separators between segments. See `lua/flemma/config/schema.lua` for the literal list; users with a custom `statusline.format` are unaffected.
