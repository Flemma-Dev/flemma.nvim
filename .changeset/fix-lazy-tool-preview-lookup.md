---
"@flemma-dev/flemma.nvim": patch
---

Fixed tool fold previews falling back to generic key=value format for tools registered via `config.tools.modules` (e.g. extras) by ensuring lazy modules are loaded before registry lookup
