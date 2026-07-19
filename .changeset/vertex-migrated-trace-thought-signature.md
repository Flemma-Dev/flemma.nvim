---
"@flemma-dev/flemma.nvim": patch
---

Fix Gemini 3+ rejecting conversations migrated from another provider (HTTP 400): tool calls without a native Vertex thought signature now carry Google's documented migrated-trace placeholder, and buffered API error bodies are logged so failures stay diagnosable from the log file.
