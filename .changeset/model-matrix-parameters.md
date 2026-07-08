---
"@flemma-dev/flemma.nvim": minor
---

Model strings accept URI matrix parameters: `flemma.opt.model = "vertex/gemini-3.1-pro-preview;project_id=x"` decomposes into provider, model, and provider-scoped parameters everywhere a model is named (config, `:Flemma switch`, presets), and `@file` references accept the same multi-key `;key=value` options.
