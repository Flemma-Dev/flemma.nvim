---
"@flemma-dev/flemma.nvim": patch
---

Fixed silent failure when API returns non-SSE error responses (plain JSON, HTML error pages, or plain text). Errors are now properly surfaced via vim.notify instead of being silently swallowed.
