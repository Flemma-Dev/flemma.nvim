--- Flemma plugin core functionality
--- Provides chat interface and API integration
local M = {}

local plugin_config = require("flemma.config")
local log = require("flemma.logging")
local provider_config = require("flemma.provider.config")
local state = require("flemma.state")
local textobject = require("flemma.textobject")
local core = require("flemma.core")

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

-- Navigation functions
local function find_next_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, cur_line, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^@[%w]+:") then
      -- Get the line and find position after the colon and whitespace
      local full_line = vim.api.nvim_buf_get_lines(0, cur_line + i - 1, cur_line + i, false)[1]
      local col = full_line:find(":%s*") + 1 -- Find position after the colon
      while full_line:sub(col, col) == " " do -- Skip any whitespace
        col = col + 1
      end
      vim.api.nvim_win_set_cursor(0, { cur_line + i, col - 1 })
      return true
    end
  end
  return false
end

local function find_prev_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1] - 2
  if cur_line < 0 then
    return false
  end

  for i = cur_line, 0, -1 do
    local line = vim.api.nvim_buf_get_lines(0, i, i + 1, false)[1]
    if line:match("^@[%w]+:") then
      -- Get the line and find position after the colon and whitespace
      local full_line = vim.api.nvim_buf_get_lines(0, i, i + 1, false)[1]
      local col = full_line:find(":%s*") + 1 -- Find position after the colon
      while full_line:sub(col, col) == " " do -- Skip any whitespace
        col = col + 1
      end
      vim.api.nvim_win_set_cursor(0, { i + 1, col - 1 })
      return true
    end
  end
  return false
end

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

  -- Helper function to toggle logging
  local function toggle_logging(enable)
    if enable == nil then
      enable = not log.is_enabled()
    end
    log.set_enabled(enable)
    if enable then
      vim.notify("Flemma: Logging enabled - " .. log.get_path())
    else
      vim.notify("Flemma: Logging disabled")
    end
  end

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

  -- Set up folding expression
  local function setup_folding()
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = 'v:lua.require("flemma.buffers").get_fold_level(v:lnum)'
    vim.wo.foldtext = 'v:lua.require("flemma.buffers").get_fold_text()'
    -- Start with all folds open
    vim.wo.foldlevel = 99
  end

  -- Add autocmd for updating rulers and signs (debounced via CursorHold)
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "VimResized", "CursorHold", "CursorHoldI" }, {
    pattern = "*.chat",
    callback = function(ev)
      -- Use the new function for debounced updates
      core.update_ui(ev.buf)
    end,
  })

  -- Create user commands
  vim.api.nvim_create_user_command("FlemmaSend", function()
    M.send_to_provider()
  end, {})

  vim.api.nvim_create_user_command("FlemmaCancel", function()
    M.cancel_request()
  end, {})

  vim.api.nvim_create_user_command("FlemmaImport", function()
    require("flemma.import").import_buffer()
  end, {})

  vim.api.nvim_create_user_command("FlemmaSendAndInsert", function()
    local bufnr = vim.api.nvim_get_current_buf()
    core.buffer_cmd(bufnr, "stopinsert")
    M.send_to_provider({
      on_complete = function()
        core.buffer_cmd(bufnr, "startinsert!")
      end,
    })
  end, {})

  -- Parse key=value arguments
  local function parse_key_value_args(args, start_index)
    local result = {}
    for i = start_index or 3, #args do
      local arg = args[i]
      local key, value = arg:match("^([%w_]+)=(.+)$")

      if key and value then
        -- Convert value to appropriate type
        if value == "true" then
          value = true
        elseif value == "false" then
          value = false
        elseif value == "nil" or value == "null" then
          value = nil
        elseif tonumber(value) then
          value = tonumber(value)
        end

        result[key] = value
      end
    end
    return result
  end

  -- Command to switch providers
  vim.api.nvim_create_user_command("FlemmaSwitch", function(opts)
    local args = opts.fargs

    if #args == 0 then
      -- Interactive selection if no arguments are provided
      local providers = {}
      for name, _ in pairs(provider_config.models) do
        table.insert(providers, name)
      end
      table.sort(providers) -- Sort providers for the selection list

      vim.ui.select(providers, { prompt = "Select Provider:" }, function(selected_provider)
        if not selected_provider then
          vim.notify("Flemma: Provider selection cancelled", vim.log.levels.INFO)
          return
        end

        -- Get models for the selected provider (unsorted)
        local models = provider_config.models[selected_provider] or {}
        if type(models) ~= "table" or #models == 0 then
          vim.notify("Flemma: No models found for provider " .. selected_provider, vim.log.levels.WARN)
          -- Switch to provider with default model
          core.switch_provider(selected_provider, nil, {})
          return
        end

        vim.ui.select(models, { prompt = "Select Model for " .. selected_provider .. ":" }, function(selected_model)
          if not selected_model then
            vim.notify("Flemma: Model selection cancelled", vim.log.levels.INFO)
            return
          end
          -- Call core.switch_provider with selected provider and model, no extra params
          core.switch_provider(selected_provider, selected_model, {})
        end)
      end)
    else
      -- Existing logic for handling command-line arguments
      local switch_opts = {
        provider = args[1],
      }

      if args[2] and not args[2]:match("^[%w_]+=") then
        switch_opts.model = args[2]
      end

      -- Parse any key=value pairs
      local key_value_args = parse_key_value_args(args, switch_opts.model and 3 or 2)
      for k, v in pairs(key_value_args) do
        switch_opts[k] = v
      end

      -- Call the refactored core.switch_provider function
      core.switch_provider(switch_opts.provider, switch_opts.model, key_value_args)
    end
  end, {
    nargs = "*", -- Allow zero arguments for interactive mode
    complete = function(arglead, cmdline, _)
      local args = vim.split(cmdline, "%s+", { trimempty = true })
      local num_args = #args
      local trailing_space = cmdline:match("%s$")

      -- If completing the provider name (argument 2)
      if num_args == 1 or (num_args == 2 and not trailing_space) then
        local providers = {}
        for name, _ in pairs(provider_config.models) do
          table.insert(providers, name)
        end
        table.sort(providers)
        return vim.tbl_filter(function(p)
          return vim.startswith(p, arglead)
        end, providers)
      -- If completing the model name (argument 3)
      elseif (num_args == 2 and trailing_space) or (num_args == 3 and not trailing_space) then
        local provider_name = args[2]
        -- Access the model list directly from the new structure
        local models = provider_config.models[provider_name] or {}

        -- Ensure models is a table before sorting and filtering
        if type(models) == "table" then
          -- Filter the original (unsorted) list
          return vim.tbl_filter(function(model)
            return vim.startswith(model, arglead)
          end, models)
        end
        -- If the provider doesn't exist or models isn't a table, return empty
        return {}
      end

      -- Default: return empty list if no completion matches
      return {}
    end,
  })

  -- Navigation commands
  vim.api.nvim_create_user_command("FlemmaNextMessage", function()
    find_next_message()
  end, {})

  vim.api.nvim_create_user_command("FlemmaPrevMessage", function()
    find_prev_message()
  end, {})

  -- Logging commands
  vim.api.nvim_create_user_command("FlemmaEnableLogging", function()
    toggle_logging(true)
  end, {})

  vim.api.nvim_create_user_command("FlemmaDisableLogging", function()
    toggle_logging(false)
  end, {})

  vim.api.nvim_create_user_command("FlemmaOpenLog", function()
    if not log.is_enabled() then
      vim.notify("Flemma: Logging is currently disabled", vim.log.levels.WARN)
      -- Give user time to see the warning
      vim.defer_fn(function()
        vim.cmd("tabedit " .. log.get_path())
      end, 1000)
    else
      vim.cmd("tabedit " .. log.get_path())
    end
  end, {})

  -- Command to recall last notification
  vim.api.nvim_create_user_command("FlemmaRecallNotification", function()
    require("flemma.notify").recall_last()
  end, {
    desc = "Recall the last notification",
  })

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
      setup_folding()

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

  -- Set up the mappings for Flemma interaction if enabled
  if config.keymaps.enabled then
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "chat",
      callback = function()
        -- Normal mode mappings
        if config.keymaps.normal.send then
          vim.keymap.set("n", config.keymaps.normal.send, function()
            M.send_to_provider()
          end, { buffer = true, desc = "Send to Flemma" })
        end

        if config.keymaps.normal.cancel then
          vim.keymap.set(
            "n",
            config.keymaps.normal.cancel,
            M.cancel_request,
            { buffer = true, desc = "Cancel Flemma Request" }
          )
        end

        -- Message navigation keymaps
        if config.keymaps.normal.next_message then
          vim.keymap.set(
            "n",
            config.keymaps.normal.next_message,
            find_next_message,
            { buffer = true, desc = "Jump to next message" }
          )
        end

        if config.keymaps.normal.prev_message then
          vim.keymap.set(
            "n",
            config.keymaps.normal.prev_message,
            find_prev_message,
            { buffer = true, desc = "Jump to previous message" }
          )
        end

        -- Set up text objects with configured key
        textobject.setup({ text_object = config.text_object })

        -- Insert mode mapping - send and return to insert mode
        if config.keymaps.insert.send then
          vim.keymap.set("i", config.keymaps.insert.send, function()
            local bufnr = vim.api.nvim_get_current_buf()
            core.buffer_cmd(bufnr, "stopinsert")
            M.send_to_provider({
              on_complete = function()
                core.buffer_cmd(bufnr, "startinsert!")
              end,
            })
          end, { buffer = true, desc = "Send to Flemma and continue editing" })
        end
      end,
    })
  end
end

-- Place signs for a message
local function place_signs(bufnr, start_line, end_line, role)
  if not config.signs.enabled then
    return
  end

  -- Map the display role ("You", "System", "Assistant") to the internal config key ("user", "system", "assistant")
  local internal_role_key = string.lower(role) -- Default to lowercase
  if role == "You" then
    internal_role_key = "user" -- Map "You" specifically to "user"
  end

  local sign_name = "flemma_" .. internal_role_key -- Construct sign name like "flemma_user"
  local sign_config = config.signs[internal_role_key] -- Look up config using "user", "system", etc.

  -- Check if the sign is actually defined before trying to place it
  if vim.fn.sign_getdefined(sign_name) == {} then
    log.debug("place_signs(): Sign not defined: " .. sign_name .. " for role " .. role)
    return
  end

  if sign_config and sign_config.hl ~= false then
    for lnum = start_line, end_line do
      vim.fn.sign_place(0, "flemma_ns", sign_name, bufnr, { lnum = lnum })
    end
  end
end

-- Parse a single message from lines
local function parse_message(bufnr, lines, start_idx, frontmatter_offset)
  local line = lines[start_idx]
  local msg_type = line:match("^@([%w]+):")
  if not msg_type then
    return nil, start_idx
  end

  local content = {}
  local i = start_idx
  -- Remove the role marker (e.g., @You:) from the first line
  local first_content = line:sub(#msg_type + 3)
  if first_content:match("%S") then
    content[#content + 1] = first_content:gsub("^%s*", "")
  end

  i = i + 1
  -- Collect lines until we hit another role marker or end of buffer
  while i <= #lines do
    local next_line = lines[i]
    if next_line:match("^@[%w]+:") then
      break
    end
    if next_line:match("%S") or #content > 0 then
      content[#content + 1] = next_line
    end
    i = i + 1
  end

  local result = {
    type = msg_type,
    content = table.concat(content, "\n"):gsub("%s+$", ""),
    start_line = start_idx,
    end_line = i - 1,
  }

  -- Place signs for the message, adjusting for frontmatter
  place_signs(bufnr, result.start_line + frontmatter_offset, result.end_line + frontmatter_offset, msg_type)

  return result, i - 1
end

-- Parse the entire buffer into a sequence of messages
function M.parse_buffer(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local messages = {}

  -- Handle frontmatter if present
  local frontmatter = require("flemma.frontmatter")
  local fm_code, content = frontmatter.parse(lines)

  -- Calculate frontmatter offset for sign placement
  local frontmatter_offset = 0
  if fm_code then
    -- Count lines in frontmatter (code + delimiters)
    frontmatter_offset = #vim.split(fm_code, "\n", true) + 2
  end

  -- If no frontmatter was found, use all lines as content
  content = content or lines

  local i = 1
  while i <= #content do
    local msg, last_idx = parse_message(bufnr, content, i, frontmatter_offset)
    if msg then
      messages[#messages + 1] = msg
      i = last_idx + 1
    else
      i = i + 1
    end
  end

  return messages, fm_code
end

-- Cancel ongoing request if any (wrapper)
M.cancel_request = function()
  return core.cancel_request()
end

-- Clean up spinner and prepare for response (wrapper)
M.cleanup_spinner = function(bufnr)
  return core.cleanup_spinner(bufnr)
end

-- Handle the AI provider interaction (wrapper)
M.send_to_provider = function(opts)
  return core.send_to_provider(opts)
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
