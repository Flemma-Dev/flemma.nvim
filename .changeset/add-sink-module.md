---
"@flemma-dev/flemma.nvim": minor
---

Added `flemma.sink` module — a buffer-backed data accumulator that replaces in-memory string/table accumulators across the codebase. Sinks handle line framing, write batching, and lifecycle management behind an opaque API. Migrated cURL streaming, bash tool output, provider response buffering, thinking accumulation, and tool input accumulation to use sinks.
