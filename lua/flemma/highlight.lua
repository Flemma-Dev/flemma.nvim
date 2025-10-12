--- Flemma syntax highlighting and theming functionality
--- Handles all highlight group definitions and syntax rules
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")
local core = require("flemma.core")

-- Helper function to set highlight groups
-- Accepts either:
--   - a highlight group name to link to (string)
--   - a hex color string (e.g., "#ff0000")
--   - a table with highlight attributes (e.g., { fg = "#ff0000", bold = true })
local function set_highlight(group_name, value)
  if type(value) == "table" then
    local hl_opts = vim.tbl_extend("force", {}, value)
    hl_opts.default = true
    vim.api.nvim_set_hl(0, group_name, hl_opts)
  elseif type(value) == "string" then
    if value:sub(1, 1) == "#" then
      -- Assume it's a hex color for foreground
      -- Add default = true to respect pre-existing user definitions
      vim.api.nvim_set_hl(0, group_name, { fg = value, default = true })
    else
      -- Assume it's a highlight group name to link
      -- Use the API function to link the highlight group in the global namespace (0)
      vim.api.nvim_set_hl(0, group_name, { link = value, default = true })
    end
  else
    log.error(string.format("set_highlight(): Invalid value type for group %s: %s", group_name, type(value)))
  end
end

-- Apply syntax highlighting and Tree-sitter configuration
M.apply_syntax = function()
  local syntax_config = state.get_config()

  -- Explicitly load our syntax file
  vim.cmd("runtime! syntax/chat.vim")

  -- Set highlights based on user config (link or hex color)
  set_highlight("FlemmaSystem", syntax_config.highlights.system)
  set_highlight("FlemmaUser", syntax_config.highlights.user)
  set_highlight("FlemmaAssistant", syntax_config.highlights.assistant)
  set_highlight("FlemmaUserLuaExpression", syntax_config.highlights.user_lua_expression) -- Highlight for {{expression}} in user messages
  set_highlight("FlemmaUserFileReference", syntax_config.highlights.user_file_reference) -- Highlight for @./file in user messages

  vim.api.nvim_set_hl(0, "FlemmaAssistantSpinner", { link = "FlemmaAssistant", default = true })

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

  -- Set highlight for thinking tags and blocks
  set_highlight("FlemmaThinkingTag", syntax_config.highlights.thinking_tag)
  set_highlight("FlemmaThinkingBlock", syntax_config.highlights.thinking_block)
end

-- Setup signs for different roles
local function setup_signs()
  local current_config = state.get_config()
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
end

-- Setup function to initialize highlighting functionality
M.setup = function()
  -- Set up signs
  setup_signs()

  -- Set up autocmd for the chat filetype
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    pattern = { "*.chat", "chat" },
    callback = function(ev)
      M.apply_syntax()
      -- Add rulers and thinking tag highlights via core module
      core.update_ui(ev.buf)
    end,
  })
end

return M
