---
"@flemma-dev/flemma.nvim": minor
---

Added tool result store for durable materialization of tool output.

Every tool result is now written to a deterministic file path alongside the .chat file (configurable via `tools.store.path_format`). Replaces ephemeral `$TMPDIR` truncation overflow with co-located durable storage. Breaking: `tools.truncate.output_path_format` is removed — truncation overflow now routes through the store.

New config: `tools.store.{path_format, unnamed_path_format, materialize, preview, backup}`.
