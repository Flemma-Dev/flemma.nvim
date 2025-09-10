--- Flemma plugin core functionality
--- Provides chat interface and API integration
local M = {}

local plugin_config = require("flemma.config")
local log = require("flemma.logging")
local provider_config = require("flemma.provider.config")
local state = require("flemma.state")
local textobject = require("flemma.textobject")
local core = require("flemma.core")
local ui = require("flemma.ui")
local buffers = require("flemma.buffers")
local navigation = require("flemma.navigation")
local commands = require("flemma.commands")
local keymaps = require("flemma.keymaps")
local highlight = require("flemma.highlight")

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

  -- Create the filetype detection
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "*.chat",
    callback = function()
      vim.bo.filetype = "chat"
      ui.setup_folding()

      -- Disable textwidth if configured
      if config.editing.disable_textwidth then
        vim.bo.textwidth = 0
      end

      -- Set autowrite if configured
      if config.editing.auto_write then
        vim.opt_local.autowrite = true
      end
    end,
  })
end

-- Cancel ongoing request if any (wrapper)
M.cancel_request = function()
  return core.cancel_request()
end

-- Clean up spinner and prepare for response (wrapper)
M.cleanup_spinner = function(bufnr)
  return ui.cleanup_spinner(bufnr)
end

-- Handle the AI provider interaction (wrapper)
M.send_to_provider = function(opts)
  return core.send_to_provider(opts)
end

-- Parse buffer (wrapper)
M.parse_buffer = function(bufnr)
  return buffers.parse_buffer(bufnr)
end

-- Legacy function for backward compatibility
function M._get_last_request_body()
  return core._get_last_request_body()
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
