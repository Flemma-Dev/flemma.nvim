---
"@flemma-dev/flemma.nvim": patch
---

Fixed thinking level mapping for OpenAI, Anthropic, and Vertex providers. Flemma's canonical thinking levels (minimal/low/medium/high/max) are now silently mapped to valid provider API values via per-model metadata instead of being passed through raw. This fixes the "Unsupported value: 'minimal'" error when using `thinking = "minimal"` with OpenAI models.
