---
"@flemma-dev/flemma.nvim": patch
---

Fixed bash tool failing with heredoc commands by replacing `{ cmd; } 2>&1` group wrapping with `exec 2>&1` prefix
