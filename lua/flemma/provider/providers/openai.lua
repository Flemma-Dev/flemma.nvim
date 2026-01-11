--- OpenAI provider for Flemma
--- Implements the OpenAI API integration
local base = require("flemma.provider.base")
local log = require("flemma.logging")
local models = require("flemma.models")
local M = {}

-- Inherit from base provider
setmetatable(M, { __index = base })

-- Create a new OpenAI provider instance
function M.new(merged_config)
  local provider = base.new(merged_config) -- Pass the already merged config to base

  -- OpenAI-specific state (endpoint, version)
  provider.endpoint = "https://api.openai.com/v1/chat/completions"
  provider.api_version = "2023-05-15" -- OpenAI API version

  provider:reset()

  -- Set metatable to use OpenAI methods
  return setmetatable(provider, { __index = setmetatable(M, { __index = base }) })
end

-- Reset provider state (called by base.new and before new requests)
function M.reset(self)
  base.reset(self)
  self._response_buffer.extra.tool_calls = {}
  log.debug("openai.reset(): Reset OpenAI provider state")
end

-- Get API key from environment, keyring, or prompt
function M.get_api_key(self)
  -- Call the base implementation with OpenAI-specific parameters
  return base.get_api_key(self, {
    env_var_name = "OPENAI_API_KEY",
    keyring_service_name = "openai",
    keyring_key_name = "api",
  })
end

---Build request body for OpenAI API
---
---@param prompt Prompt The prepared prompt with history and system (from pipeline)
---@param context Context The shared context object (not used, parts already resolved)
---@return table request_body The request body for the API
function M.build_request(self, prompt, context)
  local api_messages = {}

  -- Add system message first if present
  if prompt.system and #prompt.system > 0 then
    table.insert(api_messages, {
      role = "system",
      content = prompt.system,
    })
  end

  for _, msg in ipairs(prompt.history) do
    if msg.role == "user" then
      -- Map generic parts (already resolved by pipeline) to OpenAI-specific format
      local content_parts_for_api = {}
      local has_multimedia_part = false
      local tool_results = {}

      for _, part in ipairs(msg.parts or {}) do
        if part.kind == "text" then
          table.insert(content_parts_for_api, { type = "text", text = part.text })
        elseif part.kind == "image" then
          table.insert(content_parts_for_api, {
            type = "image_url",
            image_url = {
              url = part.data_url,
              detail = "auto",
            },
          })
          has_multimedia_part = true
          log.debug(
            'openai.build_request: Added image_url part for "'
              .. (part.filename or "image")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "pdf" then
          table.insert(content_parts_for_api, {
            type = "file",
            file = {
              filename = part.filename or "document.pdf",
              file_data = part.data_url,
            },
          })
          has_multimedia_part = true
          log.debug(
            'openai.build_request: Added file part for PDF "'
              .. (part.filename or "document")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "text_file" then
          table.insert(content_parts_for_api, { type = "text", text = part.text })
          log.debug(
            'openai.build_request: Added text part for "'
              .. (part.filename or "text_file")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "unsupported_file" then
          table.insert(content_parts_for_api, { type = "text", text = "@" .. (part.raw_filename or "") })
        elseif part.kind == "tool_result" then
          table.insert(tool_results, {
            tool_call_id = part.tool_use_id,
            content = part.content,
            is_error = part.is_error,
          })
          log.debug("openai.build_request: Added tool_result for " .. part.tool_use_id)
        end
      end

      local final_api_content
      if #content_parts_for_api == 0 then
        final_api_content = ""
      elseif has_multimedia_part then
        final_api_content = content_parts_for_api
      else
        -- Concatenate all text parts into a single string
        local text_only_accumulator = {}
        for _, api_part in ipairs(content_parts_for_api) do
          if api_part.type == "text" and api_part.text then
            table.insert(text_only_accumulator, api_part.text)
          end
        end
        final_api_content = table.concat(text_only_accumulator)
      end

      -- Add tool results FIRST as separate role:tool messages (OpenAI format)
      -- Tool results must come before any new user content in the same turn
      for _, tr in ipairs(tool_results) do
        -- OpenAI doesn't have is_error field; prefix content with "Error: " to signal error semantics
        local result_content = tr.content
        if tr.is_error then
          result_content = "Error: " .. (tr.content or "Tool execution failed")
          log.debug("openai.build_request: Tool result marked as error for " .. tr.tool_call_id)
        end
        table.insert(api_messages, {
          role = "tool",
          tool_call_id = tr.tool_call_id,
          content = result_content,
        })
      end

      -- Add user message AFTER tool results, only if it has non-tool-result content
      if #content_parts_for_api > 0 or (final_api_content ~= "" and #tool_results == 0) then
        table.insert(api_messages, {
          role = msg.role,
          content = final_api_content,
        })
      end
    elseif msg.role == "assistant" then
      -- Extract text and tool_use from parts, skip thinking nodes
      local text_parts = {}
      local tool_calls = {}

      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "text" then
          table.insert(text_parts, p.text or "")
        elseif p.kind == "thinking" then
          -- Skip thinking nodes - OpenAI doesn't need them
        elseif p.kind == "tool_use" then
          table.insert(tool_calls, {
            id = p.id,
            type = "function",
            ["function"] = {
              name = p.name,
              arguments = vim.fn.json_encode(p.input),
            },
          })
          log.debug("openai.build_request: Added tool_use for " .. p.name .. " (" .. p.id .. ")")
        end
      end

      local content = table.concat(text_parts, "")
      local api_msg = {
        role = msg.role,
        content = #content > 0 and content or nil,
      }

      if #tool_calls > 0 then
        api_msg.tool_calls = tool_calls
      end

      table.insert(api_messages, api_msg)
    end
  end

  -- Build tools array from registry (OpenAI format)
  local tools_module = require("flemma.tools")
  local all_tools = tools_module.get_all()
  local tools_array = {}

  for _, def in pairs(all_tools) do
    table.insert(tools_array, {
      type = "function",
      ["function"] = {
        name = def.name,
        description = def.description,
        parameters = def.input_schema,
      },
    })
  end

  local request_body = {
    model = self.parameters.model,
    messages = api_messages,
    -- max_tokens or max_completion_tokens will be set conditionally below
    -- temperature will be set conditionally below
    stream = true,
    stream_options = {
      include_usage = true, -- Request usage information in the final chunk
    },
  }

  -- Add tools if any are registered
  if #tools_array > 0 then
    request_body.tools = tools_array
    request_body.tool_choice = "auto"
    -- MVP: Disable parallel tool use to ensure at most one tool per response
    request_body.parallel_tool_calls = false
    log.debug("openai.build_request: Added " .. #tools_array .. " tools to request")
  end

  -- Use max_completion_tokens for all OpenAI models (recommended by OpenAI)
  request_body.max_completion_tokens = self.parameters.max_tokens

  if self.parameters.reasoning and self.parameters.reasoning ~= "" then
    request_body.reasoning_effort = self.parameters.reasoning
    log.debug(
      "openai.build_request: Using max_completion_tokens: "
        .. tostring(self.parameters.max_tokens)
        .. " and reasoning_effort: "
        .. self.parameters.reasoning
    )
  else
    request_body.temperature = self.parameters.temperature
    log.debug(
      "openai.build_request: Using max_completion_tokens: "
        .. tostring(self.parameters.max_tokens)
        .. " and temperature: "
        .. tostring(self.parameters.temperature)
    )
  end

  return request_body
end

-- Get request headers for OpenAI API
function M.get_request_headers(self)
  local api_key = self:get_api_key()

  return {
    "Authorization: Bearer " .. api_key,
    "Content-Type: application/json",
  }
end

-- Get API endpoint
--- Process a single line of OpenAI API streaming response
--- Parses OpenAI's server-sent events format and extracts content, usage, and completion information
---@param self table The OpenAI provider instance
---@param line string A single line from the OpenAI API response stream
---@param callbacks ProviderCallbacks Table of callback functions to handle parsed data
function M.process_response_line(self, line, callbacks)
  -- Use base SSE parser
  local parsed = base._parse_sse_line(line)
  if not parsed then
    -- Handle non-SSE lines
    base._handle_non_sse_line(self, line, callbacks)
    return
  end

  -- Handle [DONE] message
  if parsed.type == "done" then
    log.debug("openai.process_response_line(): Received [DONE] message")
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
    local msg = self:extract_json_response_error(data)
    log.error("openai.process_response_line(): OpenAI API error: " .. log.inspect(msg))
    if callbacks.on_error then
      callbacks.on_error(msg)
    end
    return
  end

  -- Handle final chunk with usage information
  if data.choices and #data.choices == 0 and data.usage then
    log.debug("openai.process_response_line(): Received final chunk with usage: " .. log.inspect(data.usage))

    if type(data.usage) == "table" then
      if callbacks.on_usage and data.usage.prompt_tokens then
        callbacks.on_usage({ type = "input", tokens = data.usage.prompt_tokens })
      end
      if callbacks.on_usage and data.usage.completion_tokens then
        callbacks.on_usage({ type = "output", tokens = data.usage.completion_tokens })
      end
      if
        callbacks.on_usage
        and data.usage.completion_tokens_details
        and data.usage.completion_tokens_details.reasoning_tokens
      then
        callbacks.on_usage({ type = "thoughts", tokens = data.usage.completion_tokens_details.reasoning_tokens })
      end

      if callbacks.on_response_complete then
        callbacks.on_response_complete()
      end
    end
    return
  end

  -- Handle content deltas
  if not data.choices or not data.choices[1] or not data.choices[1].delta then
    return
  end

  local delta = data.choices[1].delta

  -- Skip role marker without content and without tool_calls
  if delta.role == "assistant" and not delta.content and not delta.tool_calls then
    log.debug("openai.process_response_line(): Received assistant role marker, skipping")
    return
  end

  -- Handle actual content (check for vim.NIL as well)
  if delta.content and delta.content ~= vim.NIL then
    log.debug("openai.process_response_line(): Content delta: " .. log.inspect(delta.content))
    base._signal_content(self, delta.content, callbacks)
  end

  -- Handle tool_calls streaming
  if delta.tool_calls then
    for _, tc in ipairs(delta.tool_calls) do
      local idx = tc.index or 0
      local tool_calls = self._response_buffer.extra.tool_calls or {}

      if tc.id then
        tool_calls[idx] = {
          id = tc.id,
          name = tc["function"] and tc["function"].name or "",
          arguments = tc["function"] and tc["function"].arguments or "",
        }
        log.debug(
          "openai.process_response_line(): Started tool_call: "
            .. (tool_calls[idx].name or "")
            .. " ("
            .. (tool_calls[idx].id or "")
            .. ")"
        )
      elseif tool_calls[idx] then
        if tc["function"] and tc["function"].arguments then
          tool_calls[idx].arguments = tool_calls[idx].arguments .. tc["function"].arguments
          log.debug("openai.process_response_line(): Appending arguments for tool_call index " .. tostring(idx))
        end
      end

      self._response_buffer.extra.tool_calls = tool_calls
    end
  end

  -- Handle finish_reason
  local finish_reason = data.choices[1].finish_reason
  if finish_reason and finish_reason ~= vim.NIL then
    log.debug("openai.process_response_line(): Received finish_reason: " .. log.inspect(finish_reason))

    if finish_reason == "tool_calls" then
      local tool_calls = self._response_buffer.extra.tool_calls or {}
      for _, tc in pairs(tool_calls) do
        local ok, input = pcall(vim.fn.json_decode, tc.arguments)
        if not ok then
          input = {}
          log.warn("openai.process_response_line(): Failed to parse tool arguments JSON: " .. tc.arguments)
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
          tc.name,
          tc.id,
          fence,
          json_str,
          fence
        )

        base._signal_content(self, formatted, callbacks)
        log.debug("openai.process_response_line(): Emitted tool_use block for " .. tc.name)
      end

      self._response_buffer.extra.tool_calls = {}
    end
  end
end

---Validate provider-specific parameters
---@param model_name string The model name
---@param parameters table The parameters to validate
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
      vim.notify(warning_msg, vim.log.levels.WARN, { title = "Flemma Configuration" })
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
    vim.notify(temp_warning_msg, vim.log.levels.WARN, { title = "Flemma Configuration" })
    log.warn(temp_warning_msg)
  end

  return true
end

return M
