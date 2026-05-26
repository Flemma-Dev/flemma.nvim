---
"@flemma-dev/flemma.nvim": patch
---

Fence overlay extmarks are now only shown when conceallevel >= 2; toggling conceal off reveals raw ``` delimiters. Markdown buffers in the same session regain native fence concealing via automatic highlighter restoration.
