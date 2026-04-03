---
"@flemma-dev/flemma.nvim": minor
---

Processor now gates tool result template evaluation on the `template_tool_result` capability. Tool results from tools that declare this capability get their inner segments compiled and evaluated through the capture mechanism; all other tool results collapse to their fallback string.
