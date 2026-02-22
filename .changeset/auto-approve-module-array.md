---
"@flemma-dev/flemma.nvim": minor
---

`tools.auto_approve` now accepts a `string[]` of module paths (and mixed module paths + tool names). Internal approval resolver names use `urn:flemma:approval:*` convention; module-sourced resolvers are addressable by their module path directly.
