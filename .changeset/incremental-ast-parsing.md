---
"@flemma-dev/flemma.nvim": patch
---

Optimized AST parsing during streaming: the parser now snapshots the document before a request and only re-parses newly appended content during streaming, reducing per-chunk parse cost from O(total_lines) to O(new_content_lines) for long conversations.
