--- Flemma default configuration

---@alias flemma.config.HighlightValue string|{ dark: string, light: string }

---@class flemma.config.Highlights
---@field system flemma.config.HighlightValue
---@field user flemma.config.HighlightValue
---@field assistant flemma.config.HighlightValue
---@field user_lua_expression flemma.config.HighlightValue
---@field user_file_reference flemma.config.HighlightValue
---@field thinking_tag flemma.config.HighlightValue
---@field thinking_block flemma.config.HighlightValue
---@field tool_use flemma.config.HighlightValue
---@field tool_result flemma.config.HighlightValue
---@field tool_result_error flemma.config.HighlightValue

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

---@class flemma.config.Pricing
---@field enabled boolean

---@class flemma.config.Statusline
---@field thinking_format string
---@field reasoning_format string

---@class flemma.config.Parameters
---@field max_tokens? integer
---@field temperature? number
---@field timeout? integer
---@field connect_timeout? integer
---@field reasoning? string
---@field thinking_budget? number
---@field [string] table<string, any>|nil Provider-specific parameter overrides

---@class flemma.config.BashToolConfig
---@field shell? string
---@field cwd? string
---@field env? table<string, string>

---@class flemma.config.AutoApproveContext
---@field bufnr integer
---@field tool_id string

---@alias flemma.config.AutoApproveDecision true|false|"deny"

---@alias flemma.config.AutoApproveFunction fun(tool_name: string, input: table, context: flemma.config.AutoApproveContext): flemma.config.AutoApproveDecision|nil

---@alias flemma.config.AutoApprove string[]|flemma.config.AutoApproveFunction

---@class flemma.config.ToolsConfig
---@field require_approval boolean
---@field auto_approve? flemma.config.AutoApprove
---@field default_timeout integer
---@field show_spinner boolean
---@field cursor_after_result "result"|"stay"|"next"
---@field bash flemma.config.BashToolConfig

---@class flemma.config.Editing
---@field disable_textwidth boolean
---@field auto_write boolean
---@field manage_updatetime boolean
---@field foldlevel integer

---@class flemma.config.NormalKeymaps
---@field send string
---@field cancel string
---@field tool_execute string
---@field next_message string
---@field prev_message string

---@class flemma.config.InsertKeymaps
---@field send string

---@class flemma.config.Keymaps
---@field normal flemma.config.NormalKeymaps
---@field insert flemma.config.InsertKeymaps
---@field enabled boolean

---User-facing setup options — every field is optional (merged with defaults).
---@class flemma.Config.Opts
---@field defaults? { dark: { bg: string, fg: string }, light: { bg: string, fg: string } }
---@field highlights? flemma.config.Highlights
---@field role_style? string
---@field ruler? flemma.config.Ruler
---@field signs? flemma.config.Signs
---@field line_highlights? flemma.config.LineHighlights
---@field notify? flemma.notify.Options
---@field pricing? flemma.config.Pricing
---@field statusline? flemma.config.Statusline
---@field provider? string
---@field model? string
---@field parameters? flemma.config.Parameters
---@field tools? flemma.config.ToolsConfig
---@field presets? table<string, any>
---@field text_object? string|false
---@field editing? flemma.config.Editing
---@field logging? flemma.logging.Config
---@field keymaps? flemma.config.Keymaps

---Full resolved config (all fields present after merging with defaults).
---@class flemma.Config : flemma.Config.Opts
---@field defaults { dark: { bg: string, fg: string }, light: { bg: string, fg: string } }
---@field highlights flemma.config.Highlights
---@field role_style string
---@field ruler flemma.config.Ruler
---@field signs flemma.config.Signs
---@field line_highlights flemma.config.LineHighlights
---@field notify flemma.notify.Options
---@field pricing flemma.config.Pricing
---@field statusline flemma.config.Statusline
---@field provider string
---@field parameters flemma.config.Parameters
---@field tools flemma.config.ToolsConfig
---@field presets table<string, any>
---@field text_object string|false
---@field editing flemma.config.Editing
---@field logging flemma.logging.Config
---@field keymaps flemma.config.Keymaps

---@type flemma.Config
return {
  -- Fallback colors used when highlight groups don't define fg/bg
  defaults = {
    dark = { bg = "#000000", fg = "#ffffff" },
    light = { bg = "#ffffff", fg = "#000000" },
  },
  highlights = {
    system = "Special", -- Highlight group or hex color (e.g., "#ffccaa") for system messages
    user = "Normal", -- Highlight group or hex color for user messages
    assistant = "Normal", -- Highlight group or hex color for assistant messages
    user_lua_expression = "PreProc", -- Highlight group or hex color for {{expression}} in user messages
    user_file_reference = "Include", -- Highlight group or hex color for @./file references in user messages
    thinking_tag = "Comment", -- Highlight group or hex color for <thinking> and </thinking> tags
    thinking_block = { dark = "Comment+bg:#102020-fg:#111111", light = "Comment-bg:#102020+fg:#111111" }, -- Highlight group or hex color for content inside <thinking> blocks
    tool_use = "Function", -- Highlight group or hex color for **Tool Use:** title
    tool_result = "Function", -- Highlight group or hex color for **Tool Result:** title
    tool_result_error = "DiagnosticError", -- Highlight group or hex color for (error) marker in tool results
  },
  role_style = "bold,underline", -- style applied to role markers like @You:
  ruler = {
    enabled = true, -- Set to false to disable rulers between messages
    char = "─", -- The character to use for the ruler
    hl = { dark = "Comment-fg:#303030", light = "Comment+fg:#303030" }, -- Highlight group or hex color for the ruler
  },
  signs = {
    enabled = false, -- Enable sign column highlighting (disabled by default)
    char = "▌", -- Default vertical bar character
    system = {
      char = nil, -- Use default char
      hl = true, -- Inherit from highlights.system, set false to disable, or provide specific group/hex color
    },
    user = {
      char = "▏",
      hl = true, -- Inherit from highlights.user, set false to disable, or provide specific group/hex color
    },
    assistant = {
      char = nil, -- Use default char
      hl = true, -- Inherit from highlights.assistant, set false to disable, or provide specific group/hex color
    },
  },
  line_highlights = {
    enabled = true, -- Enable full-line background highlighting to distinguish roles
    frontmatter = { dark = "Normal+bg:#201020", light = "Normal-bg:#201020" }, -- Background color for frontmatter lines
    system = { dark = "Normal+bg:#201000", light = "Normal-bg:#201000" }, -- Background color for system message lines
    user = { dark = "Normal", light = "Normal" }, -- Background color for user message lines
    assistant = { dark = "Normal+bg:#102020", light = "Normal-bg:#102020" }, -- Background color for assistant message lines
  },
  notify = require("flemma.notify").default_opts,
  pricing = {
    enabled = true, -- Whether to show pricing information in notifications
  },
  statusline = {
    thinking_format = "{model}  ✓ thinking", -- Format string when thinking is enabled. {model} is replaced with the model name.
    reasoning_format = "{model} ({level})", -- Format string when reasoning is enabled. {model} is model name, {level} is reasoning level.
  },
  provider = "anthropic", -- Default provider: "anthropic", "openai", or "vertex"
  model = nil, -- Will use provider-specific default if nil
  parameters = {
    max_tokens = 4000, -- Default max tokens for all providers
    temperature = 0.7, -- Default temperature for all providers
    timeout = 120, -- Default response timeout for cURL requests
    connect_timeout = 10, -- Default connection timeout for cURL requests
  },
  tools = {
    require_approval = true, -- Require user approval before executing tool calls (two-step <C-]> flow)
    auto_approve = nil, -- Tools that bypass approval: string[] of tool names, or function(tool_name, input, context) → true|false|"deny"
    default_timeout = 30, -- Default timeout for async tools (seconds)
    show_spinner = true, -- Show spinner animation during execution
    cursor_after_result = "result", -- Cursor behavior after result injection: "result", "stay", or "next"
    bash = {
      shell = nil, -- Shell to use (default: bash)
      cwd = nil, -- Working directory (nil = buffer's directory or cwd)
      env = nil, -- Environment variables to add
    },
  },
  presets = {}, -- Named presets for :Flemma switch (use ["$name"] key syntax)
  text_object = "m", -- Default text object key, set to false to disable
  editing = {
    disable_textwidth = true, -- Whether to disable textwidth in chat buffers
    auto_write = false, -- Whether to automatically write the buffer after changes
    manage_updatetime = true, -- Whether to set updatetime to 100 in chat buffers and restore original value when leaving
    foldlevel = 1, -- Default fold level: 0=all closed, 1=thinking/frontmatter collapsed, 99=all open
  },
  logging = {
    enabled = false, -- Logging disabled by default
    path = vim.fn.stdpath("cache") .. "/flemma.log", -- Default log path
  },
  keymaps = {
    normal = {
      send = "<C-]>",
      cancel = "<C-c>",
      tool_execute = "<M-CR>", -- Execute tool at cursor
      next_message = "]m", -- Jump to next message
      prev_message = "[m", -- Jump to previous message
    },
    insert = {
      send = "<C-]>",
    },
    enabled = true, -- Set to false to disable all keymaps
  },
}
