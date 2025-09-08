--- Flemma plugin core functionality
--- Provides chat interface and API integration
local M = {}
local last_request_body_for_testing = nil -- For testing purposes

local buffers = require("flemma.buffers")
local plugin_config = require("flemma.config")
local log = require("flemma.logging")
local provider_config = require("flemma.provider.config")
local state = require("flemma.state")
local textobject = require("flemma.textobject")
local config_manager = require("flemma.core.config_manager")

local provider = nil

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

local ns_id = vim.api.nvim_create_namespace("flemma")

-- Execute a command in the context of a specific buffer
local function buffer_cmd(bufnr, cmd)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    -- If buffer has no window, do nothing
    return
  end
  vim.fn.win_execute(winid, "noautocmd " .. cmd)
end

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

-- Helper function to add rulers
local function add_rulers(bufnr)
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^@[%w]+:") then
      -- If this isn't the first line, add a ruler before it
      if i > 1 then
        -- Create virtual line with ruler using the FlemmaRuler highlight group
        local ruler_text = string.rep(state.get_config().ruler.char, math.floor(vim.api.nvim_win_get_width(0) * 1))
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, i - 1, 0, {
          virt_lines = { { { ruler_text, "FlemmaRuler" } } }, -- Use defined group
          virt_lines_above = true,
        })
      end
    end
  end
end

-- Helper function to fold the last thinking block in a buffer
local function fold_last_thinking_block(bufnr)
  log.debug("fold_last_thinking_block(): Attempting to fold last thinking block in buffer " .. bufnr)
  local num_lines = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) -- 0-indexed lines

  -- Find the line number of the last @You: prompt to define the search boundary.
  -- We search upwards from this prompt.
  local last_you_prompt_lnum_0idx = -1
  for l = num_lines - 1, 0, -1 do -- Iterate 0-indexed line numbers
    if lines[l + 1]:match("^@You:%s*") then -- lines table is 1-indexed
      last_you_prompt_lnum_0idx = l
      break
    end
  end

  if last_you_prompt_lnum_0idx == -1 then
    log.debug("fold_last_thinking_block(): Could not find the last @You: prompt. Aborting.")
    return
  end

  local end_think_lnum_0idx = -1
  -- Search for </thinking> upwards from just before the last @You: prompt.
  -- Stop if we hit another message type, ensuring we're in the last message block.
  for l = last_you_prompt_lnum_0idx - 1, 0, -1 do
    if lines[l + 1]:match("^</thinking>$") then
      end_think_lnum_0idx = l
      break
    end
    -- If we encounter another role marker before finding </thinking>,
    -- it means the last message block didn't have a thinking tag.
    if lines[l + 1]:match("^@[%w]+:") then
      log.debug(
        "fold_last_thinking_block(): Encountered another role marker before </thinking> in the last message segment."
      )
      return
    end
  end

  if end_think_lnum_0idx == -1 then
    log.debug("fold_last_thinking_block(): No </thinking> tag found in the last message segment.")
    return
  end

  local start_think_lnum_0idx = -1
  -- Search for <thinking> upwards from just before the found </thinking> tag.
  -- Stop if we hit another message type.
  for l = end_think_lnum_0idx - 1, 0, -1 do
    if lines[l + 1]:match("^<thinking>$") then
      start_think_lnum_0idx = l
      break
    end
    if lines[l + 1]:match("^@[%w]+:") then
      log.debug("fold_last_thinking_block(): Encountered another role marker before finding matching <thinking> tag.")
      return
    end
  end

  if start_think_lnum_0idx ~= -1 and start_think_lnum_0idx < end_think_lnum_0idx then
    log.debug(
      string.format(
        "fold_last_thinking_block(): Found thinking block from line %d to %d (1-indexed). Closing fold.",
        start_think_lnum_0idx + 1,
        end_think_lnum_0idx + 1
      )
    )
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      -- vim.cmd uses 1-based line numbers
      vim.fn.win_execute(
        winid,
        string.format("%d,%d foldclose", start_think_lnum_0idx + 1, end_think_lnum_0idx + 1) -- Corrected to foldclose and added space
      )
      log.debug("fold_last_thinking_block(): Executed foldclose command via win_execute.")
    else
      log.debug("fold_last_thinking_block(): Buffer " .. bufnr .. " has no window. Cannot close fold.")
    end
  else
    log.debug(
      "fold_last_thinking_block(): No matching <thinking> tag found for the last </thinking> tag, or order is incorrect."
    )
  end
end

-- Helper function to force UI update (rulers and signs)
local function update_ui(bufnr)
  -- Ensure buffer is valid before proceeding
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.debug("update_ui(): Invalid buffer: " .. bufnr)
    return
  end
  add_rulers(bufnr)
  -- Clear and reapply all signs
  vim.fn.sign_unplace("flemma_ns", { buffer = bufnr })
  M.parse_buffer(bufnr) -- This will reapply signs
end

-- Helper function to auto-write the buffer if enabled
local function auto_write_buffer(bufnr)
  if state.get_config().editing.auto_write and vim.bo[bufnr].modified then
    log.debug("auto_write_buffer(): bufnr = " .. bufnr)
    buffer_cmd(bufnr, "silent! write")
  end
end

-- Initialize or switch provider based on configuration
local function initialize_provider(provider_name, model_name, parameters)
  -- Prepare configuration using the centralized config manager
  local provider_config, err = config_manager.prepare_config(provider_name, model_name, parameters)
  if not provider_config then
    vim.notify(err, vim.log.levels.ERROR)
    return nil
  end

  -- Apply the configuration to global state
  config_manager.apply_config(provider_config)

  -- Create a fresh provider instance with the merged parameters
  local new_provider
  if provider_config.provider == "openai" then
    new_provider = require("flemma.provider.openai").new(provider_config.parameters)
  elseif provider_config.provider == "vertex" then
    new_provider = require("flemma.provider.vertex").new(provider_config.parameters)
  elseif provider_config.provider == "claude" then
    new_provider = require("flemma.provider.claude").new(provider_config.parameters)
  else
    -- This should never happen since config_manager validates the provider
    local err_msg = "initialize_provider(): Invalid provider after validation: " .. tostring(provider_config.provider)
    log.error(err_msg)
    return nil
  end

  -- Update the global provider reference
  state.set_provider(new_provider)

  return new_provider
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
  initialize_provider(current_config.provider, current_config.model, current_config.parameters)

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
      update_ui(ev.buf)
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
    buffer_cmd(bufnr, "stopinsert")
    M.send_to_provider({
      on_complete = function()
        buffer_cmd(bufnr, "startinsert!")
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
          M.switch(selected_provider, nil, {})
          return
        end

        vim.ui.select(models, { prompt = "Select Model for " .. selected_provider .. ":" }, function(selected_model)
          if not selected_model then
            vim.notify("Flemma: Model selection cancelled", vim.log.levels.INFO)
            return
          end
          -- Call M.switch with selected provider and model, no extra params
          M.switch(selected_provider, selected_model, {})
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

      -- Call the refactored M.switch function
      M.switch(switch_opts.provider, switch_opts.model, key_value_args)
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
      add_rulers(ev.buf)
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
            buffer_cmd(bufnr, "stopinsert")
            M.send_to_provider({
              on_complete = function()
                buffer_cmd(bufnr, "startinsert!")
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

-- Cancel ongoing request if any
function M.cancel_request()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer_state = buffers.get_state(bufnr)

  if buffer_state.current_request then
    log.info("cancel_request(): job_id = " .. tostring(buffer_state.current_request))

    -- Mark as cancelled
    buffer_state.request_cancelled = true

    -- Use provider to cancel the request
    local current_provider = state.get_provider()
    if current_provider and current_provider:cancel_request(buffer_state.current_request) then
      buffer_state.current_request = nil

      -- Clean up the buffer
      local last_line = vim.api.nvim_buf_line_count(bufnr)
      local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

      -- If we're still showing the thinking message, remove it
      if last_line_content:match("^@Assistant:.*Thinking%.%.%.$") then
        log.debug("cancel_request(): ... Cleaning up 'Thinking...' message")
        M.cleanup_spinner(bufnr)
      end

      -- Auto-write if enabled and we've received some content
      if buffer_state.request_cancelled and not last_line_content:match("^@Assistant:.*Thinking%.%.%.$") then
        auto_write_buffer(bufnr)
      end

      vim.bo[bufnr].modifiable = true -- Restore modifiable state

      local msg = "Flemma: Request cancelled"
      if log.is_enabled() then
        msg = msg .. ". See " .. log.get_path() .. " for details"
      end
      vim.notify(msg, vim.log.levels.INFO)
      -- Force UI update after cancellation
      update_ui(bufnr)
    end
  else
    log.debug("cancel_request(): No current request found")
    -- If there was no request, ensure buffer is modifiable if it somehow got stuck
    if not vim.bo[bufnr].modifiable then
      vim.bo[bufnr].modifiable = true
    end
  end
end

-- Clean up spinner and prepare for response
M.cleanup_spinner = function(bufnr)
  local original_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true -- Allow plugin modifications

  local buffer_state = buffers.get_state(bufnr)
  if buffer_state.spinner_timer then
    vim.fn.timer_stop(buffer_state.spinner_timer)
    buffer_state.spinner_timer = nil
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1) -- Clear rulers/virtual text

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    update_ui(bufnr) -- Ensure UI is clean even if buffer is empty
    return
  end

  local last_line_content = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]

  -- Only modify lines if the last line is actually the spinner message
  if last_line_content and last_line_content:match("^@Assistant: .*Thinking%.%.%.$") then
    buffer_cmd(bufnr, "undojoin") -- Group changes for undo

    -- Get the line before the "Thinking..." message (if it exists)
    local prev_line_actual_content = nil
    if line_count > 1 then
      prev_line_actual_content = vim.api.nvim_buf_get_lines(bufnr, line_count - 2, line_count - 1, false)[1]
    end

    -- Ensure we maintain a blank line if needed, or remove the spinner line
    if prev_line_actual_content and prev_line_actual_content:match("%S") then
      -- Previous line has content, replace spinner line with a blank line
      vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, { "" })
    else
      -- Previous line is blank or doesn't exist, remove the spinner line entirely
      vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, {})
    end
  else
    log.debug("cleanup_spinner(): Last line is not the 'Thinking...' message, not modifying lines.")
  end

  update_ui(bufnr) -- Force UI update after cleaning up spinner
  vim.bo[bufnr].modifiable = original_modifiable -- Restore previous modifiable state
end

-- Show loading spinner
local function start_loading_spinner(bufnr)
  local original_modifiable_initial = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true -- Allow plugin modifications for initial message

  local buffer_state = buffers.get_state(bufnr)
  local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 1

  -- Clear any existing virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Check if we need to add a blank line
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines > 0 and lines[#lines]:match("%S") then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "@Assistant: Thinking..." })
  else
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant: Thinking..." })
  end
  -- Immediately update UI after adding the thinking message
  update_ui(bufnr)
  vim.bo[bufnr].modifiable = original_modifiable_initial -- Restore state after initial message

  local timer = vim.fn.timer_start(100, function()
    if not buffer_state.current_request then
      return
    end

    local original_modifiable_timer = vim.bo[bufnr].modifiable
    vim.bo[bufnr].modifiable = true -- Allow plugin modifications for spinner update

    frame = (frame % #spinner_frames) + 1
    local text = "@Assistant: " .. spinner_frames[frame] .. " Thinking..."
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    buffer_cmd(bufnr, "undojoin")
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { text })
    -- Force UI update during spinner animation
    update_ui(bufnr)

    vim.bo[bufnr].modifiable = original_modifiable_timer -- Restore state after spinner update
  end, { ["repeat"] = -1 })

  buffer_state.spinner_timer = timer
  return timer
end

-- Handle the AI provider interaction
function M.send_to_provider(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer_state = buffers.get_state(bufnr)

  -- Check if there's already a request in progress
  if buffer_state.current_request then
    vim.notify("Flemma: A request is already in progress. Use <C-c> to cancel it first.", vim.log.levels.WARN)
    return
  end

  log.info("send_to_provider(): Starting new request for buffer " .. bufnr)
  buffer_state.request_cancelled = false
  buffer_state.api_error_occurred = false -- Initialize flag for API errors

  -- Make buffer non-modifiable by user during request
  vim.bo[bufnr].modifiable = false

  -- Auto-write the buffer before sending if enabled
  auto_write_buffer(bufnr)

  -- Ensure we have a valid provider
  local current_provider = state.get_provider()
  if not current_provider then
    log.error("send_to_provider(): Provider not initialized")
    vim.notify("Flemma: Provider not initialized", vim.log.levels.ERROR)
    vim.bo[bufnr].modifiable = true -- Restore modifiable state
    return
  end

  -- Check if we need to prompt for API key
  local api_key_result, api_key_error = pcall(function()
    return current_provider:get_api_key()
  end)

  if not api_key_result then
    -- There was an error getting the API key
    log.error("send_to_provider(): Error getting API key: " .. tostring(api_key_error))

    -- Get provider-specific authentication notes if available
    local auth_notes = provider_config.auth_notes and provider_config.auth_notes[config.provider]

    if auth_notes then
      -- Show a more detailed alert with the auth notes
      require("flemma.notify").alert(
        tostring(api_key_error):gsub("%s+$", "") .. "\n\n---\n\n" .. auth_notes,
        { title = "Flemma - Authentication Error: " .. config.provider }
      )
    else
      require("flemma.notify").alert(tostring(api_key_error), { title = "Flemma - Authentication Error" })
    end
    return
  end

  if not api_key_error and not current_provider.state.api_key then
    log.info("send_to_provider(): No API key found, prompting user")
    vim.ui.input({
      prompt = "Enter your API key: ",
      default = "",
      border = "rounded",
      title = " Flemma - API Key Required ",
      relative = "editor",
    }, function(input)
      if input then
        current_provider.state.api_key = input
        log.info("send_to_provider(): API key set via prompt")
        -- Continue with the Flemma request immediately
        M.send_to_provider() -- This recursive call will handle modifiable state
      else
        log.error("send_to_provider(): API key prompt cancelled by user")
        vim.notify("Flemma: API key required to continue", vim.log.levels.ERROR)
        vim.bo[bufnr].modifiable = true -- Restore modifiable state
      end
    end)

    -- Return early since we'll continue in the callback
    return
  end

  local messages, frontmatter_code = M.parse_buffer(bufnr)
  if #messages == 0 then
    vim.notify("Flemma: No messages found in buffer", vim.log.levels.WARN)
    vim.bo[bufnr].modifiable = true -- Restore modifiable state
    return
  end

  -- Execute frontmatter if present and get variables
  local template_vars = {}
  local chat_file_path = vim.api.nvim_buf_get_name(bufnr) -- Used for frontmatter and message templating context

  if frontmatter_code then
    log.debug(
      "send_to_provider(): Evaluating frontmatter code for file '"
        .. chat_file_path
        .. "': "
        .. log.inspect(frontmatter_code)
    )
    -- Pass chat_file_path to set up __filename for include() in frontmatter
    local ok, result = pcall(require("flemma.frontmatter").execute, frontmatter_code, chat_file_path)
    if not ok then
      vim.notify("Flemma: Frontmatter evaluation failed:\n• " .. result, vim.log.levels.ERROR)
      vim.bo[bufnr].modifiable = true -- Restore modifiable state
      return
    end
    log.debug("send_to_provider(): ... Frontmatter evaluation result: " .. log.inspect(result))
    template_vars = result
  end

  local formatted_messages, system_message = current_provider:format_messages(messages)

  -- Process template expressions in messages
  local eval = require("flemma.eval")
  -- Create base env for message templating, extending with frontmatter variables
  local env = vim.tbl_extend("force", eval.create_safe_env(), template_vars)
  -- Set __filename and __include_stack for include() in message content
  env.__filename = chat_file_path
  env.__include_stack = { chat_file_path } -- Initialize stack with the main chat file

  -- Collect all template evaluation errors before processing
  local template_errors = {}

  for i, msg in ipairs(formatted_messages) do
    -- Look for {{expression}} patterns
    msg.content = msg.content:gsub("{{(.-)}}", function(expr)
      log.debug(
        string.format("send_to_provider(): Evaluating template expression (message %d): %s", i, log.inspect(expr))
      )
      local ok, result = pcall(eval.eval_expression, expr, env)
      if not ok then
        -- result is the detailed error string from eval.lua
        local current_file_for_error = env.__filename
        if not current_file_for_error or current_file_for_error == "" then
          current_file_for_error = vim.api.nvim_buf_get_name(bufnr) -- Fallback if env.__filename is empty
          if not current_file_for_error or current_file_for_error == "" then
            current_file_for_error = "current buffer"
          end
        end

        -- Collect error instead of showing immediately
        table.insert(template_errors, {
          message_index = i,
          expression = expr,
          file_path = current_file_for_error,
          error_details = result,
        })

        -- For logging, keep it on one line for easier parsing if needed
        local err_msg_for_log = string.format(
          "Template error (message %d) processing '{{%s}}' in '%s': %s",
          i,
          expr,
          current_file_for_error,
          result
        )
        log.error("send_to_provider(): " .. err_msg_for_log)
        return "{{" .. expr .. "}}" -- Keep original on error
      end
      log.debug(string.format("send_to_provider(): ... Expression result (message %d): %s", i, log.inspect(result)))
      return tostring(result)
    end)
  end

  -- Show aggregated template errors if any occurred
  if #template_errors > 0 then
    local error_lines = {}
    table.insert(
      error_lines,
      string.format(
        "Template evaluation failed for %d expression%s:",
        #template_errors,
        #template_errors == 1 and "" or "s"
      )
    )

    for _, error_info in ipairs(template_errors) do
      table.insert(
        error_lines,
        string.format(
          "• Message #%d: '{{%s}}' in '%s'",
          error_info.message_index,
          error_info.expression,
          error_info.file_path
        )
      )
      table.insert(error_lines, string.format("  %s", error_info.error_details))
    end

    vim.notify("Flemma: " .. table.concat(error_lines, "\n"), vim.log.levels.WARN)
  end

  -- Create request body using the validated model stored in the provider
  local request_body = current_provider:create_request_body(formatted_messages, system_message)
  last_request_body_for_testing = request_body -- Store for testing

  -- Log the request details (using the provider's stored model)
  log.debug(
    "send_to_provider(): Sending request for provider "
      .. log.inspect(state.get_config().provider)
      .. " with model "
      .. log.inspect(current_provider.parameters.model)
  )

  local spinner_timer = start_loading_spinner(bufnr) -- Handles its own modifiable toggles for writes
  local response_started = false

  -- Format usage information for display
  local function format_usage(current, session)
    local pricing = require("flemma.pricing")
    local lines = {}

    -- Request usage
    if
      current
      and (
        current.input_tokens > 0
        or current.output_tokens > 0
        or (current.thoughts_tokens and current.thoughts_tokens > 0)
      )
    then
      local total_output_tokens_for_cost = (current.output_tokens or 0) + (current.thoughts_tokens or 0)
      local current_cost = config.pricing.enabled
        and pricing.calculate_cost(config.model, current.input_tokens, total_output_tokens_for_cost)
      table.insert(lines, "Request:")
      -- Add model and provider information
      table.insert(lines, string.format("  Model:  `%s` (%s)", config.model, config.provider))
      if current_cost then
        table.insert(lines, string.format("  Input:  %d tokens / $%.2f", current.input_tokens or 0, current_cost.input))
        local display_output_tokens = (current.output_tokens or 0) + (current.thoughts_tokens or 0)
        local output_display_string
        if current.thoughts_tokens and current.thoughts_tokens > 0 then
          output_display_string = string.format(
            " Output:  %d tokens (⊂ %d thoughts) / $%.2f",
            display_output_tokens,
            current.thoughts_tokens,
            current_cost.output
          )
        else
          output_display_string =
            string.format(" Output:  %d tokens / $%.2f", display_output_tokens, current_cost.output)
        end
        table.insert(lines, output_display_string)
        table.insert(lines, string.format("  Total:  $%.2f", current_cost.total))
      else
        table.insert(lines, string.format("  Input:  %d tokens", current.input_tokens or 0))
        local display_output_tokens = (current.output_tokens or 0) + (current.thoughts_tokens or 0)
        local output_display_string
        if current.thoughts_tokens and current.thoughts_tokens > 0 then
          output_display_string =
            string.format(" Output:  %d tokens (⊂ %d thoughts)", display_output_tokens, current.thoughts_tokens)
        else
          output_display_string = string.format(" Output:  %d tokens", display_output_tokens)
        end
        table.insert(lines, output_display_string)
      end
    end

    -- Session totals
    if session and (session.input_tokens > 0 or session.output_tokens > 0) then
      local total_session_output_tokens_for_cost = (session.output_tokens or 0) + (session.thoughts_tokens or 0)
      local session_cost = config.pricing.enabled
        and pricing.calculate_cost(config.model, session.input_tokens, total_session_output_tokens_for_cost)
      if #lines > 0 then
        table.insert(lines, "")
      end
      table.insert(lines, "Session:")
      if session_cost then
        table.insert(lines, string.format("  Input:  %d tokens / $%.2f", session.input_tokens or 0, session_cost.input))
        local display_session_output_tokens = (session.output_tokens or 0) + (session.thoughts_tokens or 0)
        table.insert(
          lines,
          string.format(" Output:  %d tokens / $%.2f", display_session_output_tokens, session_cost.output)
        )
        table.insert(lines, string.format("  Total:  $%.2f", session_cost.total))
      else
        table.insert(lines, string.format("  Input:  %d tokens", session.input_tokens or 0))
        local display_session_output_tokens = (session.output_tokens or 0) + (session.thoughts_tokens or 0)
        table.insert(lines, string.format(" Output:  %d tokens", display_session_output_tokens))
      end
    end
    return table.concat(lines, "\n")
  end

  -- Reset usage tracking for this buffer
  buffer_state.current_usage = {
    input_tokens = 0,
    output_tokens = 0,
    thoughts_tokens = 0,
  }

  -- Set up callbacks for the provider
  local callbacks = {
    on_data = function(line)
      -- Don't log here as it's already logged in process_response_line
    end,

    on_stderr = function(line)
      log.error("send_to_provider(): callbacks.on_stderr: " .. line)
    end,

    on_error = function(msg)
      vim.schedule(function()
        if spinner_timer then
          vim.fn.timer_stop(spinner_timer)
        end
        M.cleanup_spinner(bufnr) -- Handles its own modifiable toggles
        buffer_state.current_request = nil
        buffer_state.api_error_occurred = true -- Set flag indicating API error

        vim.bo[bufnr].modifiable = true -- Restore modifiable state

        -- Auto-write on error if enabled
        auto_write_buffer(bufnr)

        local notify_msg = "Flemma: " .. msg
        if log.is_enabled() then
          notify_msg = notify_msg .. ". See " .. log.get_path() .. " for details"
        end
        vim.notify(notify_msg, vim.log.levels.ERROR)
      end)
    end,

    on_done = function()
      vim.schedule(function()
        -- This callback is called by the provider's on_exit handler.
        -- Most finalization logic (spinner, state, UI, prompt) is now handled
        -- in on_complete based on the cURL exit code and response_started state.
        log.debug("send_to_provider(): callbacks.on_done called.")
      end)
    end,

    on_usage = function(usage_data)
      if usage_data.type == "input" then
        buffer_state.current_usage.input_tokens = usage_data.tokens
      elseif usage_data.type == "output" then
        buffer_state.current_usage.output_tokens = usage_data.tokens
      elseif usage_data.type == "thoughts" then
        buffer_state.current_usage.thoughts_tokens = usage_data.tokens
      end
    end,

    on_message_complete = function()
      vim.schedule(function()
        -- Update session totals
        state.update_session_usage({
          input_tokens = buffer_state.current_usage.input_tokens or 0,
          output_tokens = buffer_state.current_usage.output_tokens or 0,
          thoughts_tokens = buffer_state.current_usage.thoughts_tokens or 0,
        })

        -- Auto-write when response is complete
        auto_write_buffer(bufnr)

        -- Format and display usage information using our custom notification
        local usage_str = format_usage(buffer_state.current_usage, state.get_session_usage())
        if usage_str ~= "" then
          local notify_opts = vim.tbl_deep_extend("force", state.get_config().notify, {
            title = "Usage",
          })
          require("flemma.notify").show(usage_str, notify_opts)
        end
        -- Reset current usage for next request
        buffer_state.current_usage = {
          input_tokens = 0,
          output_tokens = 0,
          thoughts_tokens = 0,
        }
      end)
    end,

    on_content = function(text)
      vim.schedule(function()
        local original_modifiable_for_on_content = vim.bo[bufnr].modifiable -- Expected to be false
        vim.bo[bufnr].modifiable = true -- Temporarily allow plugin modifications

        -- Stop spinner on first content
        if not response_started then
          if spinner_timer then
            vim.fn.timer_stop(spinner_timer)
            -- spinner_timer = nil -- Not strictly needed here as it's local to send_to_provider
          end
        end

        -- Split content into lines
        local lines = vim.split(text, "\n", { plain = true })

        if #lines > 0 then
          local last_line = vim.api.nvim_buf_line_count(bufnr)

          if not response_started then
            -- Clean up spinner and ensure blank line
            M.cleanup_spinner(bufnr) -- Handles its own modifiable toggles
            last_line = vim.api.nvim_buf_line_count(bufnr)

            -- Check if response starts with a code fence
            if lines[1]:match("^```") then
              -- Add a newline before the code fence
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant:", lines[1] })
            else
              -- Start with @Assistant: prefix as normal
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant: " .. lines[1] })
            end

            -- Add remaining lines if any
            if #lines > 1 then
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line + 1, last_line + 1, false, { unpack(lines, 2) })
            end
          else
            -- Get the last line's content
            local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

            if #lines == 1 then
              -- Just append to the last line
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { last_line_content .. lines[1] })
            else
              -- First chunk goes to the end of the last line
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { last_line_content .. lines[1] })

              -- Remaining lines get added as new lines
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { unpack(lines, 2) })
            end
          end

          response_started = true
          -- Force UI update after appending content
          update_ui(bufnr)
        end
        vim.bo[bufnr].modifiable = original_modifiable_for_on_content -- Restore to likely false
      end)
    end,

    on_complete = function(code)
      vim.schedule(function()
        -- If the request was cancelled, M.cancel_request() handles cleanup including modifiable.
        if buffer_state.request_cancelled then
          -- M.cancel_request should have already set modifiable = true
          -- and stopped the spinner.
          if spinner_timer then
            vim.fn.timer_stop(spinner_timer)
            spinner_timer = nil
          end
          return
        end

        -- Stop the spinner timer if it's still active.
        -- on_content might have already stopped it if response_started.
        -- M.cleanup_spinner will also try to stop state.spinner_timer.
        if spinner_timer then
          vim.fn.timer_stop(spinner_timer)
          spinner_timer = nil
        end
        buffer_state.current_request = nil -- Mark request as no longer current

        -- Ensure buffer is modifiable for final operations and user interaction
        vim.bo[bufnr].modifiable = true

        if code == 0 then
          -- cURL request completed successfully (exit code 0)
          if buffer_state.api_error_occurred then
            log.info(
              "send_to_provider(): on_complete: cURL success (code 0), but an API error was previously handled. Skipping new prompt."
            )
            buffer_state.api_error_occurred = false -- Reset flag for next request
            if not response_started then
              M.cleanup_spinner(bufnr) -- Handles its own modifiable toggles
            end
            auto_write_buffer(bufnr) -- Still auto-write if configured
            update_ui(bufnr) -- Update UI
            return -- Do not proceed to add new prompt or call opts.on_complete
          end

          if not response_started then
            log.info(
              "send_to_provider(): on_complete: cURL success (code 0), no API error, but no response content was processed."
            )
            M.cleanup_spinner(bufnr) -- Handles its own modifiable toggles
          end

          -- Add new "@You:" prompt for the next message (buffer is already modifiable)
          local last_line_idx = vim.api.nvim_buf_line_count(bufnr)
          local last_line_content = ""
          if last_line_idx > 0 then
            last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line_idx - 1, last_line_idx, false)[1] or ""
          end

          local lines_to_insert = {}
          local cursor_line_offset = 1
          if last_line_content == "" then
            lines_to_insert = { "@You: " }
          else
            lines_to_insert = { "", "@You: " }
            cursor_line_offset = 2
          end

          buffer_cmd(bufnr, "undojoin")
          vim.api.nvim_buf_set_lines(bufnr, last_line_idx, last_line_idx, false, lines_to_insert)

          local new_prompt_line_num = last_line_idx + cursor_line_offset - 1
          local new_prompt_lines =
            vim.api.nvim_buf_get_lines(bufnr, new_prompt_line_num, new_prompt_line_num + 1, false)
          if #new_prompt_lines > 0 then
            local line_text = new_prompt_lines[1]
            local col = line_text:find(":%s*") + 1
            while line_text:sub(col, col) == " " do
              col = col + 1
            end
            if vim.api.nvim_get_current_buf() == bufnr then
              vim.api.nvim_win_set_cursor(0, { new_prompt_line_num + 1, col - 1 })
            end
          end

          auto_write_buffer(bufnr)
          update_ui(bufnr)
          fold_last_thinking_block(bufnr) -- Attempt to fold the last thinking block

          if opts.on_complete then -- For FlemmaSendAndInsert
            opts.on_complete()
          end
        else
          -- cURL request failed (exit code ~= 0)
          -- Buffer is already set to modifiable = true
          M.cleanup_spinner(bufnr) -- Handles its own modifiable toggles

          local error_msg
          if code == 6 then -- CURLE_COULDNT_RESOLVE_HOST
            error_msg =
              string.format("Flemma: cURL could not resolve host (exit code %d). Check network or hostname.", code)
          elseif code == 7 then -- CURLE_COULDNT_CONNECT
            error_msg = string.format(
              "Flemma: cURL could not connect to host (exit code %d). Check network or if the host is up.",
              code
            )
          elseif code == 28 then -- cURL timeout error
            local timeout_value = current_provider.parameters.timeout or state.get_config().parameters.timeout -- Get effective timeout
            error_msg = string.format(
              "Flemma: cURL request timed out (exit code %d). Timeout is %s seconds.",
              code,
              tostring(timeout_value)
            )
          else -- Other cURL errors
            error_msg = string.format("Flemma: cURL request failed (exit code %d).", code)
          end

          if log.is_enabled() then
            error_msg = error_msg .. " See " .. log.get_path() .. " for details."
          end
          vim.notify(error_msg, vim.log.levels.ERROR)

          auto_write_buffer(bufnr) -- Auto-write if enabled, even on error
          update_ui(bufnr) -- Update UI to remove any artifacts
        end
      end)
    end,
  }

  -- Send the request using the provider
  buffer_state.current_request = current_provider:send_request(request_body, callbacks)

  if not buffer_state.current_request or buffer_state.current_request == 0 or buffer_state.current_request == -1 then
    log.error("send_to_provider(): Failed to start provider job.")
    if spinner_timer then -- Ensure spinner_timer is valid before trying to stop
      vim.fn.timer_stop(spinner_timer)
      -- state.spinner_timer might have been set by start_loading_spinner, clear it if so
      if state.spinner_timer == spinner_timer then
        state.spinner_timer = nil
      end
    end
    M.cleanup_spinner(bufnr) -- Clean up any "Thinking..." message, handles its own modifiable toggles
    vim.bo[bufnr].modifiable = true -- Restore modifiable state
    return
  end
  -- If job started successfully, modifiable remains false (as set at the start of this function).
end

-- Switch to a different provider or model
function M.switch(provider_name, model_name, parameters)
  if not provider_name then
    vim.notify("Flemma: Provider name is required", vim.log.levels.ERROR)
    return
  end

  -- Check for ongoing requests
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer_state = buffers.get_state(bufnr)
  if buffer_state.current_request then
    vim.notify("Flemma: Cannot switch providers while a request is in progress.", vim.log.levels.WARN)
    return
  end

  -- Ensure parameters is a table if nil
  parameters = parameters or {}

  -- Create a new configuration by merging the current config with the provided options
  local new_config = vim.tbl_deep_extend("force", {}, config)

  -- Ensure parameters table and provider-specific sub-table exist for parameter merging
  new_config.parameters = new_config.parameters or {}
  new_config.parameters[provider_name] = new_config.parameters[provider_name] or {}

  -- Merge the provided parameters into the correct parameter locations
  for k, v in pairs(parameters) do
    -- Check if it's a general parameter
    if config_manager.is_general_parameter(k) then
      new_config.parameters[k] = v
    else
      -- Assume it's a provider-specific parameter
      new_config.parameters[provider_name][k] = v
    end
  end

  -- Initialize the new provider using the centralized approach
  -- but do not commit the global config until validation succeeds.
  local prev_provider = provider
  provider = nil -- Clear the current provider
  local new_provider = initialize_provider(provider_name, model_name, new_config.parameters)

  if not new_provider then
    -- Restore previous provider and keep existing config unchanged.
    provider = prev_provider
    log.warn("switch(): Aborting switch due to invalid provider: " .. log.inspect(provider_name))
    return nil
  end

  -- Commit the new configuration now that initialization succeeded.
  -- The config has already been updated by initialize_provider via config_manager.apply_config
  local updated_config = state.get_config()
  config.provider = updated_config.provider
  config.model = updated_config.model
  config.parameters = updated_config.parameters

  -- Force the new provider to clear its API key cache
  if new_provider and new_provider.state then
    new_provider.state.api_key = nil
  end

  -- Notify the user
  local model_info = config.model and (" with model '" .. config.model .. "'") or ""
  vim.notify("Flemma: Switched to '" .. config.provider .. "'" .. model_info .. ".", vim.log.levels.INFO)

  -- Refresh lualine if available to update the model component
  local lualine_ok, lualine = pcall(require, "lualine")
  if lualine_ok and lualine.refresh then
    lualine.refresh()
    log.debug("switch(): Lualine refreshed.")
  else
    log.debug("switch(): Lualine not found or refresh function unavailable.")
  end

  return new_provider
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

-- Get the last request body for testing
function M._get_last_request_body()
  return last_request_body_for_testing
end

return M
