---
"@flemma-dev/flemma.nvim": minor
---

Unified presets: `config.tools.presets` merged into top-level `presets`. Presets can now carry `provider`, `model`, `parameters`, and `auto_approve` fields — enabling composite presets like `$explore` that switch both model and tool approval in one `:Flemma switch` call. Built-in `$default` renamed to `$standard` (approves read, write, edit, find, grep, ls); `$readonly` updated to include find, grep, ls. Read-only tools (find, grep, ls) are now approved via the `$standard` preset instead of the sandbox auto-approval path. Schema validates preset key `$` prefix at finalize via new `MapNode` deferred key validation. `:Flemma status` now shows (R) icon for runtime-sourced tool approvals.
