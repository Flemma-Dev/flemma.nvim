---
"@flemma-dev/flemma.nvim": minor
---

Fold previews now show tool labels (the LLM's stated intent) prominently, with raw technical detail visually subordinate.

Tool `format_preview` functions can now return `{ label?, detail? }` instead of a plain string. Built-in tools (bash, read, write, edit, grep, find, ls) have been updated to use the structured return. String-returning `format_preview` functions are fully backward-compatible. New highlight groups `FlemmaToolLabel` (italic) and `FlemmaToolDetail` (default: Comment) style the two pieces independently.
