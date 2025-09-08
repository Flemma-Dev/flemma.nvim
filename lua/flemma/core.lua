--- Core runtime functionality for Flemma plugin
--- Handles provider initialization, switching, and main request-response lifecycle
local M = {}

local buffers = require("flemma.buffers")
local log = require("flemma.logging")
local state = require("flemma.state")
local config_manager = require("flemma.core.config_manager")

-- For testing purposes
local last_request_body_for_testing = nil

local ns_id = vim.api.nvim_create_namespace("flemma")

-- Execute a command in the context of a specific buffer
function M.buffer_cmd(bufnr, cmd)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    -- If buffer has no window, do nothing
    return
  end
  vim.fn.win_execute(winid, "noautocmd " .. cmd)
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
  -- We need access to the parse_buffer function from init.lua
  require("flemma").parse_buffer(bufnr) -- This will reapply signs
end

-- Helper function to auto-write the buffer if enabled
local function auto_write_buffer(bufnr)
  if state.get_config().editing.auto_write and vim.bo[bufnr].modified then
    log.debug("auto_write_buffer(): bufnr = " .. bufnr)
    M.buffer_cmd(bufnr, "silent! write")
  end
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
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #buffer_lines > 0 and buffer_lines[#buffer_lines]:match("%S") then
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
    M.buffer_cmd(bufnr, "undojoin")
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { text })
    -- Force UI update during spinner animation
    update_ui(bufnr)

    vim.bo[bufnr].modifiable = original_modifiable_timer -- Restore state after spinner update
  end, { ["repeat"] = -1 })

  buffer_state.spinner_timer = timer
  return timer
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
    M.buffer_cmd(bufnr, "undojoin") -- Group changes for undo

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

-- Initialize or switch provider based on configuration (local function)
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

-- Initialize provider for initial setup (exposed version)
function M.initialize_provider(provider_name, model_name, parameters)
  return initialize_provider(provider_name, model_name, parameters)
end

-- Switch to a different provider or model
function M.switch_provider(provider_name, model_name, parameters)
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
  local config = state.get_config()
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
  local prev_provider = state.get_provider()
  state.set_provider(nil) -- Clear the current provider
  local new_provider = initialize_provider(provider_name, model_name, new_config.parameters)

  if not new_provider then
    -- Restore previous provider and keep existing config unchanged.
    state.set_provider(prev_provider)
    log.warn("switch_provider(): Aborting switch due to invalid provider: " .. log.inspect(provider_name))
    return nil
  end

  -- Commit the new configuration now that initialization succeeded.
  -- The config has already been updated by initialize_provider via config_manager.apply_config
  local updated_config = state.get_config()

  -- Force the new provider to clear its API key cache
  if new_provider and new_provider.state then
    new_provider.state.api_key = nil
  end

  -- Notify the user
  local model_info = updated_config.model and (" with model '" .. updated_config.model .. "'") or ""
  vim.notify("Flemma: Switched to '" .. updated_config.provider .. "'" .. model_info .. ".", vim.log.levels.INFO)

  -- Refresh lualine if available to update the model component
  local lualine_ok, lualine = pcall(require, "lualine")
  if lualine_ok and lualine.refresh then
    lualine.refresh()
    log.debug("switch_provider(): Lualine refreshed.")
  else
    log.debug("switch_provider(): Lualine not found or refresh function unavailable.")
  end

  return new_provider
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

  -- Make the buffer non-modifiable to prevent user edits during request
  vim.bo[bufnr].modifiable = false

  -- Check if buffer has content
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    log.warn("send_to_provider(): Empty buffer - nothing to send")
    vim.bo[bufnr].modifiable = true -- Restore modifiable state before returning
    return
  end

  -- Get current provider
  local current_provider = state.get_provider()
  if not current_provider then
    log.error("send_to_provider(): No provider available")
    vim.notify("Flemma: No provider configured. Use :FlemmaSwitch to select one.", vim.log.levels.ERROR)
    vim.bo[bufnr].modifiable = true -- Restore modifiable state
    return
  end

  -- Parse messages from buffer using init module
  local messages = require("flemma").parse_buffer(bufnr)

  if #messages == 0 then
    log.warn("send_to_provider(): No messages found in buffer")
    vim.notify("Flemma: No messages found in buffer.", vim.log.levels.WARN)
    vim.bo[bufnr].modifiable = true -- Restore modifiable state
    return
  end

  -- Process and validate messages
  local processed_messages = messages
  local validation_errors = {} -- No validation errors for now
  log.debug("send_to_provider(): Processed messages count: " .. #processed_messages)

  if #validation_errors > 0 then
    log.warn("send_to_provider(): Lua expression evaluation errors occurred")
    vim.bo[bufnr].modifiable = true -- Restore modifiable state before returning
    local error_lines = { "Lua expression evaluation errors:" }
    for _, error_info in ipairs(validation_errors) do
      table.insert(
        error_lines,
        string.format("  Expression: %s (File: %s)", error_info.expression, error_info.file_path)
      )
      table.insert(error_lines, string.format("  %s", error_info.error_details))
    end

    vim.notify("Flemma: " .. table.concat(error_lines, "\n"), vim.log.levels.WARN)
  end

  -- Format messages using provider and get system message
  local formatted_messages, system_message = current_provider:format_messages(processed_messages)

  log.debug("send_to_provider(): Formatted messages for provider: " .. log.inspect(formatted_messages))
  log.debug("send_to_provider(): System message: " .. log.inspect(system_message))

  -- Check for pending Lua expression evaluation errors
  if #validation_errors > 0 then
    log.warn("send_to_provider(): Cannot proceed due to Lua expression errors.")
    -- Show error notification
    local error_lines = { "Cannot send request due to Lua expression evaluation errors:" }
    for _, error_info in ipairs(validation_errors) do
      table.insert(
        error_lines,
        string.format("  Expression: %s (File: %s)", error_info.expression, error_info.file_path)
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
    local usage_lines = {}

    -- Request usage
    if
      current
      and (
        current.input_tokens > 0
        or current.output_tokens > 0
        or (current.thoughts_tokens and current.thoughts_tokens > 0)
      )
    then
      local config = state.get_config()
      local total_output_tokens_for_cost = (current.output_tokens or 0) + (current.thoughts_tokens or 0)
      local current_cost = config.pricing.enabled
        and pricing.calculate_cost(config.model, current.input_tokens, total_output_tokens_for_cost)
      table.insert(usage_lines, "Request:")
      -- Add model and provider information
      table.insert(usage_lines, string.format("  Model:  `%s` (%s)", config.model, config.provider))
      if current_cost then
        table.insert(
          usage_lines,
          string.format("  Input:  %d tokens / $%.2f", current.input_tokens or 0, current_cost.input)
        )
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
        table.insert(usage_lines, output_display_string)
        table.insert(usage_lines, string.format("  Total:  $%.2f", current_cost.total))
      else
        table.insert(usage_lines, string.format("  Input:  %d tokens", current.input_tokens or 0))
        local display_output_tokens = (current.output_tokens or 0) + (current.thoughts_tokens or 0)
        local output_display_string
        if current.thoughts_tokens and current.thoughts_tokens > 0 then
          output_display_string =
            string.format(" Output:  %d tokens (⊂ %d thoughts)", display_output_tokens, current.thoughts_tokens)
        else
          output_display_string = string.format(" Output:  %d tokens", display_output_tokens)
        end
        table.insert(usage_lines, output_display_string)
      end
    end

    -- Session totals
    if session and (session.input_tokens > 0 or session.output_tokens > 0) then
      local config = state.get_config()
      local total_session_output_tokens_for_cost = (session.output_tokens or 0) + (session.thoughts_tokens or 0)
      local session_cost = config.pricing.enabled
        and pricing.calculate_cost(config.model, session.input_tokens, total_session_output_tokens_for_cost)
      if #usage_lines > 0 then
        table.insert(usage_lines, "")
      end
      table.insert(usage_lines, "Session:")
      if session_cost then
        table.insert(
          usage_lines,
          string.format("  Input:  %d tokens / $%.2f", session.input_tokens or 0, session_cost.input)
        )
        local display_session_output_tokens = (session.output_tokens or 0) + (session.thoughts_tokens or 0)
        table.insert(
          usage_lines,
          string.format(" Output:  %d tokens / $%.2f", display_session_output_tokens, session_cost.output)
        )
        table.insert(usage_lines, string.format("  Total:  $%.2f", session_cost.total))
      else
        table.insert(usage_lines, string.format("  Input:  %d tokens", session.input_tokens or 0))
        local display_session_output_tokens = (session.output_tokens or 0) + (session.thoughts_tokens or 0)
        table.insert(usage_lines, string.format(" Output:  %d tokens", display_session_output_tokens))
      end
    end
    return table.concat(usage_lines, "\n")
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
        local content_lines = vim.split(text, "\n", { plain = true })

        if #content_lines > 0 then
          local last_line = vim.api.nvim_buf_line_count(bufnr)

          if not response_started then
            -- Clean up spinner and ensure blank line
            M.cleanup_spinner(bufnr) -- Handles its own modifiable toggles
            last_line = vim.api.nvim_buf_line_count(bufnr)

            -- Check if response starts with a code fence
            if content_lines[1]:match("^```") then
              -- Add a newline before the code fence
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant:", content_lines[1] })
            else
              -- Start with @Assistant: prefix as normal
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant: " .. content_lines[1] })
            end

            -- Add remaining lines if any
            if #content_lines > 1 then
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line + 1, last_line + 1, false, { unpack(content_lines, 2) })
            end
          else
            -- Get the last line's content
            local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

            if #content_lines == 1 then
              -- Just append to the last line
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(
                bufnr,
                last_line - 1,
                last_line,
                false,
                { last_line_content .. content_lines[1] }
              )
            else
              -- First chunk goes to the end of the last line
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(
                bufnr,
                last_line - 1,
                last_line,
                false,
                { last_line_content .. content_lines[1] }
              )

              -- Remaining lines get added as new lines
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { unpack(content_lines, 2) })
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

          M.buffer_cmd(bufnr, "undojoin")
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

-- Get the last request body for testing
function M._get_last_request_body()
  return last_request_body_for_testing
end

-- Expose UI update function
function M.update_ui(bufnr)
  return update_ui(bufnr)
end

return M
