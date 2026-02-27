---
"@flemma-dev/flemma.nvim": patch
---

Fixed bwrap sandbox breaking nix commands on NixOS by using `--symlink` instead of `--ro-bind` for `/run/current-system` and `/run/booted-system`, preserving their symlink nature so nix can detect store paths correctly
