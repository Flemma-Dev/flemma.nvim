---
"@flemma-dev/flemma.nvim": minor
---

Preserve foreign thinking blocks when switching providers mid-conversation. When an assistant message contains thinking from a different provider, the thinking summary is wrapped in `<thinking>` tags and injected as text content, giving the new model context on the previous model's reasoning.
