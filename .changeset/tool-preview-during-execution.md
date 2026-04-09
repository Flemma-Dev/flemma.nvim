---
"@flemma-dev/flemma.nvim": patch
---

Fixed tool preview disappearing during execution. The virtual line preview (e.g., `bash: print Hello — $ sleep 5 && echo Hello`) now remains visible while a tool is executing, not just while pending approval.
