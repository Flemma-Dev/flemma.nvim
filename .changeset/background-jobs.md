---
"@flemma-dev/flemma.nvim": minor
---

Added background job support for async tools. Tools can run in the background without blocking the conversation — the model requests it via `background: true`, or the user moves an executing tool mid-flight with `<M-b>` (`:Flemma tool:background`). Completed results are delivered as `**Job Result:**` blocks when the conversation reaches idle. Orphaned jobs are detected and resolved on file reload.

- `flemma:jobs:status` harness tool lets the model query job status
- Jobs observability bar shows active count, spinner, and autopilot resume countdown (`ui.jobs.position`)
- `tools.autopilot.resume_delay` (default 2000ms) debounces auto-continue after job completion; Ctrl+C cancels
- Cursor-aware Ctrl+C with double-tap RAGE cancel (cancels all tools and the active request)
- `hooks.on(name, callback)` Lua subscriber API alongside User autocmds
- New hooks: `conversation:idle`, `job:submitted`, `job:completed`, `autopilot:resume-scheduled/cancelled/resumed`
- Tool indicator redesign: inline `⬢` icon + EOL status text with eight status-specific highlight groups
- Job result blocks: syntax highlighting, folding, fold text preview, LSP hover and go-to-definition
- Conceal keybindings migrated to `yoe`/`]oe`/`[oe` (Neovim option-toggle convention)
- Glob patterns in `auto_approve` lists (`"flemma:*"`); `$standard` preset updated to include harness tools
- `tool:finished` hook renamed to `tool:completed` (`FlemmaToolFinished` → `FlemmaToolCompleted`)
