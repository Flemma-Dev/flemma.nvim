--- OpenAI provider for Flemma
--- Implements the OpenAI Responses API integration
local base = require("flemma.provider.base")
local log = require("flemma.logging")
local models = require("flemma.models")

---@class flemma.provider.OpenAI : flemma.provider.Base
local M = {}

-- Inherit from base provider
setmetatable(M, { __index = base })

---@type flemma.provider.Metadata
M.metadata = {
  name = "openai",
  display_name = "OpenAI",
  capabilities = {
    supports_reasoning = true,
    supports_thinking_budget = false,
    outputs_thinking = false,
  },
  default_parameters = {
    cache_retention = "short",
  },
}

-- OpenAI's output_tokens already includes reasoning_tokens,
-- so we should NOT add thoughts_tokens separately for cost calculation.
M.output_has_thoughts = true

---@param merged_config flemma.provider.Parameters
---@return flemma.provider.OpenAI
function M.new(merged_config)
  local provider = base.new(merged_config) -- Pass the already merged config to base

  -- OpenAI Responses API endpoint
  provider.endpoint = "https://api.openai.com/v1/responses"

  provider:reset()

  -- Set metatable to use OpenAI methods
  ---@diagnostic disable-next-line: return-type-mismatch
  return setmetatable(provider, { __index = setmetatable(M, { __index = base }) })
end

---@param self flemma.provider.OpenAI
function M.reset(self)
  base.reset(self)
  self._response_buffer.extra.current_tool_call = nil
  log.debug("openai.reset(): Reset OpenAI provider state")
end

---@param self flemma.provider.OpenAI
---@return string|nil
function M.get_api_key(self)
  -- Call the base implementation with OpenAI-specific parameters
  return base.get_api_key(self, {
    env_var_name = "OPENAI_API_KEY",
    keyring_service_name = "openai",
    keyring_key_name = "api",
  })
end

---Build request body for OpenAI Responses API
---
---@param prompt flemma.provider.Prompt The prepared prompt with history and system (from pipeline)
---@param context? flemma.Context The shared context object (used for prompt caching hints)
---@return table<string, any> request_body The request body for the API
function M.build_request(self, prompt, context)
  local input_items = {}

  -- Add system message first if present
  if prompt.system and #prompt.system > 0 then
    -- Use "developer" role for reasoning models, "system" for others
    local system_role = (self.parameters.reasoning and self.parameters.reasoning ~= "") and "developer" or "system"
    table.insert(input_items, {
      role = system_role,
      content = prompt.system,
    })
  end

  for _, msg in ipairs(prompt.history) do
    if msg.role == "user" then
      -- Map generic parts (already resolved by pipeline) to Responses API format
      local content_parts_for_api = {}
      local tool_results = {}

      for _, part in ipairs(msg.parts or {}) do
        if part.kind == "text" then
          if vim.trim(part.text or "") ~= "" then
            table.insert(content_parts_for_api, { type = "input_text", text = part.text })
          end
        elseif part.kind == "image" then
          table.insert(content_parts_for_api, {
            type = "input_image",
            image_url = part.data_url,
            detail = "auto",
          })
          log.debug(
            'openai.build_request: Added input_image part for "'
              .. (part.filename or "image")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "pdf" then
          table.insert(content_parts_for_api, {
            type = "input_file",
            filename = part.filename or "document.pdf",
            file_data = part.data_url,
          })
          log.debug(
            'openai.build_request: Added file part for PDF "'
              .. (part.filename or "document")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "text_file" then
          table.insert(content_parts_for_api, { type = "input_text", text = part.text })
          log.debug(
            'openai.build_request: Added input_text part for "'
              .. (part.filename or "text_file")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "unsupported_file" then
          table.insert(content_parts_for_api, { type = "input_text", text = "@" .. (part.filename or "") })
        elseif part.kind == "tool_result" then
          -- Normalize tool ID for OpenAI compatibility (handles Vertex URN-style IDs)
          local normalized_id = base.normalize_tool_id(part.tool_use_id)
          table.insert(tool_results, {
            call_id = normalized_id,
            content = part.content,
            is_error = part.is_error,
          })
          log.debug("openai.build_request: Added tool_result for " .. normalized_id)
        end
      end

      -- Add tool results FIRST as top-level function_call_output items
      -- Tool results must come before any new user content in the same turn
      for _, tr in ipairs(tool_results) do
        -- OpenAI doesn't have is_error field; prefix content with "Error: " to signal error semantics
        local result_content = tr.content
        if tr.is_error then
          result_content = "Error: " .. (tr.content or "Tool execution failed")
          log.debug("openai.build_request: Tool result marked as error for " .. tr.call_id)
        end
        table.insert(input_items, {
          type = "function_call_output",
          call_id = tr.call_id,
          output = result_content,
        })
      end

      -- Add user message AFTER tool results, only if it has non-tool-result content
      if #content_parts_for_api > 0 then
        table.insert(input_items, {
          role = "user",
          content = content_parts_for_api,
        })
      end
    elseif msg.role == "assistant" then
      -- Emit assistant parts as flat top-level items in the input array
      -- Collect text parts for a single message item
      local text_parts = {}

      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "text" then
          table.insert(text_parts, p.text or "")
        elseif p.kind == "thinking" then
          -- Skip thinking nodes for now (future enhancement)
        elseif p.kind == "tool_use" then
          -- Flush any accumulated text before the tool call
          if #text_parts > 0 then
            local text = table.concat(text_parts, "")
            if #text > 0 then
              table.insert(input_items, {
                role = "assistant",
                content = text,
              })
            end
            text_parts = {}
          end

          -- Normalize tool ID for OpenAI compatibility (handles Vertex URN-style IDs)
          local normalized_id = base.normalize_tool_id(p.id)
          table.insert(input_items, {
            type = "function_call",
            call_id = normalized_id,
            name = p.name,
            arguments = vim.fn.json_encode(p.input),
          })
          log.debug("openai.build_request: Added function_call for " .. p.name .. " (" .. normalized_id .. ")")
        end
      end

      -- Flush remaining text
      if #text_parts > 0 then
        local text = table.concat(text_parts, "")
        if #text > 0 then
          table.insert(input_items, {
            type = "message",
            role = "assistant",
            content = { { type = "output_text", text = text, annotations = {} } },
            status = "completed",
          })
        end
      end
    end
  end

  -- Build tools array from registry (OpenAI format, filtered by per-buffer opts if present)
  local tools_module = require("flemma.tools")
  local all_tools = tools_module.get_for_prompt(prompt.opts)
  local tools_array = {}

  for _, definition in pairs(all_tools) do
    table.insert(tools_array, {
      type = "function",
      name = definition.name,
      description = tools_module.build_description(definition),
      parameters = definition.input_schema,
    })
  end

  local request_body = {
    model = self.parameters.model,
    input = input_items,
    stream = true,
    store = false,
    max_output_tokens = self.parameters.max_tokens,
  }

  -- Add tools if any are registered
  if #tools_array > 0 then
    request_body.tools = tools_array
    request_body.tool_choice = "auto"
    log.debug("openai.build_request: Added " .. #tools_array .. " tools to request")
  end

  if self.parameters.reasoning and self.parameters.reasoning ~= "" then
    request_body.reasoning = { effort = self.parameters.reasoning }
    log.debug(
      "openai.build_request: Using max_output_tokens: "
        .. tostring(self.parameters.max_tokens)
        .. " and reasoning.effort: "
        .. self.parameters.reasoning
    )
  else
    request_body.temperature = self.parameters.temperature
    log.debug(
      "openai.build_request: Using max_output_tokens: "
        .. tostring(self.parameters.max_tokens)
        .. " and temperature: "
        .. tostring(self.parameters.temperature)
    )
  end

  -- Prompt caching (Responses API)
  local cache_retention = self.parameters.cache_retention or "short"
  if cache_retention ~= "none" then
    local filename = context and context:get_filename() or ""
    if filename ~= "" then
      request_body.prompt_cache_key = filename
    end
    request_body.prompt_cache_retention = cache_retention == "long" and "24h" or "in_memory"
  end

  return request_body
end

---@param self flemma.provider.OpenAI
---@return string[]
function M.get_request_headers(self)
  local api_key = self:get_api_key()

  return {
    "Authorization: Bearer " .. api_key,
    "Content-Type: application/json",
  }
end

--- Process a single line of OpenAI Responses API streaming response
--- Parses OpenAI's server-sent events format and extracts content, usage, and completion information
---@param self flemma.provider.OpenAI
---@param line string A single line from the OpenAI API response stream
---@param callbacks flemma.provider.Callbacks Table of callback functions to handle parsed data
function M.process_response_line(self, line, callbacks)
  -- Use base SSE parser (no [DONE] in Responses API)
  local parsed = base._parse_sse_line(line, { allow_done = false })
  if not parsed then
    -- Handle non-SSE lines
    base._handle_non_sse_line(self, line, callbacks)
    return
  end

  -- Skip event: lines (we use data.type instead)
  if parsed.type == "event" then
    return
  end

  -- Handle non-data SSE lines
  if parsed.type ~= "data" then
    return
  end

  -- Parse JSON content
  local ok, data = pcall(vim.fn.json_decode, parsed.content)
  if not ok then
    log.error("openai.process_response_line(): Failed to parse JSON from response: " .. parsed.content)
    return
  end

  if type(data) ~= "table" then
    log.error("openai.process_response_line(): Expected table in response, got type: " .. type(data))
    return
  end

  -- Handle error responses
  if data.error then
    local error_message = self:extract_json_response_error(data) or "Unknown API error"
    log.error("openai.process_response_line(): OpenAI API error: " .. log.inspect(error_message))
    if callbacks.on_error then
      callbacks.on_error(error_message)
    end
    return
  end

  local event_type = data.type

  if not event_type then
    log.debug("openai.process_response_line(): Data without type field, skipping")
    return
  end

  -- Handle text content deltas
  if event_type == "response.output_text.delta" then
    if data.delta then
      log.debug("openai.process_response_line(): Text delta: " .. log.inspect(data.delta))
      base._signal_content(self, data.delta, callbacks)
    end
    return
  end

  -- Handle function call start
  if event_type == "response.output_item.added" then
    if data.item and data.item.type == "function_call" then
      self._response_buffer.extra.current_tool_call = {
        name = data.item.name or "",
        call_id = data.item.call_id or "",
        arguments_json = "",
      }
      log.debug(
        "openai.process_response_line(): Started function_call: "
          .. (data.item.name or "")
          .. " ("
          .. (data.item.call_id or "")
          .. ")"
      )
    elseif data.item and data.item.type == "reasoning" then
      log.debug("openai.process_response_line(): Reasoning item added (ignored for now)")
    end
    return
  end

  -- Handle function call arguments streaming
  if event_type == "response.function_call_arguments.delta" then
    if data.delta and self._response_buffer.extra.current_tool_call then
      self._response_buffer.extra.current_tool_call.arguments_json = self._response_buffer.extra.current_tool_call.arguments_json
        .. data.delta
      log.debug("openai.process_response_line(): Appending function_call arguments")
    end
    return
  end

  -- Handle function call completion
  if event_type == "response.output_item.done" then
    if data.item and data.item.type == "function_call" then
      local arguments_json = data.item.arguments or ""
      local parse_ok, input = pcall(vim.fn.json_decode, arguments_json)
      if not parse_ok then
        input = {}
        log.warn("openai.process_response_line(): Failed to parse tool arguments JSON: " .. arguments_json)
      end

      local json_str = vim.fn.json_encode(input)

      local max_ticks = 0
      for ticks in json_str:gmatch("`+") do
        max_ticks = math.max(max_ticks, #ticks)
      end
      local fence = string.rep("`", math.max(3, max_ticks + 1))

      -- Use appropriate prefix based on what's already accumulated
      local prefix = ""
      if self:_has_content() then
        prefix = self:_content_ends_with_newline() and "\n" or "\n\n"
      end
      local formatted = string.format(
        "%s**Tool Use:** `%s` (`%s`)\n\n%sjson\n%s\n%s\n",
        prefix,
        data.item.name or "",
        data.item.call_id or "",
        fence,
        json_str,
        fence
      )

      base._signal_content(self, formatted, callbacks)
      log.debug("openai.process_response_line(): Emitted tool_use block for " .. (data.item.name or ""))

      -- Reset tool state
      self._response_buffer.extra.current_tool_call = nil
    end
    return
  end

  -- Handle response completion with usage
  if event_type == "response.completed" then
    log.debug("openai.process_response_line(): Response completed")

    if data.response and data.response.usage and type(data.response.usage) == "table" then
      local usage = data.response.usage

      -- Extract cached tokens first so we can subtract from input_tokens.
      -- OpenAI's input_tokens includes cached_tokens as a subset, so we normalize
      -- to make input_tokens mean "non-cached input" (matching Anthropic's semantics).
      local cached_tokens = (
        usage.input_tokens_details
        and usage.input_tokens_details.cached_tokens
        and usage.input_tokens_details.cached_tokens > 0
      )
          and usage.input_tokens_details.cached_tokens
        or 0

      if callbacks.on_usage and usage.input_tokens then
        callbacks.on_usage({ type = "input", tokens = usage.input_tokens - cached_tokens })
      end
      if callbacks.on_usage and usage.output_tokens then
        callbacks.on_usage({ type = "output", tokens = usage.output_tokens })
      end
      if callbacks.on_usage and usage.output_tokens_details and usage.output_tokens_details.reasoning_tokens then
        callbacks.on_usage({ type = "thoughts", tokens = usage.output_tokens_details.reasoning_tokens })
      end
      if callbacks.on_usage and cached_tokens > 0 then
        callbacks.on_usage({ type = "cache_read", tokens = cached_tokens })
        log.debug("openai.process_response_line(): Cached input tokens: " .. tostring(cached_tokens))
      end
    end

    if callbacks.on_response_complete then
      callbacks.on_response_complete()
    end
    return
  end

  -- Handle response failure
  if event_type == "response.failed" then
    local error_message = "Response failed"
    if data.response and data.response.error then
      error_message = data.response.error.message or error_message
    end
    log.error("openai.process_response_line(): " .. error_message)
    if callbacks.on_error then
      callbacks.on_error(error_message)
    end
    return
  end

  -- All other events are ignored
  log.debug("openai.process_response_line(): Ignoring event type: " .. event_type)
end

---Validate provider-specific parameters
---@param model_name string The model name
---@param parameters table<string, any> The parameters to validate
---@return boolean success True if validation passes (warnings don't fail)
function M.validate_parameters(model_name, parameters)
  -- Check for reasoning parameter support
  local reasoning_value = parameters.reasoning
  if reasoning_value ~= nil and reasoning_value ~= "" then
    local model_info = models.providers.openai
      and models.providers.openai.models
      and models.providers.openai.models[model_name]
    local supports_reasoning_effort = model_info and model_info.supports_reasoning_effort == true

    if not supports_reasoning_effort then
      local warning_msg = string.format(
        "Flemma: The 'reasoning' parameter is not supported by the selected OpenAI model '%s'. It may be ignored or cause an API error.",
        model_name
      )
      vim.notify(warning_msg, vim.log.levels.WARN, { title = "Flemma Configuration" }) ---@diagnostic disable-line: redundant-parameter
      log.warn(warning_msg)
    end
  end

  -- Check for temperature <> 1.0 with OpenAI o-series models when reasoning is active
  local temp_value = parameters.temperature
  local model_info = models.providers.openai
    and models.providers.openai.models
    and models.providers.openai.models[model_name]
  local supports_reasoning_effort = model_info and model_info.supports_reasoning_effort == true

  if
    reasoning_value ~= nil
    and reasoning_value ~= ""
    and supports_reasoning_effort
    and string.sub(model_name, 1, 1) == "o"
    and temp_value ~= nil
    and temp_value ~= 1
    and temp_value ~= 1.0
  then
    local temp_warning_msg = string.format(
      "Flemma: For OpenAI o-series models with 'reasoning' active, 'temperature' must be 1 or omitted. Current value is '%s'. The API will likely reject this.",
      tostring(temp_value)
    )
    vim.notify(temp_warning_msg, vim.log.levels.WARN, { title = "Flemma Configuration" }) ---@diagnostic disable-line: redundant-parameter
    log.warn(temp_warning_msg)
  end

  return true
end

return M
