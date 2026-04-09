---
"@flemma-dev/flemma.nvim": minor
---

Added `mime.detect(filepath)` as the single public entry point for MIME detection — tries extension-based lookup first, falls back to the `file` command. Added `mime.is_binary(mime_type)` for classifying MIME types as binary vs textual. The previous `get_mime_type()` and `get_mime_by_extension()` methods are now internal.
