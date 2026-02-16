---
"@flemma-dev/flemma.nvim": minor
---

Added autopilot: an autonomous tool execution loop that transforms Flemma into a fully autonomous agent. After each LLM response containing tool calls, autopilot executes approved tools, collects results, and re-sends the conversation automatically – repeating until the model stops calling tools or a tool requires manual approval. Includes per-buffer frontmatter override (`flemma.opt.tools.autopilot`), runtime toggle commands (`:Flemma autopilot:enable/disable/status`), configurable turn limits, conflict detection for user-edited pending blocks, and full cancellation safety via Ctrl-C.
