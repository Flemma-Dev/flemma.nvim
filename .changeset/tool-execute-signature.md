---
"@flemma-dev/flemma.nvim": minor
---

Changed tool execute function signature from `(input, callback, ctx)` to `(input, ctx, callback?)` — sync tools no longer need a placeholder `_` argument, and callback-last ordering matches Node.js conventions
