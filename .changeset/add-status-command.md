---
"@flemma-dev/flemma.nvim": minor
---

Added `:Flemma status` command that displays comprehensive runtime status (provider, model, merged parameters, autopilot state, sandbox state, enabled tools) in a read-only scratch buffer. Use `:Flemma status verbose` for full config dump. `:Flemma autopilot:status` and `:Flemma sandbox:status` now open the same status view with cursor positioned at the relevant section.
