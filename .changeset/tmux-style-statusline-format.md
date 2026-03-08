---
"@flemma-dev/flemma.nvim": minor
---

Added tmux-style format strings for the lualine statusline component. The new `statusline.format` config replaces `thinking_format` with a composable syntax supporting variable expansion (`#{model}`, `#{provider}`, `#{thinking}`), ternary conditionals (`#{?cond,true,false}`), string comparisons, and boolean operators. Variables are lazy-evaluated — only referenced variables trigger data lookups.
