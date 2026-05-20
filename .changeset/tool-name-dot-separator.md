---
"@flemma-dev/flemma.nvim": minor
---

Changed tool name separator from `:` to `.` for consistency with MCP and conventional namespace syntax. Existing `.chat` files are migrated automatically on open. Tool modules can now export `.approval` to register approval resolvers via `tools.modules`, replacing the module-path-in-auto_approve pattern.
