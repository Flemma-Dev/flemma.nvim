---
"@flemma-dev/flemma.nvim": patch
---

Foreign thinking is now injected as tagless prose ("Here is some context to help you: …", closed by a lone `---` rule) instead of an XML-style wrapper. Anything framing the model's own prior turns is eventually reproduced verbatim in replies, so the framing must stay harmless when echoed — tag pairs re-enter the conversation as structure. The framing lives in the string catalogue (`thinking.foreign.wrap` in `po/flemma-harness.po`).
