--- Claude provider for Flemma
--- Implements the Claude API integration
local base = require("flemma.provider.base")
local log = require("flemma.logging")
local M = {}

-- Create a new Claude provider instance
function M.new(merged_config)
  local provider = base.new(merged_config) -- Pass the already merged config to base

  -- Claude-specific state (endpoint, version)
  provider.endpoint = "https://api.anthropic.com/v1/messages"
  provider.api_version = "2023-06-01"

  provider:reset()

  -- Set metatable to use Claude methods
  return setmetatable(provider, { __index = setmetatable(M, { __index = base }) })
end

-- Reset provider state (called by base.new and before new requests)
function M.reset(self)
  base.reset(self)
  log.debug("claude.reset(): Reset Claude provider state")
end

-- Get API key from environment, keyring, or prompt
function M.get_api_key(self)
  -- Call the base implementation with Claude-specific parameters
  return base.get_api_key(self, {
    env_var_name = "ANTHROPIC_API_KEY",
    keyring_service_name = "anthropic",
    keyring_key_name = "api",
  })
end

---Build request body for Claude API
---
---@param prompt Prompt The prepared prompt with history and system (from pipeline)
---@param context Context The shared context object (not used, parts already resolved)
---@return table request_body The request body for the API
function M.build_request(self, prompt, context)
  local api_messages = {}

  for _, msg in ipairs(prompt.history) do
    if msg.role == "user" then
      -- Map generic parts (already resolved by pipeline) to Claude-specific format
      local content_blocks = {}

      for _, part in ipairs(msg.parts or {}) do
        if part.kind == "text" then
          table.insert(content_blocks, { type = "text", text = part.text })
        elseif part.kind == "image" then
          table.insert(content_blocks, {
            type = "image",
            source = {
              type = "base64",
              media_type = part.mime_type,
              data = part.data,
            },
          })
          log.debug(
            'claude.build_request: Added image part for "'
              .. (part.filename or "image")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "pdf" then
          table.insert(content_blocks, {
            type = "document",
            source = {
              type = "base64",
              media_type = part.mime_type,
              data = part.data,
            },
          })
          log.debug(
            'claude.build_request: Added document part for "'
              .. (part.filename or "document")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "text_file" then
          table.insert(content_blocks, { type = "text", text = part.text })
          log.debug(
            'claude.build_request: Added text part for "'
              .. (part.filename or "text_file")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "unsupported_file" then
          table.insert(content_blocks, { type = "text", text = "@" .. (part.raw_filename or "") })
        end
      end

      local final_user_content = #content_blocks > 0 and content_blocks or ""
      table.insert(api_messages, {
        role = msg.role,
        content = final_user_content,
      })
    elseif msg.role == "assistant" then
      -- Extract text from parts, skip thinking nodes
      local text_parts = {}
      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "text" then
          table.insert(text_parts, p.text or "")
        elseif p.kind == "thinking" then
          -- Skip thinking nodes - Claude doesn't need them
        end
      end
      table.insert(api_messages, {
        role = msg.role,
        content = { { type = "text", text = table.concat(text_parts, "") } },
      })
    end
  end

  local request_body = {
    model = self.parameters.model,
    messages = api_messages,
    system = prompt.system,
    max_tokens = self.parameters.max_tokens,
    temperature = self.parameters.temperature,
    stream = true,
  }

  return request_body
end

-- Get request headers for Claude API
function M.get_request_headers(self)
  local api_key = self:get_api_key()

  return {
    "x-api-key: " .. api_key,
    "anthropic-version: " .. self.api_version,
    "content-type: application/json",
  }
end

-- Get API endpoint
--- Process a single line of Claude API streaming response
--- Parses Claude's server-sent events format and extracts content, usage, and error information
---@param self table The Claude provider instance
---@param line string A single line from the Claude API response stream
---@param callbacks ProviderCallbacks Table of callback functions to handle parsed data
function M.process_response_line(self, line, callbacks)
  -- Skip empty lines
  if not line or line == "" then
    return
  end

  -- First try parsing the line directly as JSON for error responses
  local ok, error_data = pcall(vim.fn.json_decode, line)
  if ok and error_data.type == "error" then
    local msg = "Claude API error"
    if error_data.error and error_data.error.message then
      msg = error_data.error.message
    end

    -- Log the error
    log.error("claude.process_response_line(): Claude API error: " .. log.inspect(msg))

    if callbacks.on_error then
      callbacks.on_error(msg) -- Keep original message for user notification
    end
    return
  end

  -- Check for expected format: lines should start with "event: " or "data: "
  if not (line:match("^event: ") or line:match("^data: ")) then
    -- This is not a standard SSE line or potentially a non-SSE JSON error
    log.debug("claude.process_response_line(): Received non-SSE line, adding to accumulator: " .. line)

    -- Add to response accumulator for potential multi-line JSON response
    self:_buffer_response_line(line)

    -- Try parsing as a direct JSON error response
    local parse_ok, error_json = pcall(vim.fn.json_decode, line)
    if parse_ok and type(error_json) == "table" and error_json.error then
      local msg = "Claude API error"
      if error_json.error.message then
        msg = error_json.error.message
      end

      log.error("claude.process_response_line(): ... Claude API error (parsed from non-SSE line): " .. log.inspect(msg))

      if callbacks.on_error then
        callbacks.on_error(msg) -- Keep original message for user notification
      end
      return
    end

    -- If we can't parse it as an error, it will be handled by base class finalize_response
    return
  end

  -- Handle event lines (event: type)
  if line:match("^event: ") then
    local event_type = line:gsub("^event: ", "")
    log.debug("claude.process_response_line(): Received event type: " .. event_type)
    return
  end

  -- Extract JSON from data: prefix
  local json_str = line:gsub("^data: ", "")

  -- Handle [DONE] message (Note: Claude doesn't typically send [DONE])
  if json_str == "[DONE]" then
    log.debug("claude.process_response_line(): Received [DONE] message from Claude API (unexpected)")
    return
  end

  -- Parse the JSON data
  local parse_ok, data = pcall(vim.fn.json_decode, json_str)
  if not parse_ok then
    log.error("claude.process_response_line(): Failed to parse JSON from Claude API response: " .. json_str)
    return
  end

  -- Validate the response structure
  if type(data) ~= "table" then
    log.error(
      "claude.process_response_line(): Expected table in Claude API response, got type: "
        .. type(data)
        .. ", data: "
        .. log.inspect(data)
    )
    return
  end

  -- Handle error responses
  if data.type == "error" then
    local msg = "Claude API error"
    if data.error and data.error.message then
      msg = data.error.message
    end

    log.error("claude.process_response_line(): Claude API error in response data: " .. log.inspect(msg))

    if callbacks.on_error then
      callbacks.on_error(msg) -- Keep original message for user notification
    end
    return
  end

  -- Handle ping events
  if data.type == "ping" then
    log.debug("claude.process_response_line(): Received ping event")
    return
  end

  -- Track usage information from message_start event
  if data.type == "message_start" then
    log.debug("claude.process_response_line(): Received message_start event")
    if data.message and data.message.usage and data.message.usage.input_tokens then
      log.debug(
        "claude.process_response_line(): ... Input tokens from message_start: " .. data.message.usage.input_tokens
      )
      if callbacks.on_usage then
        callbacks.on_usage({
          type = "input",
          tokens = data.message.usage.input_tokens,
        })
      end
    else
      log.debug("claude.process_response_line(): ... No usage information in message_start event")
    end
  end

  -- Track output tokens from usage field in any event (including message_delta)
  if type(data.usage) == "table" and data.usage.output_tokens then
    log.debug("claude.process_response_line(): ... Output tokens update: " .. data.usage.output_tokens)
    if callbacks.on_usage then
      callbacks.on_usage({
        type = "output",
        tokens = data.usage.output_tokens,
      })
    end
  end

  -- Handle message_delta event (mostly for logging the event type now)
  if data.type == "message_delta" then
    log.debug("claude.process_response_line(): Received message_delta event")
    -- Usage is handled above
  end

  -- Handle message_stop event
  if data.type == "message_stop" then
    log.debug("claude.process_response_line(): Received message_stop event")
    if callbacks.on_response_complete then
      callbacks.on_response_complete()
    end
  end

  -- Handle content_block_start event
  if data.type == "content_block_start" then
    log.debug("claude.process_response_line(): Received content_block_start event for index " .. tostring(data.index))
  end

  -- Handle content_block_stop event
  if data.type == "content_block_stop" then
    log.debug("claude.process_response_line(): Received content_block_stop event for index " .. tostring(data.index))
  end

  -- Handle content_block_delta event
  if data.type == "content_block_delta" then
    if not data.delta then
      log.error(
        "claude.process_response_line(): Received content_block_delta without delta field: " .. log.inspect(data)
      )
      return
    end

    if data.delta.type == "text_delta" and data.delta.text then
      log.debug("claude.process_response_line(): ... Content text delta: " .. log.inspect(data.delta.text))
      self:_mark_response_successful() -- Mark that we've received actual content

      if callbacks.on_content then
        callbacks.on_content(data.delta.text)
      end
    elseif data.delta.type == "input_json_delta" and data.delta.partial_json ~= nil then
      log.debug(
        "claude.process_response_line(): ... Content input_json_delta: " .. log.inspect(data.delta.partial_json)
      )
      -- Tool use JSON deltas are not displayed directly
    elseif data.delta.type == "thinking_delta" and data.delta.thinking then
      log.debug("claude.process_response_line(): ... Content thinking delta: " .. log.inspect(data.delta.thinking))
      -- Thinking deltas are not displayed directly
    elseif data.delta.type == "signature_delta" and data.delta.signature then
      log.debug("claude.process_response_line(): ... Content signature delta received")
      -- Signature deltas are not displayed
    else
      log.error(
        "claude.process_response_line(): Received content_block_delta with unknown delta type: "
          .. log.inspect(data.delta.type)
          .. ", delta: "
          .. log.inspect(data.delta)
      )
    end
  elseif
    data.type
    and not (
      data.type == "message_start"
      or data.type == "message_stop"
      or data.type == "message_delta"
      or data.type == "content_block_start"
      or data.type == "content_block_stop"
      or data.type == "ping"
    )
  then
    log.error(
      "claude.process_response_line(): Received unknown event type from Claude API: "
        .. log.inspect(data.type)
        .. ", data: "
        .. log.inspect(data)
    )
  end
end

-- Import helper: Convert JS object notation to valid JSON
local function import_prepare_json(content)
  local lines = {}
  -- Process each line individually
  for line in content:gmatch("[^\r\n]+") do
    -- Only look for unquoted property names at the start of the line
    line = line:gsub("^%s*([%w_%.-]+)%s*:", function(prop)
      return string.format('"%s":', prop)
    end)
    lines[#lines + 1] = line
  end

  -- Join lines back together with spaces
  return table.concat(lines, " ")
end

-- Import helper: Extract content between anthropic.messages.create() call
local function import_extract_content(lines)
  local content = {}
  local capturing = false

  for _, line in ipairs(lines) do
    if line:match("anthropic%.messages%.create%(") then
      capturing = true
      -- Get everything after the opening parenthesis
      local after_paren = line:match("%((.*)$")
      if after_paren then
        content[#content + 1] = after_paren
      end
    elseif capturing then
      if line:match("^%s*%}%)%s*;%s*$") then
        -- Last line - only take the closing brace
        content[#content + 1] = "}"
        break
      else
        content[#content + 1] = line
      end
    end
  end

  return table.concat(content, "\n")
end

-- Import helper: Convert message content to text
local function import_get_message_text(content)
  if type(content) == "string" then
    return content
  elseif type(content) == "table" then
    if content[1] and content[1].type == "text" then
      return content[1].text
    end
  end
  return ""
end

-- Import helper: Generate chat file content from parsed API data
local function import_generate_chat(data)
  local output = {}

  -- Add system message if present
  if data.system then
    table.insert(output, "@System: " .. data.system)
    table.insert(output, "")
  end

  -- Process messages
  for _, msg in ipairs(data.messages or {}) do
    local role_type = msg.role == "user" and "@You: " or "@Assistant: "
    local text = import_get_message_text(msg.content)

    -- Add blank line before message if needed
    if #output > 0 and output[#output] ~= "" then
      table.insert(output, "")
    end

    table.insert(output, role_type .. text)
  end

  return table.concat(output, "\n")
end

-- Try to import from buffer lines (Claude Workbench format)
function M.try_import_from_buffer(self, lines)
  -- Extract and prepare content
  local content = import_extract_content(lines)
  if #content == 0 then
    vim.notify("No Claude API call found in buffer", vim.log.levels.ERROR)
    return nil
  end

  local json_str = import_prepare_json(content)

  -- Parse JSON with better error handling
  local ok, data = pcall(vim.fn.json_decode, json_str)
  if not ok then
    -- Log the problematic JSON string for debugging
    -- Get temp dir and path separator
    local tmp_path = os.tmpname()
    local tmp_dir = tmp_path:match("^(.+)[/\\]")
    local sep = tmp_path:match("[/\\]")
    local debug_file = io.open(tmp_dir .. sep .. "flemma_import_debug.log", "w")
    if debug_file then
      debug_file:write("Original content:\n")
      debug_file:write(content .. "\n\n")
      debug_file:write("Prepared JSON:\n")
      debug_file:write(json_str .. "\n")
      debug_file:close()
    end

    vim.notify(
      "Failed to parse API call data. Debug info written to " .. tmp_dir .. sep .. "flemma_import_debug.log",
      vim.log.levels.ERROR
    )
    return nil
  end

  -- Generate chat content
  local chat_content = import_generate_chat(data)
  return chat_content
end

return M
