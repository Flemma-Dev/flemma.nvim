---
"@flemma-dev/flemma.nvim": minor
---

Highlight config fields now accept plain strings: a group name coerces to `h.link()`, a `#RRGGBB` hex value coerces to `h.hex()`. This removes the need to `require("flemma.hl")` for simple overrides.
