---
"@flemma-dev/flemma.nvim": minor
---

Added automatic handling of aborted responses: when a user cancels (`<C-c>`) mid-stream after tool_use blocks, orphaned tool calls are now automatically resolved with error results instead of triggering the approval flow. The abort marker (`<!-- flemma:aborted: message -->`) is preserved for the LLM on the last text-only assistant message so it can continue contextually.
