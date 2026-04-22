---
"@flemma-dev/flemma.nvim": patch
---

`normalize.resolve_max_tokens` now honours `min_output_tokens` on model info as a lower bound. Values below the model's minimum are raised to the minimum with a warning, and percentage-based `max_tokens` values use the larger of `MIN_MAX_TOKENS` or the model's minimum as their floor. Affects Moonshot Kimi K2.x thinking-capable models where the API rejects `max_tokens` below 16,000.
