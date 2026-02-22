---
"@flemma-dev/flemma.nvim": patch
---

Fixed bwrap sandbox hiding NixOS system packages by re-binding `/run/current-system` read-only after the `/run` tmpfs mount
