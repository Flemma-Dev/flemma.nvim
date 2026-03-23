---
"@flemma-dev/flemma.nvim": patch
---

Fixed auto_write crashing when an external process modifies the .chat file on disk mid-request, which left autopilot and request state broken
