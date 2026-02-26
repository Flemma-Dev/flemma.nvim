---
"@flemma-dev/flemma.nvim": patch
---

Fixed pending tool blocks with user-provided content being silently discarded. When a user pastes output into a `flemma:tool status=pending` block and presses `<C-]>`, the content is now accepted as the tool result and sent to the provider instead of being replaced by a synthetic error.
