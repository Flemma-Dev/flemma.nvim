---
"@flemma-dev/flemma.nvim": patch
---

`config.materialize()` now expands a `$preset` model reference into its concrete provider, model, and merged parameters as part of materialization. Previously every call site that needed the effective config had to wrap materialize in `normalize.resolve_preset(...)` — a two-step dance that was easy to forget, leaving `$preset` aliases unexpanded and reaching model logic as literal strings. Preset expansion now lives with the config facade (the other config-domain expansion, e.g. `$preset` list references, already did); `normalize.resolve_preset` is removed. `config.get()`/`config.inspect()` continue to return the raw alias, which is what setup's one-time `presets.resolve_default` reads.
