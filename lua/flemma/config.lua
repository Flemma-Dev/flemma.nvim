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
---@field tool_icon flemma.config.HighlightValue
---@field tool_name flemma.config.HighlightValue
---@field tool_use_title flemma.config.HighlightValue
---@field tool_result_title flemma.config.HighlightValue
---@field tool_result_error flemma.config.HighlightValue
---@field tool_preview flemma.config.HighlightValue
---@field fold_preview flemma.config.HighlightValue
---@field fold_meta flemma.config.HighlightValue

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

---@class flemma.Config.Notifications
---@field enabled boolean Whether notifications are shown
---@field timeout integer Milliseconds before auto-dismiss. 0 for persistent.
---@field limit integer Maximum visible notifications at once.
---@field position "overlay" Display mode ("overlay" pins to window top).
---@field zindex integer Floating window stacking priority.
---@field highlight string Comma-separated highlight groups to derive bar colors from (first with both fg+bg wins)
---@field border false|"underline"|"underdouble"|"undercurl"|"underdotted"|"underdashed" Bottom border style, or false to disable

---@class flemma.config.Pricing
---@field enabled boolean

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

---@class flemma.config.BashToolConfig
---@field shell? string
---@field cwd? string Working directory; supports "urn:flemma:buffer:path" (default: "urn:flemma:buffer:path")
---@field env? table<string, string>

---@class flemma.config.SandboxPolicy
---@field rw_paths? string[] Read-write paths; supports urn:flemma:* URNs, $ENV, ${ENV:-default} (default: see config defaults)
---@field network? boolean Allow network access (default: true)
---@field allow_privileged? boolean Allow sudo/capabilities (default: false, enables --unshare-user)

---@class flemma.config.BwrapBackendConfig
---@field path? string Path to bwrap binary (default: "bwrap")
---@field extra_args? string[] Raw extra bwrap arguments

---@class flemma.config.SandboxConfig
---@field enabled boolean Master switch (default: true)
---@field backend? string "auto" = detect quietly, "required" = detect and warn if none, or explicit name (default: "auto")
---@field policy? flemma.config.SandboxPolicy
---@field backends? table<string, table> Per-backend config

---@class flemma.config.AutoApproveContext
---@field bufnr integer
---@field tool_id string
---@field opts? flemma.opt.FrontmatterOpts Pre-evaluated per-buffer opts (avoids re-evaluating frontmatter)

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
---@field bash flemma.config.BashToolConfig
---@field modules? string[] Lua module paths for third-party tool sources
---@field max_concurrent integer

---@class flemma.config.AutoClose
---@field thinking boolean
---@field tool_use boolean
---@field tool_result boolean
---@field frontmatter boolean

---@class flemma.config.Editing
---@field disable_textwidth boolean
---@field auto_write boolean
---@field manage_updatetime boolean
---@field foldlevel integer
---@field auto_close flemma.config.AutoClose

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

---@class flemma.config.Experimental
---@field lsp boolean Enable in-process LSP for .chat buffers

---User-facing setup options — every field is optional (merged with defaults).
---@class flemma.Config.Opts
---@field defaults? { dark: { bg: string, fg: string }, light: { bg: string, fg: string } }
---@field highlights? flemma.config.Highlights
---@field role_style? string
---@field ruler? flemma.config.Ruler
---@field signs? flemma.config.Signs
---@field line_highlights? flemma.config.LineHighlights
---@field notifications? flemma.Config.Notifications
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
---@field sandbox? flemma.config.SandboxConfig
---@field diagnostics? flemma.config.Diagnostics
---@field experimental? flemma.config.Experimental

---Full resolved config (all fields present after merging with defaults).
---@class flemma.Config : flemma.Config.Opts
---@field defaults { dark: { bg: string, fg: string }, light: { bg: string, fg: string } }
---@field highlights flemma.config.Highlights
---@field role_style string
---@field ruler flemma.config.Ruler
---@field signs flemma.config.Signs
---@field line_highlights flemma.config.LineHighlights
---@field notifications flemma.Config.Notifications
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
---@field sandbox flemma.config.SandboxConfig
---@field diagnostics flemma.config.Diagnostics
---@field experimental flemma.config.Experimental

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
    -- Tools
    tool_icon = "FlemmaToolUseTitle", -- Highlight for ◆ symbol in tool fold lines
    tool_name = "Function", -- Highlight for tool name in fold lines and headers
    tool_use_title = "Function", -- Highlight for **Tool Use:** title text
    tool_result_title = "Function", -- Highlight for **Tool Result:** title text
    tool_result_error = "DiagnosticError", -- Highlight for (error) marker in tool results
    tool_preview = "Comment", -- Highlight for tool preview virtual lines in pending tool blocks
    -- Folds
    fold_preview = "Comment", -- Highlight for tool content preview text in fold lines
    fold_meta = "Comment", -- Highlight for (N lines) suffix in fold lines
  },
  role_style = "bold", -- style applied to role markers like @You:
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
  notifications = {
    enabled = true,
    timeout = 10000,
    limit = 1,
    position = "overlay",
    zindex = 30,
    highlight = "@text.note,PmenuSel", -- Highlight group(s) for the notification bar; first with both fg+bg is used
    border = false, -- Bottom border: "underline", "underdouble", "undercurl", "underdotted", "underdashed", or false
  },
  pricing = {
    enabled = true, -- Whether to show pricing information in notifications
  },
  statusline = {
    format = "#{model}#{?#{thinking}, (#{thinking}),}#{?#{booting}, ⏳,}", -- tmux-style format string. Variables: #{model}, #{provider}, #{thinking}, #{booting}
  },
  provider = "anthropic", -- Default provider: "anthropic", "openai", or "vertex"
  model = nil, -- Will use provider-specific default if nil
  parameters = {
    max_tokens = "50%", -- Default max tokens: percentage of model's max_output_tokens, or integer
    temperature = 0.7, -- Default temperature for all providers
    timeout = 120, -- Default response timeout for cURL requests
    connect_timeout = 10, -- Default connection timeout for cURL requests
    cache_retention = "short", -- Default prompt caching: "short", "long", or "none"
    thinking = "high", -- Default thinking level: "low", "medium", "high", numeric budget, or false to disable
  },
  tools = {
    require_approval = true, -- Require user approval before executing tool calls (two-step <C-]> flow)
    auto_approve = { "$default" }, -- Tools that bypass approval: string[] of tool/preset names, or function(tool_name, input, context) → true|false|"deny"
    auto_approve_sandboxed = true, -- Auto-approve tools that run inside the sandbox (set false to require manual approval)
    presets = {}, -- Named approval presets (override built-ins or add new ones with "$name" keys)
    autopilot = {
      enabled = true, -- Auto-execute approved tools and re-send when resolved
      max_turns = 100, -- Safety limit on consecutive autonomous LLM turns
    },
    max_concurrent = 2, -- Max tools executing simultaneously per buffer (0 = unlimited)
    default_timeout = 30, -- Default timeout for async tools (seconds)
    show_spinner = true, -- Show spinner animation during execution
    cursor_after_result = "result", -- Cursor behavior after result injection: "result", "stay", or "next"
    bash = {
      shell = nil, -- Shell to use (default: bash)
      cwd = "urn:flemma:buffer:path", -- Working directory; resolves to .chat file's directory (set nil for Neovim cwd)
      env = nil, -- Environment variables to add
    },
    modules = {}, -- Lua module paths for third-party tool sources (e.g., "3rd.tools.todos")
  },
  presets = {}, -- Named presets for :Flemma switch (use ["$name"] key syntax)
  text_object = "m", -- Default text object key, set to false to disable
  editing = {
    disable_textwidth = true, -- Whether to disable textwidth in chat buffers
    auto_write = false, -- Whether to automatically write the buffer after changes
    manage_updatetime = true, -- Whether to set updatetime to 100 in chat buffers and restore original value when leaving
    foldlevel = 1, -- Default fold level: 0=all closed, 1=thinking/frontmatter collapsed, 99=all open
    auto_close = {
      thinking = true, -- Auto-close thinking blocks when they become terminal
      tool_use = true, -- Auto-close tool_use blocks when completed
      tool_result = true, -- Auto-close tool_result blocks when terminal
      frontmatter = false, -- Auto-close frontmatter blocks (disabled by default)
    },
  },
  logging = {
    enabled = false, -- Logging disabled by default
    path = vim.fn.stdpath("cache") .. "/flemma.log", -- Default log path
    level = "DEBUG", -- Minimum log level: "TRACE", "DEBUG", "INFO", "WARN", "ERROR"
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
  diagnostics = {
    enabled = false, -- Enable request diagnostics for debugging prompt caching issues
  },
  sandbox = {
    enabled = true, -- Enable filesystem sandboxing
    backend = "auto", -- "auto" detects the best available backend; set explicitly to force one
    policy = {
      rw_paths = { -- Read-write paths (all others are read-only)
        "urn:flemma:cwd",
        "urn:flemma:buffer:path",
        "/tmp",
        "${TMPDIR:-/tmp}",
        "${XDG_CACHE_HOME:-~/.cache}",
        "${XDG_DATA_HOME:-~/.local/share}",
      },
      network = true, -- Allow network access inside the sandbox
      allow_privileged = false, -- Allow sudo/capabilities (false = safer, drops privileges)
    },
    backends = {
      bwrap = {
        path = "bwrap", -- Path to bubblewrap binary
        extra_args = {}, -- Additional bwrap arguments for advanced use
      },
    },
  },
  experimental = {
    lsp = vim.lsp ~= nil,
  },
}
