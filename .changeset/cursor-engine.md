---
"@flemma-dev/flemma.nvim": minor
---

Added centralized cursor engine with focus-stealing prevention. System-initiated cursor moves (tool results, response completion, autopilot) are now deferred until user idle, preventing cursor hijacking during agent loops. User-initiated moves (send, navigation) execute immediately.
