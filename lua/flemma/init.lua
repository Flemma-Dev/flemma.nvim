--- Flemma plugin core functionality
--- Provides chat interface and API integration
local M = {}

local plugin_config = require("flemma.config")
local log = require("flemma.logging")
local state = require("flemma.state")
local core = require("flemma.core")
local ui = require("flemma.ui")
local commands = require("flemma.commands")
local keymaps = require("flemma.keymaps")
local highlight = require("flemma.highlight")

-- Load frontmatter module to register built-in parsers
require("flemma.frontmatter")

-- Module configuration (will hold merged user opts and defaults)
local config = {}

-- Setup function to initialize the plugin
M.setup = function(user_opts)
  -- Merge user config with defaults from the config module
  user_opts = user_opts or {}
  config = vim.tbl_deep_extend("force", plugin_config, user_opts)

  -- Store config in state module
  state.set_config(config)

  -- Configure logging based on user settings
  log.configure({
    enabled = state.get_config().logging.enabled,
    path = state.get_config().logging.path,
  })

  -- Associate .chat files with the markdown treesitter parser
  vim.treesitter.language.register("markdown", { "chat" })

  log.info("setup(): Flemma starting...")

  -- Initialize provider based on the merged config
  local current_config = state.get_config()
  core.initialize_provider(current_config.provider, current_config.model, current_config.parameters)

  -- Set up filetype detection for .chat files
  vim.filetype.add({
    extension = {
      chat = "chat",
    },
    pattern = {
      [".*%.chat"] = "chat",
    },
  })

  -- Set up UI module
  ui.setup()

  -- Set up user commands
  commands.setup()

  -- Set up keymaps
  keymaps.setup()

  -- Set up highlighting
  highlight.setup()

  -- Set up chat filetype handling
  ui.setup_chat_filetype_autocmds()
end

-- Get the current model name
function M.get_current_model_name()
  local current_config = state.get_config()
  if current_config and current_config.model then
    return current_config.model
  end
  return nil -- Or an empty string, depending on desired behavior for uninitialized model
end

-- Get the current provider name
function M.get_current_provider_name()
  local current_config = state.get_config()
  if current_config and current_config.provider then
    return current_config.provider
  end
  return nil
end

return M
