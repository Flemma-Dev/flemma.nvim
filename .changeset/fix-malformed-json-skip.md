---
"@flemma-dev/flemma.nvim": patch
---

Fixed parser bug where malformed JSON in a tool_use block caused all subsequent tool_use blocks in the same message to be skipped.
