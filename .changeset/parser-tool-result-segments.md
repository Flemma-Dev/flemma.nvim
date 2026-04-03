---
"@flemma-dev/flemma.nvim": minor
---

Parser now parses tool result fence content into template segments instead of attempting language-based (JSON/YAML) parsing. Raw fence text is retained as fallback for backward compatibility with processors that don't opt in to rich content evaluation.
