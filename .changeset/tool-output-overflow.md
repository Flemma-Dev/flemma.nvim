---
"@flemma-dev/flemma.nvim": minor
---

Added shared tool output overflow handling: when bash or MCP tool results exceed 2000 lines or 50KB, the full output is saved to a configurable temp file and the model receives truncated content with instructions to read the full output. The overflow path format is configurable via `tools.truncate.output_path_format`.
