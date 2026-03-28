---
"@flemma-dev/flemma.nvim": patch
---

Centralized sink buffer name sanitization in the sink module. Callers no longer need to sanitize names themselves — `sink.create()` handles it automatically, keeping alphanumerics, dots, hyphens, underscores, and colons while collapsing consecutive hyphens. Sink buffer names are now more readable (e.g. `flemma://sink/http/https:-api.anthropic.com-v1-messages#1` instead of `flemma://sink/http/https-//api-anthropic-com/v1/messages#1`). Removed unused `contrib/extras/sink_viewer.lua`.
