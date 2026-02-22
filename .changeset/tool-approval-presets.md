---
"@flemma-dev/flemma.nvim": minor
---

Added tool approval presets for zero-config agent loops. Flemma now ships with `$readonly` and `$default` presets. The default `auto_approve` is `{ "$default" }`, which auto-approves `read`, `write`, and `edit` while keeping `bash` gated behind manual approval. Users can define custom presets in `tools.presets` and reference them in `auto_approve`. Frontmatter supports `flemma.opt.tools.auto_approve:remove("$default")` and `:remove("read")` for per-buffer overrides.
