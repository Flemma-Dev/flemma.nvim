---
"@flemma-dev/flemma.nvim": patch
---

Fixed race condition where autopilot emitted "Tool … is already executing" during heavy tool use with mixed sync/async tools in the same response.
