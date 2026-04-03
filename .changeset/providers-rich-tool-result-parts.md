---
"@flemma-dev/flemma.nvim": minor
---

Providers now read `.parts` on tool results instead of the deprecated `.content` string. Anthropic, OpenAI Responses, and Vertex map image/PDF parts to their native content block formats; OpenAI Chat and Moonshot fall back to text with `[binary file: ...]` placeholder for non-text parts.
