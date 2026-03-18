---
"@flemma-dev/flemma.nvim": minor
---

Fold previews now show tool labels (the LLM's stated intent) prominently, with raw technical detail visually subordinate.

Tool `format_preview` functions can now return `{ label?, detail? }` instead of a plain string, where `detail` may be a `string[]` (joined with double-space upstream for uniform display). Built-in tools (bash, read, write, edit, grep, find, ls) have been updated to use the structured return. String-returning `format_preview` functions are fully backward-compatible. New highlight groups `FlemmaToolLabel` (italic) and `FlemmaToolDetail` (default: Comment) style the two pieces independently. Label and detail are separated by an em-dash (`—`) in both folds and tool preview virtual lines.
