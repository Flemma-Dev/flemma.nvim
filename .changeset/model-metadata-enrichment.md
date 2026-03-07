---
"@flemma-dev/flemma.nvim": minor
---

Enriched model metadata matrix with per-model thinking budgets, cache pricing, and cache minimum thresholds. Thinking parameters are now silently clamped to model-specific bounds instead of hitting runtime API errors. Cache percentage indicator is suppressed when input tokens are below the model's minimum cacheable threshold. Session pricing now uses per-model absolute cache costs where available, with provider-level multipliers as fallback.
