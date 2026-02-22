---
"@flemma-dev/flemma.nvim": minor
---

Removed all backwards-compatibility layers from the Claudius-to-Flemma migration. This is a breaking change for users who still rely on any of the following:

**Removed: `require("claudius")` module fallback.** The `lua/claudius/` shim that forwarded to `require("flemma")` has been deleted. Update your config to `require("flemma")`.

**Removed: legacy `:Flemma*` commands.** The individual commands `:FlemmaSend`, `:FlemmaCancel`, `:FlemmaImport`, `:FlemmaSendAndInsert`, `:FlemmaSwitch`, `:FlemmaNextMessage`, `:FlemmaPrevMessage`, `:FlemmaEnableLogging`, `:FlemmaDisableLogging`, `:FlemmaOpenLog`, and `:FlemmaRecallNotification` have been removed. Use the unified `:Flemma <subcommand>` tree instead (e.g., `:Flemma send`, `:Flemma cancel`, `:Flemma message:next`).

**Removed: `"claude"` provider alias.** Configs specifying `provider = "claude"` will no longer resolve to `"anthropic"`. Update your configuration to use `"anthropic"` directly.

**Removed: `reasoning_format` config field.** The deprecated `reasoning_format` type annotation (alias for `thinking_format`) has been removed from `flemma.config.Statusline`.

**Removed: `resolve_all_awaiting_execution()` internal API.** This backwards-compatibility wrapper in `flemma.tools.context` has been removed. Use `resolve_all_tool_blocks()` and filter for the `"pending"` status group instead.
