---
"@flemma-dev/flemma.nvim": patch
---

Refactor: consolidated try_estimate_usage orchestration into a shared
base.send_count_tokens helper. Adapters now declare only endpoint,
body transformer, and response parser.
