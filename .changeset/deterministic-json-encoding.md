---
"@flemma-dev/flemma.nvim": minor
---

Add deterministic key-ordered JSON encoder for prompt caching. API request bodies now serialize with sorted keys and provider-specific trailing keys (messages, tools) placed last, maximizing prefix-based cache hits across all providers.
