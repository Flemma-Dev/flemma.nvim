---
"@flemma-dev/flemma.nvim": minor
---

Compiler now compiles compound tool_result segments (those with inner segments populated by the parser) using a generic capture mechanism. The `__capture_open`/`__capture_close` runtime primitives redirect `__emit` output into a sub-collector, grouping evaluated child parts into a `tool_result` envelope with `.parts`. Opaque tool results (no inner segments) continue to pass through unchanged.
