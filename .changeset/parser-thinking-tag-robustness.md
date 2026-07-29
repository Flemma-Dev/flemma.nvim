---
"@flemma-dev/flemma.nvim": patch
---

Fix assistant turns being silently emptied by an unterminated `<thinking>` block: the collected content is now preserved as thinking instead of dropping the rest of the turn from the AST. `</thinking>` still only closes a block on a line of its own — the token followed by content is treated as thinking prose (HTML/XML examples, format transcripts).
