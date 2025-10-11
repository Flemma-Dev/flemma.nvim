--- Core runtime functionality for Flemma plugin
--- Handles provider initialization, switching, and main request-response lifecycle
local M = {}

local buffers = require("flemma.buffers")
local log = require("flemma.logging")
local state = require("flemma.state")
local config_manager = require("flemma.core.config.manager")
local ui = require("flemma.ui")
local providers_registry = require("flemma.provider.providers")

-- For testing purposes
local last_request_body_for_testing = nil

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
  local provider_module = providers_registry.get(provider_config.provider)
  if not provider_module then
    local err_msg = "initialize_provider(): Invalid provider after validation: " .. tostring(provider_config.provider)
    log.error(err_msg)
    return nil
  end

  local new_provider = require(provider_module).new(provider_config.parameters)

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

    -- Use client to cancel the request
    local client = require("flemma.client")
    if client.cancel_request(buffer_state.current_request) then
      buffer_state.current_request = nil

      -- Clean up the buffer
      local last_line = vim.api.nvim_buf_line_count(bufnr)
      local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

      -- If we're still showing the thinking message, remove it
      if last_line_content:match("^@Assistant:.*Thinking%.%.%.$") then
        log.debug("cancel_request(): ... Cleaning up 'Thinking...' message")
        ui.cleanup_spinner(bufnr)
      end

      -- Auto-write if enabled and we've received some content
      if buffer_state.request_cancelled and not last_line_content:match("^@Assistant:.*Thinking%.%.%.$") then
        buffers.auto_write_buffer(bufnr)
      end

      vim.bo[bufnr].modifiable = true -- Restore modifiable state

      local msg = "Flemma: Request cancelled"
      if log.is_enabled() then
        msg = msg .. ". See " .. log.get_path() .. " for details"
      end
      vim.notify(msg, vim.log.levels.INFO)
      -- Force UI update after cancellation
      ui.update_ui(bufnr)
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

  -- Create context ONCE for the entire pipeline (used by frontmatter, @./file refs, etc.)
  local context = require("flemma.context").from_buffer(bufnr)

  -- Run the new AST-based pipeline
  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local pipeline = require("flemma.pipeline")
  local prompt, evaluated = pipeline.run(buf_lines, context)

  if #prompt.history == 0 then
    log.warn("send_to_provider(): No messages found in buffer")
    vim.notify("Flemma: No messages found in buffer.", vim.log.levels.WARN)
    vim.bo[bufnr].modifiable = true -- Restore modifiable state
    return
  end

  log.debug("send_to_provider(): Processed messages count: " .. #prompt.history)

  -- Display diagnostics to user if any
  local diagnostics = evaluated.diagnostics or {}
  if #diagnostics > 0 then
    local has_errors = false
    local by_type = { frontmatter = {}, expression = {}, file = {} }

    for _, diag in ipairs(diagnostics) do
      if diag.severity == "error" then
        has_errors = true
      end
      local type_bucket = by_type[diag.type] or {}
      table.insert(type_bucket, diag)
      by_type[diag.type] = type_bucket
    end

    local diagnostic_lines = {}
    local max_per_type = 5

    local function format_position(pos)
      if not pos then
        return ""
      end
      if pos.start_line then
        if pos.start_col then
          return string.format(":%d:%d", pos.start_line, pos.start_col)
        end
        return string.format(":%d", pos.start_line)
      end
      return ""
    end

    -- Format frontmatter errors
    if #by_type.frontmatter > 0 then
      table.insert(diagnostic_lines, "Frontmatter errors:")
      for i, d in ipairs(by_type.frontmatter) do
        if i <= max_per_type then
          local loc = (d.source_file or "N/A") .. format_position(d.position)
          table.insert(diagnostic_lines, string.format("  [%s] %s", loc, d.error))
        elseif i == max_per_type + 1 then
          table.insert(diagnostic_lines, string.format("  ... and %d more", #by_type.frontmatter - max_per_type))
          break
        end
      end
    end

    -- Format expression errors (non-fatal warnings)
    if #by_type.expression > 0 then
      table.insert(diagnostic_lines, "Expression evaluation errors (request will still be sent):")
      for i, d in ipairs(by_type.expression) do
        if i <= max_per_type then
          local loc = (d.source_file or "N/A") .. format_position(d.position)
          local role_info = d.message_role and (" in @" .. d.message_role) or ""
          table.insert(diagnostic_lines, string.format("  [%s%s] %s", loc, role_info, d.error))
          table.insert(diagnostic_lines, string.format("    Expression: {{ %s }}", d.expression or ""))
        elseif i == max_per_type + 1 then
          table.insert(diagnostic_lines, string.format("  ... and %d more", #by_type.expression - max_per_type))
          break
        end
      end
    end

    -- Format file reference warnings
    if #by_type.file > 0 then
      table.insert(diagnostic_lines, "File reference errors:")
      for i, d in ipairs(by_type.file) do
        if i <= max_per_type then
          local loc = (d.source_file or "N/A") .. format_position(d.position)
          local ref = d.filename or d.raw or "unknown"
          table.insert(diagnostic_lines, string.format("  [%s] %s: %s", loc, ref, d.error))
        elseif i == max_per_type + 1 then
          table.insert(diagnostic_lines, string.format("  ... and %d more", #by_type.file - max_per_type))
          break
        end
      end
    end

    local level = has_errors and vim.log.levels.ERROR or vim.log.levels.WARN
    vim.notify("Flemma diagnostics:\n" .. table.concat(diagnostic_lines, "\n"), level)
    log.warn("send_to_provider(): Diagnostics occurred: " .. #diagnostics .. " total")

    -- Block request if there are critical errors (frontmatter parsing failures)
    if has_errors then
      log.error("send_to_provider(): Blocking request due to critical errors")
      vim.bo[bufnr].modifiable = true
      return
    end
  end

  log.debug("send_to_provider(): Prompt history for provider: " .. log.inspect(prompt.history))
  log.debug("send_to_provider(): System instruction: " .. log.inspect(prompt.system))

  -- Get endpoint first to check for fixtures
  local endpoint = current_provider:get_endpoint()

  -- Check if there's a fixture for this endpoint (for testing)
  local client = require("flemma.client")
  local fixture_path = client.find_fixture_for_endpoint(endpoint)

  -- Only get API key and headers if not using a fixture
  local headers
  if not fixture_path then
    -- Get API key if not using a fixture
    local api_key = current_provider:get_api_key()
    if not api_key then
      vim.notify(
        "Flemma: No API key available for provider '" .. state.get_config().provider .. "'.",
        vim.log.levels.ERROR
      )
      return nil
    end
    headers = current_provider:get_request_headers()
  else
    -- For fixtures, provide dummy headers since they won't be used
    headers = { "content-type: application/json" }
  end

  -- Build request body using the validated model stored in the provider
  local request_body = current_provider:build_request(prompt, context)
  last_request_body_for_testing = request_body -- Store for testing

  -- Log the request details (using the provider's stored model)
  log.debug(
    "send_to_provider(): Sending request for provider "
      .. log.inspect(state.get_config().provider)
      .. " with model "
      .. log.inspect(current_provider.parameters.model)
  )

  local spinner_timer = ui.start_loading_spinner(bufnr) -- Handles its own modifiable toggles for writes
  local response_started = false

  -- Reset in-flight usage tracking for this buffer
  buffer_state.inflight_usage = {
    input_tokens = 0,
    output_tokens = 0,
    thoughts_tokens = 0,
  }

  -- Set up callbacks for the provider
  local callbacks = {
    on_error = function(msg)
      vim.schedule(function()
        if spinner_timer then
          vim.fn.timer_stop(spinner_timer)
        end
        ui.cleanup_spinner(bufnr) -- Handles its own modifiable toggles
        buffer_state.current_request = nil
        buffer_state.api_error_occurred = true -- Set flag indicating API error

        vim.bo[bufnr].modifiable = true -- Restore modifiable state

        -- Auto-write on error if enabled
        buffers.auto_write_buffer(bufnr)

        local notify_msg = "Flemma: " .. msg
        if log.is_enabled() then
          notify_msg = notify_msg .. ". See " .. log.get_path() .. " for details"
        end
        vim.notify(notify_msg, vim.log.levels.ERROR)
      end)
    end,

    on_usage = function(usage_data)
      if usage_data.type == "input" then
        buffer_state.inflight_usage.input_tokens = usage_data.tokens
      elseif usage_data.type == "output" then
        buffer_state.inflight_usage.output_tokens = usage_data.tokens
      elseif usage_data.type == "thoughts" then
        buffer_state.inflight_usage.thoughts_tokens = usage_data.tokens
      end
    end,

    on_response_complete = function()
      vim.schedule(function()
        local usage = require("flemma.usage")
        local pricing = require("flemma.pricing")
        local config = state.get_config()

        -- Get tokens from in-flight usage
        local input_tokens = buffer_state.inflight_usage.input_tokens or 0
        local output_tokens = buffer_state.inflight_usage.output_tokens or 0
        local thoughts_tokens = buffer_state.inflight_usage.thoughts_tokens or 0

        -- Add request to session with pricing snapshot
        local pricing_info = pricing.models[config.model]
        if pricing_info then
          state.get_session():add_request({
            provider = config.provider,
            model = config.model,
            input_tokens = input_tokens,
            output_tokens = output_tokens,
            thoughts_tokens = thoughts_tokens,
            input_price = pricing_info.input,
            output_price = pricing_info.output,
            bufnr = bufnr,
          })
        end

        -- Auto-write when response is complete
        buffers.auto_write_buffer(bufnr)

        -- Format and display usage information using our custom notification
        local usage_str = usage.format_notification(buffer_state.inflight_usage, state.get_session())
        if usage_str ~= "" then
          local notify_opts = vim.tbl_deep_extend("force", state.get_config().notify, {
            title = "Usage",
          })
          require("flemma.notify").show(usage_str, notify_opts)
        end
        -- Reset in-flight usage for next request
        buffer_state.inflight_usage = {
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
            ui.cleanup_spinner(bufnr) -- Handles its own modifiable toggles
            last_line = vim.api.nvim_buf_line_count(bufnr)

            -- Check if response starts with a code fence
            if content_lines[1]:match("^```") then
              -- Add a newline before the code fence
              buffers.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant:", content_lines[1] })
            else
              -- Start with @Assistant: prefix as normal
              buffers.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant: " .. content_lines[1] })
            end

            -- Add remaining lines if any
            if #content_lines > 1 then
              buffers.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line + 1, last_line + 1, false, { unpack(content_lines, 2) })
            end
          else
            -- Get the last line's content
            local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

            if #content_lines == 1 then
              -- Just append to the last line
              buffers.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(
                bufnr,
                last_line - 1,
                last_line,
                false,
                { last_line_content .. content_lines[1] }
              )
            else
              -- First chunk goes to the end of the last line
              buffers.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(
                bufnr,
                last_line - 1,
                last_line,
                false,
                { last_line_content .. content_lines[1] }
              )

              -- Remaining lines get added as new lines
              buffers.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { unpack(content_lines, 2) })
            end
          end

          response_started = true
          -- Force UI update after appending content
          ui.update_ui(bufnr)
        end
        vim.bo[bufnr].modifiable = original_modifiable_for_on_content -- Restore to likely false
      end)
    end,

    on_request_complete = function(code)
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
        -- ui.cleanup_spinner will also try to stop state.spinner_timer.
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
              "send_to_provider(): on_request_complete: cURL success (code 0), but an API error was previously handled. Skipping new prompt."
            )
            buffer_state.api_error_occurred = false -- Reset flag for next request
            if not response_started then
              ui.cleanup_spinner(bufnr) -- Handles its own modifiable toggles
            end
            buffers.auto_write_buffer(bufnr) -- Still auto-write if configured
            ui.update_ui(bufnr) -- Update UI
            return -- Do not proceed to add new prompt or call opts.on_request_complete
          end

          if not response_started then
            log.info(
              "send_to_provider(): on_request_complete: cURL success (code 0), no API error, but no response content was processed."
            )
            ui.cleanup_spinner(bufnr) -- Handles its own modifiable toggles
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

          buffers.buffer_cmd(bufnr, "undojoin")
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

          buffers.auto_write_buffer(bufnr)
          ui.update_ui(bufnr)
          ui.fold_last_thinking_block(bufnr) -- Attempt to fold the last thinking block

          if opts.on_request_complete then -- For FlemmaSendAndInsert
            opts.on_request_complete()
          end
        else
          -- cURL request failed (exit code ~= 0)
          -- Buffer is already set to modifiable = true
          ui.cleanup_spinner(bufnr) -- Handles its own modifiable toggles

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

          buffers.auto_write_buffer(bufnr) -- Auto-write if enabled, even on error
          ui.update_ui(bufnr) -- Update UI to remove any artifacts
        end
      end)
    end,
  }

  -- Headers and endpoint are already obtained above with API key validation

  -- Send the request using the client
  buffer_state.current_request = client.send_request({
    request_body = request_body,
    headers = headers,
    endpoint = endpoint,
    parameters = current_provider.parameters,
    callbacks = callbacks,
    process_response_line_fn = function(line, cb)
      return current_provider:process_response_line(line, cb)
    end,
    finalize_response_fn = function(exit_code, cb)
      return current_provider:finalize_response(exit_code, cb)
    end,
    reset_fn = function()
      return current_provider:reset()
    end,
  })

  if not buffer_state.current_request or buffer_state.current_request == 0 or buffer_state.current_request == -1 then
    log.error("send_to_provider(): Failed to start provider job.")
    if spinner_timer then -- Ensure spinner_timer is valid before trying to stop
      vim.fn.timer_stop(spinner_timer)
      -- state.spinner_timer might have been set by start_loading_spinner, clear it if so
      if state.spinner_timer == spinner_timer then
        state.spinner_timer = nil
      end
    end
    ui.cleanup_spinner(bufnr) -- Clean up any "Thinking..." message, handles its own modifiable toggles
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
  return ui.update_ui(bufnr)
end

return M
