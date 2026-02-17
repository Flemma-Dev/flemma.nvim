---
"@flemma-dev/flemma.nvim": patch
---

Fixed cross-provider parameter merge bug where provider-specific config keys (e.g., `project_id`) were silently dropped when switching providers via presets
