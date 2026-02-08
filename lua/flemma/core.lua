--- Core runtime functionality for Flemma plugin
--- Handles provider initialization, switching, and main request-response lifecycle
---@class flemma.Core
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")
local config_manager = require("flemma.core.config.manager")
local ui = require("flemma.ui")
local registry = require("flemma.provider.registry")

-- For testing purposes
local last_request_body_for_testing = nil

---Auto-write buffer if configured and modified
---@param bufnr integer
local function auto_write_buffer(bufnr)
  local config = state.get_config()
  if config.editing and config.editing.auto_write and vim.bo[bufnr].modified then
    ui.buffer_cmd(bufnr, "silent! write")
  end
end

---Initialize or switch provider based on configuration
---@param provider_name string
---@param model_name? string
---@param parameters? table<string, any>
---@return flemma.provider.Base|nil
local function initialize_provider(provider_name, model_name, parameters)
  -- Prepare configuration using the centralized config manager
  local provider_config, err = config_manager.prepare_config(provider_name, model_name, parameters)
  if not provider_config then
    vim.notify(err --[[@as string]], vim.log.levels.ERROR)
    return nil
  end

  -- Apply the configuration to global state
  config_manager.apply_config(provider_config)

  -- Create a fresh provider instance with the merged parameters
  local provider_module = registry.get(provider_config.provider)
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

---Initialize provider for initial setup (exposed version)
---@param provider_name string
---@param model_name? string
---@param parameters? table<string, any>
---@return flemma.provider.Base|nil
function M.initialize_provider(provider_name, model_name, parameters)
  return initialize_provider(provider_name, model_name, parameters)
end

---Switch to a different provider or model
---@param provider_name string
---@param model_name? string
---@param parameters? table<string, any>
---@return flemma.provider.Base|nil
function M.switch_provider(provider_name, model_name, parameters)
  if not provider_name then
    vim.notify("Flemma: Provider name is required", vim.log.levels.ERROR)
    return
  end

  -- Check for ongoing requests
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.current_request then
    vim.notify("Flemma: Cannot switch providers while a request is in progress.", vim.log.levels.WARN)
    return
  end

  -- Ensure parameters is a table if nil
  parameters = parameters or {}

  -- Merge parameters using centralized logic
  local config = state.get_config()
  local merged_params = config_manager.merge_parameters(config.parameters, provider_name, parameters)

  -- Initialize the new provider using the centralized approach
  -- but do not commit the global config until validation succeeds.
  local prev_provider = state.get_provider()
  state.set_provider(nil) -- Clear the current provider
  local new_provider = initialize_provider(provider_name, model_name, merged_params)

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

---Cancel ongoing request if any
function M.cancel_request()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer_state = state.get_buffer_state(bufnr)

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
      if last_line_content == "@Assistant: Thinking..." then
        log.debug("cancel_request(): ... Cleaning up 'Thinking...' message")
        ui.cleanup_spinner(bufnr)
      end

      -- Auto-write if enabled and we've received some content
      if buffer_state.request_cancelled and last_line_content ~= "@Assistant: Thinking..." then
        auto_write_buffer(bufnr)
      end

      state.unlock_buffer(bufnr)

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
    local bs = state.get_buffer_state(bufnr)
    if bs.locked then
      state.unlock_buffer(bufnr)
    end
  end
end

---Handle the AI provider interaction
---@param opts? { on_request_complete?: fun() }
function M.send_to_provider(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer_state = state.get_buffer_state(bufnr)

  -- Check if there's already a request in progress
  if buffer_state.current_request then
    vim.notify("Flemma: A request is already in progress. Use <C-c> to cancel it first.", vim.log.levels.WARN)
    return
  end

  -- Check if tool executions are in progress (mutually exclusive with API requests)
  local ok_executor, executor = pcall(require, "flemma.tools.executor")
  if ok_executor then
    local pending = executor.get_pending(bufnr)
    if #pending > 0 then
      vim.notify("Flemma: Cannot send while tool execution is in progress.", vim.log.levels.WARN)
      return
    end
  end

  -- Gate on async tool sources being ready
  local tools_module = require("flemma.tools")
  if not tools_module.is_ready() then
    vim.notify("Flemma: Waiting for tool definitions to load...", vim.log.levels.WARN)
    if buffer_state.waiting_for_tools then
      return -- already queued
    end
    buffer_state.waiting_for_tools = true
    local target_bufnr = bufnr
    tools_module.on_ready(function()
      buffer_state.waiting_for_tools = false
      if vim.api.nvim_buf_is_valid(target_bufnr) and vim.api.nvim_get_current_buf() == target_bufnr then
        M.send_to_provider(opts)
      end
    end)
    return
  end

  log.info("send_to_provider(): Starting new request for buffer " .. bufnr)
  buffer_state.request_cancelled = false
  buffer_state.api_error_occurred = false -- Initialize flag for API errors

  -- Make the buffer non-modifiable to prevent user edits during request
  state.lock_buffer(bufnr)

  -- Check if buffer has content
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    log.warn("send_to_provider(): Empty buffer - nothing to send")
    state.unlock_buffer(bufnr)
    return
  end

  -- Get current provider
  local current_provider = state.get_provider()
  if not current_provider then
    log.error("send_to_provider(): No provider available")
    vim.notify("Flemma: No provider configured. Use :Flemma switch to select one.", vim.log.levels.ERROR)
    state.unlock_buffer(bufnr)
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
    state.unlock_buffer(bufnr)
    return
  end

  log.debug("send_to_provider(): Processed messages count: " .. #prompt.history)

  -- Display diagnostics to user if any
  local diagnostics = evaluated.diagnostics or {}
  if #diagnostics > 0 then
    local has_errors = false
    local by_type = { frontmatter = {}, expression = {}, file = {}, tool_result = {}, tool_use = {} }

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

    -- Format tool use/result warnings
    local tool_diags = {}
    for _, d in ipairs(by_type.tool_use) do
      table.insert(tool_diags, d)
    end
    for _, d in ipairs(by_type.tool_result) do
      table.insert(tool_diags, d)
    end
    if #tool_diags > 0 then
      table.insert(diagnostic_lines, "Tool calling errors:")
      for i, d in ipairs(tool_diags) do
        if i <= max_per_type then
          local loc = format_position(d.position)
          table.insert(diagnostic_lines, string.format("  [%s] %s", loc, d.error))
        elseif i == max_per_type + 1 then
          table.insert(diagnostic_lines, string.format("  ... and %d more", #tool_diags - max_per_type))
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
      state.unlock_buffer(bufnr)
      return
    end
  end

  log.debug("send_to_provider(): Prompt history for provider: " .. log.inspect(prompt.history))
  log.debug("send_to_provider(): System instruction: " .. log.inspect(prompt.system))

  -- Apply frontmatter parameter overrides so that get_endpoint / get_api_key see them
  local provider_key = state.get_config().provider
  current_provider:set_parameter_overrides(prompt.opts and prompt.opts[provider_key])

  -- Validate provider (endpoint, API key, headers) and build request body.
  -- Wrapped in pcall so any provider error unlocks the buffer cleanly.
  local client = require("flemma.client")
  local prep_ok, prep_result = pcall(function()
    local endpoint = current_provider:get_endpoint()
    if not endpoint then
      error("Provider did not return an endpoint.", 0)
    end

    local fixture_path = client.find_fixture_for_endpoint(endpoint)

    local headers
    if not fixture_path then
      local api_key = current_provider:get_api_key()
      if not api_key then
        error("No API key available for provider '" .. state.get_config().provider .. "'.", 0)
      end
      headers = current_provider:get_request_headers()
      if not headers then
        error("Provider did not return request headers.", 0)
      end
    else
      headers = { "content-type: application/json" }
    end

    local request_body = current_provider:build_request(prompt, context)
    return { endpoint = endpoint, headers = headers, request_body = request_body }
  end)

  if not prep_ok then
    vim.notify("Flemma: " .. tostring(prep_result), vim.log.levels.ERROR)
    state.unlock_buffer(bufnr)
    return
  end

  local endpoint = prep_result.endpoint
  local headers = prep_result.headers
  local request_body = prep_result.request_body
  last_request_body_for_testing = request_body -- Store for testing

  -- Capture timeout now so the on_request_complete closure doesn't read stale proxy state
  local effective_timeout = current_provider.parameters.timeout

  -- Log the request details (using the provider's stored model)
  log.debug(
    "send_to_provider(): Sending request for provider "
      .. log.inspect(state.get_config().provider)
      .. " with model "
      .. log.inspect(current_provider.parameters.model)
  )

  ---@type integer|nil
  local spinner_timer = ui.start_loading_spinner(bufnr) -- Handles its own modifiable toggles for writes
  local response_started = false

  -- Reset in-flight usage tracking for this buffer
  -- Include the provider's output_has_thoughts flag so usage.lua can display correctly
  buffer_state.inflight_usage = {
    input_tokens = 0,
    output_tokens = 0,
    thoughts_tokens = 0,
    output_has_thoughts = current_provider.output_has_thoughts,
    cache_read_input_tokens = 0,
    cache_creation_input_tokens = 0,
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

        state.unlock_buffer(bufnr)

        -- Auto-write on error if enabled
        auto_write_buffer(bufnr)

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
      elseif usage_data.type == "cache_read" then
        buffer_state.inflight_usage.cache_read_input_tokens = usage_data.tokens
      elseif usage_data.type == "cache_creation" then
        buffer_state.inflight_usage.cache_creation_input_tokens = usage_data.tokens
      end
    end,

    on_response_complete = function()
      vim.schedule(function()
        local usage = require("flemma.usage")
        local config = state.get_config()

        -- Get tokens from in-flight usage
        local input_tokens = buffer_state.inflight_usage.input_tokens or 0
        local output_tokens = buffer_state.inflight_usage.output_tokens or 0
        local thoughts_tokens = buffer_state.inflight_usage.thoughts_tokens or 0

        -- Get buffer filepath (resolved to handle symlinks, relative paths, etc.)
        local filepath = nil
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        if bufname and bufname ~= "" then
          -- Resolve to canonical path (handles symlinks, .. etc.)
          filepath = vim.loop.fs_realpath(bufname) or bufname
        end

        -- Add request to session with pricing snapshot
        local pricing_info = usage.models[config.model]
        if pricing_info then
          -- Look up cache multipliers from provider model data
          local models_data = require("flemma.models")
          local provider_data = models_data.providers[config.provider]
          local cache_retention = current_provider.parameters.cache_retention
          local cache_write_multiplier
          local cache_read_multiplier
          if
            provider_data
            and provider_data.cache_write_multipliers
            and cache_retention
            and cache_retention ~= "none"
          then
            cache_write_multiplier = provider_data.cache_write_multipliers[cache_retention]
          end
          if provider_data and provider_data.cache_read_multiplier then
            -- Read multiplier applies regardless of write multipliers (e.g., OpenAI has automatic caching)
            cache_read_multiplier = provider_data.cache_read_multiplier
          end

          state.get_session():add_request({
            provider = config.provider,
            model = config.model,
            input_tokens = input_tokens,
            output_tokens = output_tokens,
            thoughts_tokens = thoughts_tokens,
            input_price = pricing_info.input,
            output_price = pricing_info.output,
            filepath = filepath,
            bufnr = filepath and nil or bufnr, -- Only store bufnr for unnamed buffers
            -- Get flag from provider (set in inflight_usage, available via closure)
            output_has_thoughts = current_provider.output_has_thoughts,
            cache_read_input_tokens = buffer_state.inflight_usage.cache_read_input_tokens,
            cache_creation_input_tokens = buffer_state.inflight_usage.cache_creation_input_tokens,
            cache_write_multiplier = cache_write_multiplier,
            cache_read_multiplier = cache_read_multiplier,
          })
        end

        -- Auto-write when response is complete
        auto_write_buffer(bufnr)

        -- Format and display usage information using our custom notification
        local usage_str = usage.format_notification(buffer_state.inflight_usage, state.get_session())
        if usage_str ~= "" then
          local notify_opts = vim.tbl_deep_extend("force", state.get_config().notify, {
            title = "Usage",
          })
          require("flemma.notify").show(usage_str, notify_opts, bufnr)
        end
        -- Reset in-flight usage for next request
        -- Note: output_has_thoughts will be set again when the next request starts
        buffer_state.inflight_usage = {
          input_tokens = 0,
          output_tokens = 0,
          thoughts_tokens = 0,
          output_has_thoughts = false, -- Default, will be overwritten on next request
          cache_read_input_tokens = 0,
          cache_creation_input_tokens = 0,
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
              ui.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant:", content_lines[1] })
            else
              -- Start with @Assistant: prefix as normal
              ui.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant: " .. content_lines[1] })
            end

            -- Add remaining lines if any
            if #content_lines > 1 then
              ui.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line + 1, last_line + 1, false, { unpack(content_lines, 2) })
            end
          else
            -- Get the last line's content
            local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

            if #content_lines == 1 then
              -- Just append to the last line
              ui.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(
                bufnr,
                last_line - 1,
                last_line,
                false,
                { last_line_content .. content_lines[1] }
              )
            else
              -- First chunk goes to the end of the last line
              ui.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(
                bufnr,
                last_line - 1,
                last_line,
                false,
                { last_line_content .. content_lines[1] }
              )

              -- Remaining lines get added as new lines
              ui.buffer_cmd(bufnr, "undojoin")
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
        state.unlock_buffer(bufnr)

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
            auto_write_buffer(bufnr) -- Still auto-write if configured
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

          local lines_to_insert
          local cursor_line_offset
          if last_line_content == "" then
            lines_to_insert = { "@You: " }
            cursor_line_offset = 1
          else
            lines_to_insert = { "", "@You: " }
            cursor_line_offset = 2
          end

          ui.buffer_cmd(bufnr, "undojoin")
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
            -- Only set cursor if we're in the buffer's window, passing bufnr for safety
            if vim.api.nvim_get_current_buf() == bufnr then
              ui.set_cursor(new_prompt_line_num + 1, col - 1, bufnr)
            end
          end
          ui.move_to_bottom(bufnr)

          auto_write_buffer(bufnr)
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
            local timeout_value = effective_timeout -- Captured before async callback
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
    -- Stop the spinner timer if it was started
    -- Note: spinner_timer is the local variable, buffer_state.spinner_timer is where it's stored
    if spinner_timer then
      vim.fn.timer_stop(spinner_timer)
      buffer_state.spinner_timer = nil
    end
    ui.cleanup_spinner(bufnr) -- Clean up any "Thinking..." message, handles its own modifiable toggles
    state.unlock_buffer(bufnr)
    return
  end
  -- If job started successfully, modifiable remains false (as set at the start of this function).
end

---Get the last request body (for testing)
---@return table<string, any>|nil
function M._get_last_request_body()
  return last_request_body_for_testing
end

---Expose UI update function
---@param bufnr integer
function M.update_ui(bufnr)
  return ui.update_ui(bufnr)
end

return M
