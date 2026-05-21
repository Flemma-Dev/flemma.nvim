---
"@flemma-dev/flemma.nvim": patch
---

Bash tool now sets terminal scrollback to `-1` (Neovim's maximum) instead of a hardcoded `100000`, automatically using the highest supported value for the running Neovim version.
