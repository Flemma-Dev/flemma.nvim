---
"@flemma-dev/flemma.nvim": patch
---

Sink buffer writes now go through writequeue for E565 textlock protection. Sink scratch buffers are set to nomodifiable, preventing users from accidentally editing them when viewed via sink_viewer.
