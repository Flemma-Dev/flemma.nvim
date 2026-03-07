---
"@flemma-dev/flemma.nvim": patch
---

Fix diagnostics false positive when messages grow between turns. Cache-break warnings now only fire for actual prefix-breaking changes (tools, config, system prompt), not for normal message appends at the document tail.
