---
"@flemma-dev/flemma.nvim": minor
---

Added tool result store for durable materialization of tool output.

Tool results can be materialized to deterministic file paths alongside the .chat file (opt-in via `tools.store.materialize`, layout via `tools.store.path_format`). Truncation overflow now always lands at the durable store location, replacing ephemeral `$TMPDIR` files. Breaking: `tools.truncate.output_path_format` is removed — truncation overflow now routes through the store.

New config: `tools.store.{path_format, unnamed_path_format, materialize, preview, backup}`.
