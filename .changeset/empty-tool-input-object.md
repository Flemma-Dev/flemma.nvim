---
"@flemma-dev/flemma.nvim": patch
---

Fixed empty tool input encoding as `[]` instead of `{}` — the Anthropic streaming response sends no input deltas for empty tool input, causing the sink to read as `""` which failed JSON decode and fell back to an untagged `{}` that encoded as `[]`
