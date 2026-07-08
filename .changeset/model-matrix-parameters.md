---
"@flemma-dev/flemma.nvim": minor
---

Model strings accept URI matrix parameters: `flemma.opt.model = "vertex/gemini-3.1-pro-preview;project_id=x"` decomposes into provider, model, and provider-scoped parameters everywhere a model is named (config, `:Flemma switch`, presets), with source-order precedence, `;key=nil` clearing, and deterministic command-line-over-preset overrides in both grammars. `@file` references accept the same multi-key `;key=value` options (quote a parameterized MIME: `;type='text/plain;charset=utf-8'`). Preset parameters normalize to the config shape — provider-specific keys nest under the provider namespace.
