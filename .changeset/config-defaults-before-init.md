---
"@flemma-dev/flemma.nvim": patch
---

Fixed a crash when a Flemma module is `require()`d before `setup()` runs. The experimental Codex adapter registers its ChatGPT secrets resolver as a load-time side effect, and that path asserted the config system was already initialized — so merely requiring the adapter in isolation threw `config.init() must be called before register_module_defaults()`. This broke tools that load every module in a bare Neovim, most notably nixpkgs packaging (`nvimRequireCheck`). Config now queues module-default registrations that arrive before initialization and flushes them once `setup()` supplies the schema, so any module can be required standalone and its defaults still land.
