---
"@flemma-dev/flemma.nvim": minor
---

Added support for Kimi K2.6 (`kimi-k2.6`) and promoted it to the default Moonshot model. Pricing per platform.kimi.ai/docs/pricing/chat-k26: $0.95/M input, $0.16/M cache read, $4.00/M output, 256K context. K2 preview/turbo/thinking variants are now flagged with their May 25, 2026 retirement date.

Also introduced a provider-specific extension point on `flemma.models.ModelInfo`: an optional `meta` table whose shape is documented by the owning adapter. Moonshot uses `meta.thinking_mode = "forced" | "optional"` to drive thinking behaviour directly from the model data instead of hardcoded tables in the adapter.
