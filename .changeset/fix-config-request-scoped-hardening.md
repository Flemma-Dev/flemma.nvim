---
"@flemma-dev/flemma.nvim": patch
---

Fixed per-buffer config layer edge cases: frontmatter ops now release memory on buffer delete, provider switch notification detects higher-priority overrides, and secrets invalidation is scoped to user-initiated switches only
