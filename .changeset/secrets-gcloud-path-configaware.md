---
"@flemma-dev/flemma.nvim": minor
---

Added `secrets.gcloud.path` config option to make the gcloud binary path
configurable (e.g. for NixOS Nix-store paths). Introduced
`flemma.config.ConfigAware` interface and `flemma.secrets.Context` to
standardise per-resolver config access.
