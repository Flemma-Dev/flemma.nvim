---
"@flemma-dev/flemma.nvim": minor
---

Sandbox variable expansion overhaul and DNS fix:

- Path variables in `rw_paths` now use `urn:flemma:cwd` and `urn:flemma:buffer:path` instead of `$CWD` and `$FLEMMA_BUFFER_PATH` (breaking change for custom configs)
- Added `$ENV` and `${ENV:-default}` expansion with bash-style fallback syntax
- Default `rw_paths` now includes `${TMPDIR:-/tmp}`, `${XDG_CACHE_HOME:-~/.cache}`, and `${XDG_DATA_HOME:-~/.local/share}` for package manager compatibility
- Removed `--tmpfs /run` from bwrap backend, fixing DNS resolution on NixOS/systemd (nscd socket was hidden)
- Paths are now prefix-deduplicated (parent subsumes child)
- `:Flemma status` and `:Flemma sandbox:status` now show resolved rw_paths, network, and privilege policy
