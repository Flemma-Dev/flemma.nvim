---
"@flemma-dev/flemma.nvim": patch
---

Fixed the first diagnostic line collapsing onto the `Flemma:` title when the request is blocked by multiple diagnostics. The diagnostic renderer now starts with a leading blank so the prefix sits on its own line above the list.
