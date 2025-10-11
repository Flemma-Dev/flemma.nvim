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

      table.insert(api_messages, {
        role = msg.role,
        content = final_api_content,
      })
    elseif msg.role == "assistant" then
      -- Extract text from parts, skip thinking nodes
      local text_parts = {}
      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "text" then
          table.insert(text_parts, p.text or "")
        elseif p.kind == "thinking" then
          -- Skip thinking nodes - OpenAI doesn't need them
        end
      end
      table.insert(api_messages, {
        role = msg.role,
        content = table.concat(text_parts, ""),
      })
    end
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
  -- Skip empty lines
  if not line or line == "" then
    return
  end

  -- Handle final chunk with usage information (empty choices array with usage data)
  if line:match("^data: ") then
    local json_str = line:gsub("^data: ", "")
    local ok, data = pcall(vim.fn.json_decode, json_str)

    if ok and data and data.choices and #data.choices == 0 and data.usage then
      log.debug(
        "openai.process_response_line(): Received final chunk with usage information: " .. log.inspect(data.usage)
      )

      -- Process usage information
      if type(data.usage) == "table" then
        if callbacks.on_usage and data.usage.prompt_tokens then
          callbacks.on_usage({
            type = "input",
            tokens = data.usage.prompt_tokens,
          })
        end
        if callbacks.on_usage and data.usage.completion_tokens then
          callbacks.on_usage({
            type = "output", -- Represents visible completion tokens
            tokens = data.usage.completion_tokens,
          })
        end
        -- Check for reasoning tokens in completion_tokens_details
        if
          callbacks.on_usage
          and data.usage.completion_tokens_details
          and type(data.usage.completion_tokens_details) == "table"
          and data.usage.completion_tokens_details.reasoning_tokens
        then
          callbacks.on_usage({
            type = "thoughts",
            tokens = data.usage.completion_tokens_details.reasoning_tokens,
          })
          log.debug(
            "openai.process_response_line(): Parsed reasoning_tokens: "
              .. data.usage.completion_tokens_details.reasoning_tokens
          )
        end

        -- Signal response completion (this is the only place we should call it)
        if callbacks.on_response_complete then
          callbacks.on_response_complete()
        end
      end
      return
    end
  end

  -- Check for expected format: lines should start with "data: "
  if not line:match("^data: ") then
    log.debug("openai.process_response_line(): Received non-SSE line, adding to accumulator: " .. line)
    self:_buffer_response_line(line)

    -- Try parsing as a direct JSON error response (for single-line errors)
    local ok, error_data = pcall(vim.fn.json_decode, line)
    if ok and error_data and type(error_data) == "table" and error_data.error then
      local msg = "OpenAI API error"
      if error_data.error.message then
        msg = error_data.error.message
      end
      log.error(
        "openai.process_response_line(): OpenAI API error (parsed from single non-SSE line): " .. log.inspect(msg)
      )
      if callbacks.on_error then
        callbacks.on_error(msg)
      end
      return -- Error handled
    end
    -- If not a single-line parseable error, it will be handled by base class finalize_response
    return
  end

  -- Extract JSON from data: prefix
  local json_str = line:gsub("^data: ", "")

  -- Handle [DONE] message
  if json_str == "[DONE]" then
    log.debug("openai.process_response_line(): Received [DONE] message")
    return
  end

  local parse_ok, data = pcall(vim.fn.json_decode, json_str)
  if not parse_ok then
    log.error("openai.process_response_line(): Failed to parse JSON from response: " .. json_str)
    return
  end

  -- Validate the response structure
  if type(data) ~= "table" then
    log.error(
      "openai.process_response_line(): Expected table in response, got type: "
        .. type(data)
        .. ", data: "
        .. log.inspect(data)
    )
    return
  end

  -- Handle error responses
  if data.error then
    local msg = "OpenAI API error"
    if data.error and data.error.message then
      msg = data.error.message
    end

    log.error("openai.process_response_line(): OpenAI API error in response data: " .. log.inspect(msg))

    if callbacks.on_error then
      callbacks.on_error(msg) -- Keep original message for user notification
    end
    return
  end

  -- Note: Usage information is now handled in the final chunk with empty choices array

  -- Handle content deltas
  if not data.choices then
    log.error(
      "openai.process_response_line(): Expected 'choices' in response data, but not found: " .. log.inspect(data)
    )
    return
  end

  if not data.choices[1] then
    log.error(
      "openai.process_response_line(): Expected at least one choice in response, but none found: " .. log.inspect(data)
    )
    return
  end

  if not data.choices[1].delta then
    log.error(
      "openai.process_response_line(): Expected 'delta' in first choice, but not found: "
        .. log.inspect(data.choices[1])
    )
    return
  end

  local delta = data.choices[1].delta

  -- Check if this is the role marker without content
  if delta.role == "assistant" and not delta.content then
    -- This is just the role marker, skip it
    log.debug("openai.process_response_line(): Received assistant role marker, skipping")
    return
  end

  -- Handle actual content
  if delta.content then
    log.debug("openai.process_response_line(): Content delta: " .. log.inspect(delta.content))
    self:_mark_response_successful() -- Mark that we've received actual content

    if callbacks.on_content then
      callbacks.on_content(delta.content)
    end
  end

  -- Check if this is the finish_reason (only if it has a meaningful value, not null)
  if
    data.choices[1].finish_reason
    and data.choices[1].finish_reason ~= vim.NIL
    and data.choices[1].finish_reason ~= nil
  then
    log.debug("openai.process_response_line(): Received finish_reason: " .. log.inspect(data.choices[1].finish_reason))
    -- We'll let the final chunk with usage information trigger on_response_complete
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
