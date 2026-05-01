---
"@flemma-dev/flemma.nvim": minor
---

Added `try_estimate_usage` to the Vertex AI and Moonshot adapters, bringing `:Flemma usage:estimate` and the opt-in `#{buffer.tokens.input}` lualine segment to both providers. Vertex queries the `{model}:countTokens` REST endpoint (strips `generationConfig`); Moonshot queries `POST /v1/tokenizers/estimate-token-count` (strips `stream`/`max_tokens`/`temperature`/`thinking`). Both endpoints are free and rate-limited separately from generation.
