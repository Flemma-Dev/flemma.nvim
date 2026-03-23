---
"@flemma-dev/flemma.nvim": patch
---

Fixed race condition where autopilot emitted "Cannot send while tool execution is in progress" when an LLM response contained both sync and async tool_use blocks.
