--- EmmyLua type definitions for Flemma configuration.
--- AUTO-GENERATED from config/schema.lua — do not edit by hand.
--- Regenerate with: make types

---@alias flemma.config.HighlightValue string|{ dark: string, light: string }
---@alias flemma.tools.AutoApprove string[]|flemma.tools.AutoApproveFunction|string

---@class flemma.config.ConfigAware<T>
---@field get_config fun(self): T|nil

---@class flemma.Config
---@field diagnostics flemma.config.Diagnostics
---@field editing flemma.config.Editing
---@field experimental flemma.config.Experimental
---@field highlights flemma.config.Highlights
---@field integrations flemma.config.Integrations
---@field keymaps flemma.config.Keymaps
---@field line_highlights flemma.config.LineHighlights
---@field logging flemma.logging.Config
---@field lsp flemma.config.Lsp
---@field model? string
---@field parameters flemma.config.Parameters
---@field presets table<string, string|{  }|{ auto_approve: string[], model: string, parameters: {  }, provider: string }>
---@field provider string
---@field ruler flemma.config.Ruler
---@field sandbox flemma.config.Sandbox
---@field secrets flemma.config.Secrets
---@field templating flemma.config.Templating
---@field tools flemma.config.Tools
---@field turns flemma.config.Turns
---@field ui flemma.config.Ui

---@class flemma.config.Diagnostics
---@field enabled boolean

---@class flemma.config.Editing
---@field auto_close flemma.config.EditingAutoClose
---@field auto_prompt boolean
---@field auto_write boolean
---@field conceal? string|integer|false
---@field disable_textwidth boolean
---@field foldlevel integer
---@field manage_updatetime boolean

---@class flemma.config.Experimental

---@class flemma.config.Highlights
---@field assistant flemma.config.HighlightValue
---@field busy flemma.config.HighlightValue
---@field defaults flemma.config.HighlightsDefaults
---@field fold_meta flemma.config.HighlightValue
---@field fold_preview flemma.config.HighlightValue
---@field lua_code_block flemma.config.HighlightValue
---@field lua_delimiter flemma.config.HighlightValue
---@field lua_expression flemma.config.HighlightValue
---@field role_style string
---@field system flemma.config.HighlightValue
---@field thinking_block flemma.config.HighlightValue
---@field thinking_tag flemma.config.HighlightValue
---@field tool_detail flemma.config.HighlightValue
---@field tool_icon flemma.config.HighlightValue
---@field tool_name flemma.config.HighlightValue
---@field tool_preview flemma.config.HighlightValue
---@field tool_result_aborted flemma.config.HighlightValue
---@field tool_result_approved flemma.config.HighlightValue
---@field tool_result_denied flemma.config.HighlightValue
---@field tool_result_error flemma.config.HighlightValue
---@field tool_result_pending flemma.config.HighlightValue
---@field tool_result_rejected flemma.config.HighlightValue
---@field tool_result_title flemma.config.HighlightValue
---@field tool_use_title flemma.config.HighlightValue
---@field user flemma.config.HighlightValue
---@field user_file_reference flemma.config.HighlightValue

---@class flemma.config.Integrations
---@field devicons flemma.config.IntegrationsDevicons

---@class flemma.config.Keymaps
---@field enabled boolean
---@field insert flemma.config.KeymapsInsert
---@field normal flemma.config.KeymapsNormal
---@field text_object string|false

---@class flemma.config.LineHighlights
---@field assistant flemma.config.HighlightValue
---@field enabled boolean
---@field frontmatter flemma.config.HighlightValue
---@field system flemma.config.HighlightValue
---@field user flemma.config.HighlightValue

---@class flemma.config.Lsp
---@field enabled boolean

---@class flemma.config.Parameters
---@field anthropic? flemma.config.ParametersAnthropic
---@field cache_retention "short"|"long"|"none"
---@field connect_timeout integer
---@field max_tokens string|integer
---@field moonshot? flemma.config.ParametersMoonshot
---@field openai? flemma.config.ParametersOpenai
---@field temperature? number
---@field thinking "minimal"|"low"|"medium"|"high"|"max"|number|false
---@field timeout integer
---@field vertex? flemma.config.ParametersVertex
---@field [string] table|nil

---@class flemma.config.Ruler
---@field char string
---@field enabled boolean
---@field hl flemma.config.HighlightValue

---@class flemma.config.Sandbox
---@field backend string
---@field backends flemma.config.SandboxBackends
---@field enabled boolean
---@field policy flemma.config.SandboxPolicy

---@class flemma.config.Secrets
---@field gcloud flemma.config.SecretsGcloud

---@class flemma.config.Templating
---@field modules string[]

---@class flemma.config.Tools
---@field auto_approve flemma.tools.AutoApprove
---@field auto_approve_sandboxed boolean
---@field autopilot flemma.config.ToolsAutopilot
---@field bash? flemma.config.ToolsBash
---@field cursor_after_result "result"|"stay"|"next"
---@field default_timeout integer
---@field find? flemma.config.ToolsFind
---@field grep? flemma.config.ToolsGrep
---@field ls? flemma.config.ToolsLs
---@field max_concurrent integer
---@field mcporter flemma.config.ToolsMcporter
---@field modules string[]
---@field require_approval boolean
---@field show_spinner boolean
---@field truncate flemma.config.ToolsTruncate
---@field [string] table|nil

---@class flemma.config.Turns
---@field enabled boolean
---@field hl string
---@field padding { left: integer, right: integer }|integer

---@class flemma.config.Ui
---@field pricing flemma.config.UiPricing
---@field progress flemma.config.UiProgress
---@field statusline flemma.config.UiStatusline
---@field usage flemma.config.UiUsage

---@class flemma.config.EditingAutoClose
---@field frontmatter boolean
---@field thinking boolean
---@field tool_result boolean
---@field tool_use boolean

---@class flemma.config.HighlightsDefaults
---@field dark flemma.config.HighlightsDefaultsDark
---@field light flemma.config.HighlightsDefaultsLight

---@class flemma.config.IntegrationsDevicons
---@field enabled boolean
---@field icon string

---@class flemma.config.KeymapsInsert
---@field send string

---@class flemma.config.KeymapsNormal
---@field cancel string
---@field conceal_toggle string|false
---@field fold_toggle string|false
---@field message_next string
---@field message_prev string
---@field send string
---@field tool_execute string

---@class flemma.config.ParametersAnthropic
---@field effort? "low"|"medium"|"high"|"xhigh"|"max"
---@field thinking_budget? integer

---@class flemma.config.ParametersMoonshot
---@field prompt_cache_key? string

---@class flemma.config.ParametersOpenai
---@field experimental? flemma.config.ParametersOpenaiExperimental
---@field reasoning? string
---@field reasoning_summary? string

---@class flemma.config.ParametersVertex
---@field location? string
---@field project_id? string
---@field thinking_budget? integer

---@class flemma.config.SandboxBackends
---@field bwrap? flemma.config.SandboxBackendsBwrap
---@field [string] table|nil

---@class flemma.config.SandboxPolicy
---@field allow_privileged boolean
---@field network boolean
---@field rw_paths string[]

---@class flemma.config.SecretsGcloud
---@field path string

---@class flemma.config.ToolsAutopilot
---@field enabled boolean
---@field max_turns integer

---@class flemma.config.ToolsBash
---@field cwd? string
---@field env? table<string, string>
---@field shell? string

---@class flemma.config.ToolsFind
---@field cwd? string
---@field exclude? string[]

---@class flemma.config.ToolsGrep
---@field cwd? string
---@field exclude? string[]

---@class flemma.config.ToolsLs
---@field cwd? string

---@class flemma.config.ToolsMcporter
---@field enabled boolean
---@field exclude string[]
---@field include string[]
---@field path string
---@field startup flemma.config.ToolsMcporterStartup
---@field timeout integer

---@class flemma.config.ToolsTruncate
---@field output_path_format string

---@class flemma.config.UiPricing
---@field enabled boolean
---@field high_cost_threshold integer

---@class flemma.config.UiProgress
---@field highlight string
---@field position "top"|"bottom"|"top left"|"top right"|"bottom left"|"bottom right"

---@class flemma.config.UiStatusline
---@field format string|flemma.statusline.FormatFunction

---@class flemma.config.UiUsage
---@field enabled boolean
---@field highlight string
---@field position "top"|"bottom"|"top left"|"top right"|"bottom left"|"bottom right"
---@field timeout integer

---@class flemma.config.HighlightsDefaultsDark
---@field bg string
---@field fg string

---@class flemma.config.HighlightsDefaultsLight
---@field bg string
---@field fg string

---@class flemma.config.ParametersOpenaiExperimental
---@field phase boolean

---@class flemma.config.SandboxBackendsBwrap
---@field extra_args string[]
---@field path string

---@class flemma.config.ToolsMcporterStartup
---@field concurrency integer

---User-facing setup options — alias for flemma.Config.
---@alias flemma.Config.Opts flemma.Config
