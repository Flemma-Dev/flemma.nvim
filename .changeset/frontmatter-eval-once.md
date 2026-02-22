---
"@flemma-dev/flemma.nvim": patch
---

Frontmatter is now evaluated exactly once per dispatch cycle instead of 2N+2 times (where N = number of tool calls), reducing redundant sandbox executions and preventing potential side-effects from repeated evaluation.
