---
"@flemma-dev/flemma.nvim": patch
---

Fixed progress character counter freezing during tool use for OpenAI and Vertex providers by emitting `on_tool_input` callback for function call argument deltas
