---
"@flemma-dev/flemma.nvim": patch
---

Fixed duplicate error notifications when the API returns a single-line JSON error body (e.g. Anthropic 429 rate limit). `_handle_non_sse_line` was buffering the line and emitting `on_error`, after which `finalize_response`'s `_check_buffered_response` re-parsed the same buffered body and emitted the error again. The line is now only buffered when it can't be handled directly, so `_check_buffered_response` only runs on genuinely unhandled bodies (multi-line JSON, non-JSON, etc.).
