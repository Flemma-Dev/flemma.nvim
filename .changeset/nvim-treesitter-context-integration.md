---
"@flemma-dev/flemma.nvim": patch
---

Added optional `nvim-treesitter-context` integration that disables the sticky-context window on `.chat` buffers. Wire `require("flemma.integrations.nvim-treesitter-context").on_attach` (or `.wrap(existing)`) into your treesitter-context config. Internal rename: `flemma.integrations.devicons` → `flemma.integrations.nvim-web-devicons` and `flemma.integrations.nvim_notify` → `flemma.integrations.nvim-notify` — user-facing config keys (`integrations.devicons.*`) and internal type identifiers (`flemma.integrations.Devicons`, `flemma.integrations.NvimNotify`) are unchanged.
