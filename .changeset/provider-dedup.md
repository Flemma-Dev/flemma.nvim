---
"@flemma-dev/flemma.nvim": patch
---

Refactored provider layer to eliminate ~370 lines of duplicated code across Anthropic, OpenAI, and Vertex providers. Base now owns the SSE parsing preamble, content emission (tool use blocks, thinking blocks, truncation warnings), and automatic sink lifecycle management. New providers need roughly one-third of the previous boilerplate.
