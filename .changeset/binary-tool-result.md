---
"@flemma-dev/flemma.nvim": minor
---

Added binary content support in tool results. The read tool now detects binary files (images, PDFs) and emits file references instead of raw bytes. Providers that support mixed content (Anthropic, OpenAI Responses, Vertex) send images and PDFs natively; providers that don't (OpenAI Chat, Moonshot) fall back to text placeholders with a diagnostic warning.
