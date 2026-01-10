--- Flemma default configuration
return {
  highlights = {
    system = "Special", -- Highlight group or hex color (e.g., "#ffccaa") for system messages
    user = "Normal", -- Highlight group or hex color for user messages
    assistant = "Comment", -- Highlight group or hex color for assistant messages
    user_lua_expression = "PreProc", -- Highlight group or hex color for {{expression}} in user messages
    user_file_reference = "Include", -- Highlight group or hex color for @./file references in user messages
    thinking_tag = "Comment", -- Highlight group or hex color for <thinking> and </thinking> tags
    thinking_block = "Comment", -- Highlight group or hex color for content inside <thinking> blocks
  },
  role_style = "bold,underline", -- style applied to role markers like @You:
  ruler = {
    char = "━", -- The character to use for the ruler
    hl = "NonText", -- Highlight group or hex color for the ruler
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
    vertex = {
      project_id = nil, -- Google Cloud project ID
      location = "global", -- Google Cloud region
      thinking_budget = nil, -- Optional. Budget for model thinking, in tokens. nil or 0 disables thinking. Values >= 1 enable thinking with the specified budget.
    },
    openai = {
      reasoning = nil, -- Optional. "low", "medium", "high". Controls reasoning effort.
    },
    anthropic = {
      thinking_budget = nil, -- Optional. Budget for model thinking, in tokens. nil or 0 disables thinking. Values >= 1024 enable thinking with the specified budget.
    },
  },
  presets = {}, -- Named presets for :Flemma switch (use ["$name"] key syntax)
  text_object = "m", -- Default text object key, set to false to disable
  editing = {
    disable_textwidth = true, -- Whether to disable textwidth in chat buffers
    auto_write = false, -- Whether to automatically write the buffer after changes
    manage_updatetime = true, -- Whether to set updatetime to 100 in chat buffers and restore original value when leaving
  },
  logging = {
    enabled = false, -- Logging disabled by default
    path = vim.fn.stdpath("cache") .. "/flemma.log", -- Default log path
  },
  keymaps = {
    normal = {
      send = "<C-]>",
      cancel = "<C-c>",
      next_message = "]m", -- Jump to next message
      prev_message = "[m", -- Jump to previous message
    },
    insert = {
      send = "<C-]>",
    },
    enabled = true, -- Set to false to disable all keymaps
  },
}
