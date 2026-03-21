--- EmmyLua type definitions for Flemma configuration.
---
--- These types describe the shape of the materialized configuration returned by
--- `config.materialize()` and used for type-checking throughout the codebase.
---
--- Tool-specific and provider-specific config types live with their respective
--- modules (e.g., `tools/definitions/bash.lua` defines its own schema). They are
--- resolved dynamically via `symbols.DISCOVER` and do not appear here.
---
--- Long-term, these types will be auto-generated from the schema DSL.

---@alias flemma.config.HighlightValue string|{ dark: string, light: string }

---@class flemma.config.ConfigAware<T>
---@field get_config fun(self): T|nil

---@class flemma.config.Highlights
---@field system flemma.config.HighlightValue
---@field user flemma.config.HighlightValue
---@field assistant flemma.config.HighlightValue
---@field lua_expression flemma.config.HighlightValue
---@field lua_code_block flemma.config.HighlightValue
---@field lua_delimiter flemma.config.HighlightValue
---@field user_file_reference flemma.config.HighlightValue
---@field thinking_tag flemma.config.HighlightValue
---@field thinking_block flemma.config.HighlightValue
---@field tool_icon flemma.config.HighlightValue
---@field tool_name flemma.config.HighlightValue
---@field tool_use_title flemma.config.HighlightValue
---@field tool_result_title flemma.config.HighlightValue
---@field tool_result_error flemma.config.HighlightValue
---@field tool_preview flemma.config.HighlightValue
---@field fold_preview flemma.config.HighlightValue
---@field fold_meta flemma.config.HighlightValue
---@field tool_detail flemma.config.HighlightValue
---@field busy flemma.config.HighlightValue

---@class flemma.config.Ruler
---@field enabled boolean
---@field char string
---@field hl flemma.config.HighlightValue

---@class flemma.config.SignRole
---@field char? string
---@field hl boolean|flemma.config.HighlightValue

---@class flemma.config.Signs
---@field enabled boolean
---@field char string
---@field system flemma.config.SignRole
---@field user flemma.config.SignRole
---@field assistant flemma.config.SignRole

---@class flemma.config.LineHighlights
---@field enabled boolean
---@field frontmatter flemma.config.HighlightValue
---@field system flemma.config.HighlightValue
---@field user flemma.config.HighlightValue
---@field assistant flemma.config.HighlightValue

---@class flemma.config.Notifications
---@field enabled boolean Whether notifications are shown
---@field timeout integer Milliseconds before auto-dismiss. 0 for persistent.
---@field limit integer Maximum visible notifications at once.
---@field position "overlay" Display mode ("overlay" pins to window top).
---@field zindex integer Floating window stacking priority.
---@field highlight string Comma-separated highlight groups to derive bar colors from (first with both fg+bg wins)
---@field border false|"underline"|"underdouble"|"undercurl"|"underdotted"|"underdashed" Bottom border style, or false to disable

---@class flemma.config.Pricing
---@field enabled boolean

---@class flemma.config.Progress
---@field highlight string Comma-separated highlight groups to derive progress bar colors from (first with both fg+bg wins)
---@field zindex integer Floating window stacking priority

---@class flemma.config.Diagnostics
---@field enabled boolean

---@class flemma.config.Statusline
---@field format string tmux-style format string for the lualine component. Variables: #{model}, #{provider}, #{thinking}, #{booting}. Supports conditionals: #{?cond,true,false}

---@class flemma.config.Parameters
---@field max_tokens? integer|string Integer token count or percentage string (e.g. "50%") of model's max_output_tokens
---@field temperature? number
---@field timeout? integer
---@field connect_timeout? integer
---@field cache_retention? string Prompt caching: "short", "long", or "none"
---@field thinking? false|string|number Unified thinking: "minimal"/"low"/"medium"/"high"/"max", numeric budget, or false to disable
---@field reasoning? string Provider-specific (OpenAI): reasoning effort level
---@field thinking_budget? number Provider-specific (Anthropic/Vertex): explicit token budget
---@field [string] table<string, any>|nil Provider-specific parameter overrides

---@class flemma.config.SandboxPolicy
---@field rw_paths? string[] Read-write paths; supports urn:flemma:* URNs, $ENV, ${ENV:-default} (default: see config defaults)
---@field network? boolean Allow network access (default: true)
---@field allow_privileged? boolean Allow sudo/capabilities (default: false, enables --unshare-user)

---@class flemma.config.BwrapBackendConfig
---@field path? string Path to bwrap binary (default: "bwrap")
---@field extra_args? string[] Raw extra bwrap arguments

---@class flemma.config.SecretsGcloudConfig
---@field path? string Path to gcloud binary (default: "gcloud")

---@class flemma.config.SecretsConfig
---@field gcloud? flemma.config.SecretsGcloudConfig

---@class flemma.config.SandboxConfig
---@field enabled boolean Master switch (default: true)
---@field backend? string "auto" = detect quietly, "required" = detect and warn if none, or explicit name (default: "auto")
---@field policy? flemma.config.SandboxPolicy
---@field backends? table<string, table> Per-backend config

---@class flemma.config.AutoApproveContext
---@field bufnr integer
---@field tool_id string

---@alias flemma.config.AutoApproveDecision true|false|"deny"

---@alias flemma.config.AutoApproveFunction fun(tool_name: string, input: table, context: flemma.config.AutoApproveContext): flemma.config.AutoApproveDecision|nil

---@alias flemma.config.AutoApprove string[]|flemma.config.AutoApproveFunction|string

---@class flemma.config.AutopilotConfig
---@field enabled boolean
---@field max_turns integer

---@class flemma.config.ToolsConfig
---@field require_approval boolean
---@field auto_approve? flemma.config.AutoApprove
---@field auto_approve_sandboxed? boolean Auto-approve tools that run inside the sandbox (default: true). Set false to always require manual approval even when sandboxed.
---@field presets? table<string, flemma.tools.PresetDefinition> Named approval presets
---@field autopilot flemma.config.AutopilotConfig
---@field default_timeout integer
---@field show_spinner boolean
---@field cursor_after_result "result"|"stay"|"next"
---@field modules? string[] Lua module paths for third-party tool sources
---@field max_concurrent integer

---@class flemma.config.TemplatingConfig
---@field modules? string[] Lua module paths for third-party environment populators

---@class flemma.config.AutoClose
---@field thinking boolean
---@field tool_use boolean
---@field tool_result boolean
---@field frontmatter boolean

---@class flemma.config.Editing
---@field auto_prompt boolean
---@field disable_textwidth boolean
---@field auto_write boolean
---@field manage_updatetime boolean
---@field foldlevel integer
---@field auto_close flemma.config.AutoClose

---@class flemma.config.NormalKeymaps
---@field send string
---@field cancel string
---@field tool_execute string
---@field message_next string
---@field message_prev string
---@field fold_toggle string|false

---@class flemma.config.InsertKeymaps
---@field send string

---@class flemma.config.Keymaps
---@field normal flemma.config.NormalKeymaps
---@field insert flemma.config.InsertKeymaps
---@field enabled boolean

---@class flemma.config.Experimental
---@field lsp boolean Enable in-process LSP for .chat buffers
---@field tools boolean Enable experimental exploration tools (grep, find, ls)

---User-facing setup options — every field is optional (merged with defaults).
---@class flemma.Config.Opts
---@field defaults? { dark: { bg: string, fg: string }, light: { bg: string, fg: string } }
---@field highlights? flemma.config.Highlights
---@field role_style? string
---@field ruler? flemma.config.Ruler
---@field signs? flemma.config.Signs
---@field line_highlights? flemma.config.LineHighlights
---@field notifications? flemma.config.Notifications
---@field progress? flemma.config.Progress
---@field pricing? flemma.config.Pricing
---@field statusline? flemma.config.Statusline
---@field provider? string
---@field model? string
---@field parameters? flemma.config.Parameters
---@field tools? flemma.config.ToolsConfig
---@field templating? flemma.config.TemplatingConfig
---@field presets? table<string, any>
---@field text_object? string|false
---@field editing? flemma.config.Editing
---@field logging? flemma.logging.Config
---@field keymaps? flemma.config.Keymaps
---@field sandbox? flemma.config.SandboxConfig
---@field diagnostics? flemma.config.Diagnostics
---@field experimental? flemma.config.Experimental
---@field secrets? flemma.config.SecretsConfig

---Full resolved config (all fields present after merging with defaults).
---@class flemma.Config : flemma.Config.Opts
---@field defaults { dark: { bg: string, fg: string }, light: { bg: string, fg: string } }
---@field highlights flemma.config.Highlights
---@field role_style string
---@field ruler flemma.config.Ruler
---@field signs flemma.config.Signs
---@field line_highlights flemma.config.LineHighlights
---@field notifications flemma.config.Notifications
---@field progress flemma.config.Progress
---@field pricing flemma.config.Pricing
---@field statusline flemma.config.Statusline
---@field provider string
---@field parameters flemma.config.Parameters
---@field tools flemma.config.ToolsConfig
---@field templating flemma.config.TemplatingConfig
---@field presets table<string, any>
---@field text_object string|false
---@field editing flemma.config.Editing
---@field logging flemma.logging.Config
---@field keymaps flemma.config.Keymaps
---@field sandbox flemma.config.SandboxConfig
---@field diagnostics flemma.config.Diagnostics
---@field experimental flemma.config.Experimental
---@field secrets flemma.config.SecretsConfig
