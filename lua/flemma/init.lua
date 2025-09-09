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

-- Helper function to set highlight groups
-- Accepts either a highlight group name to link to, or a hex color string (e.g., "#ff0000")
local function set_highlight(group_name, value)
  if type(value) ~= "string" then
    log.error(string.format("set_highlight(): Invalid value type for group %s: %s", group_name, type(value)))
    return
  end

  if value:sub(1, 1) == "#" then
    -- Assume it's a hex color for foreground
    -- Add default = true to respect pre-existing user definitions
    vim.api.nvim_set_hl(0, group_name, { fg = value, default = true })
  else
    -- Assume it's a highlight group name to link
    -- Use the API function to link the highlight group in the global namespace (0)
    vim.api.nvim_set_hl(0, group_name, { link = value, default = true })
  end
end

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

  -- Define sign groups for each role
  current_config = state.get_config()
  if current_config.signs.enabled then
    -- Define signs using internal keys ('user', 'system', 'assistant')
    local signs = {
      ["user"] = { config = current_config.signs.user, highlight = current_config.highlights.user },
      ["system"] = { config = current_config.signs.system, highlight = current_config.highlights.system },
      ["assistant"] = { config = current_config.signs.assistant, highlight = current_config.highlights.assistant },
    }
    -- Iterate using internal keys
    for internal_role_key, sign_data in pairs(signs) do
      -- Define the specific highlight group name for the sign (e.g., FlemmaSignUser)
      local sign_hl_group = "FlemmaSign" .. internal_role_key:sub(1, 1):upper() .. internal_role_key:sub(2)

      -- Set the sign highlight group if highlighting is enabled
      if sign_data.config.hl ~= false then
        local target_hl = sign_data.config.hl == true and sign_data.highlight or sign_data.config.hl
        set_highlight(sign_hl_group, target_hl) -- Use the helper function

        -- Define the sign using the internal key (e.g., flemma_user)
        local sign_name = "flemma_" .. internal_role_key
        vim.fn.sign_define(sign_name, {
          text = sign_data.config.char or current_config.signs.char,
          texthl = sign_hl_group, -- Use the linked group
        })
      else
        -- Define the sign without a highlight group if hl is false
        local sign_name = "flemma_" .. internal_role_key
        vim.fn.sign_define(sign_name, {
          text = sign_data.config.char or current_config.signs.char,
          -- texthl is omitted
        })
      end
    end
  end

  -- Define syntax highlighting and Tree-sitter configuration
  local function set_syntax()
    local syntax_config = state.get_config()

    -- Explicitly load our syntax file
    vim.cmd("runtime! syntax/chat.vim")

    -- Set highlights based on user config (link or hex color)
    set_highlight("FlemmaSystem", syntax_config.highlights.system)
    set_highlight("FlemmaUser", syntax_config.highlights.user)
    set_highlight("FlemmaAssistant", syntax_config.highlights.assistant)
    set_highlight("FlemmaUserLuaExpression", syntax_config.highlights.user_lua_expression) -- Highlight for {{expression}} in user messages
    set_highlight("FlemmaUserFileReference", syntax_config.highlights.user_file_reference) -- Highlight for @./file in user messages

    -- Set up role marker highlights (e.g., @You:, @System:)
    -- Use existing highlight groups which are now correctly defined by set_highlight
    vim.cmd(string.format(
      [[
      execute 'highlight FlemmaRoleSystem guifg=' . synIDattr(synIDtrans(hlID("FlemmaSystem")), "fg", "gui") . ' gui=%s'
      execute 'highlight FlemmaRoleUser guifg=' . synIDattr(synIDtrans(hlID("FlemmaUser")), "fg", "gui") . ' gui=%s'
      execute 'highlight FlemmaRoleAssistant guifg=' . synIDattr(synIDtrans(hlID("FlemmaAssistant")), "fg", "gui") . ' gui=%s'
    ]],
      syntax_config.role_style,
      syntax_config.role_style,
      syntax_config.role_style
    ))

    -- Set ruler highlight group
    set_highlight("FlemmaRuler", syntax_config.ruler.hl)
  end

  -- Set up UI module
  ui.setup()

  -- Set up user commands
  commands.setup()

  -- Set up keymaps
  keymaps.setup()

  -- Set up autocmd for the chat filetype
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    pattern = { "*.chat", "chat" },
    callback = function(ev)
      set_syntax()
      -- Add rulers via core module
      core.update_ui(ev.buf)
    end,
  })

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
