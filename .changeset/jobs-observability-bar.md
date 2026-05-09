---
"@flemma-dev/flemma.nvim": minor
---

Added background jobs observability bar and graduated the hooks system with internal subscribers.

A new bottom-right bar shows active background job count with an animated spinner, and displays a countdown animation when autopilot auto-resume is scheduled. The bar is fully standalone — it consumes only hook events and has zero imports from core or executor modules.

The hooks module now supports internal Lua subscribers via `hooks.on(name, callback)` alongside the existing User autocmd dispatch. Internal subscribers fire synchronously before autocmds, with per-subscriber error isolation.

New hooks: `job:submitted`, `autopilot:resume-scheduled`, `autopilot:resume-cancelled`, `autopilot:resumed`. The `job:completed` hook now includes `active_count` in its payload. The default `resume_delay` is bumped from 1s to 2s. The bar position is configurable via `ui.jobs.position`.
