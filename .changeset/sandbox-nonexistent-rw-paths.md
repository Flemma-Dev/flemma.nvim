---
"@flemma-dev/flemma.nvim": patch
---

Fixed sandboxed commands failing outright when a configured `rw_paths` entry does not exist on disk (e.g. the lazily-created tool result store directory): nonexistent paths now drop out of the resolved policy instead of producing a bwrap mount error, degrading to "not writable" until the directory exists.
