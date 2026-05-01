---
"@flemma-dev/flemma.nvim": minor
---

Added opt-in lualine segment `#{buffer.tokens.input}` showing projected input tokens for the next request, fetched via the active provider (Anthropic today) and debounced 2.5s after the user pauses editing. The default `statusline.format` now includes the segment with an `↑` marker; users with a custom `statusline.format` are unaffected unless they add the variable.

Internal: `try_estimate_usage(bufnr, on_result)` is now callback-mandatory — notify/format moved to the `:Flemma usage:estimate` command dispatcher so adapter implementations stay pure-data. New hook `usage:estimated` / `FlemmaUsageEstimated` fires when a buffer's token estimate changes.
