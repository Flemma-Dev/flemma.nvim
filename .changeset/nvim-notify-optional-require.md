---
"@flemma-dev/flemma.nvim": patch
---

Fixed plugin installation failure on nixpkgs (and other eager require-checkers) when rcarriga/nvim-notify is not installed. `flemma.integrations.nvim_notify` used to hard-require `notify` at module load; it now pcalls the require so the module loads cleanly in isolation and `flemma.notify` falls back to `vim.notify`. Users with nvim-notify installed see no behavior change.
