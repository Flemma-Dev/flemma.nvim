---
"@flemma-dev/flemma.nvim": minor
---

Added `mime.detect()` and `mime.is_binary()` utility methods. `detect()` consolidates MIME detection strategy — extension-based lookup first, falling back to the `file` command. `is_binary()` classifies a MIME type as binary vs textual. Migrated `eval.lua`'s inline `detect_mime()` to use `mime.detect()`.
