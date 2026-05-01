---
"@flemma-dev/flemma.nvim": minor
---

Added `:Flemma usage:estimate` — delegates to the active provider's `try_estimate_usage` hook. The Anthropic adapter queries `POST /v1/messages/count_tokens` with the exact body a real send would produce (minus `max_tokens`, `stream`, `temperature`) and reports input tokens, estimated cost, and per-MTok pricing via `flemma.notify.info`.
