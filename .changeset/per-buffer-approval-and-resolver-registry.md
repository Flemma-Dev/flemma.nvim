---
"@flemma-dev/flemma.nvim": minor
---

Added approval resolver registry and per-buffer approval via frontmatter. Tool approval is now driven by a priority-based chain of named resolvers – global config, per-buffer frontmatter (`flemma.opt.tools.auto_approve`), and custom plugin resolvers are all evaluated in order. Consolidated tool documentation into `docs/tools.md`.
