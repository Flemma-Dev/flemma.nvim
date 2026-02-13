--- Anthropic provider for Flemma
--- Implements the Anthropic (Claude) API integration
local base = require("flemma.provider.base")
local log = require("flemma.logging")

---@class flemma.provider.Anthropic : flemma.provider.Base
local M = {}

-- Inherit from base provider
setmetatable(M, { __index = base })

---@type flemma.provider.Metadata
M.metadata = {
  name = "anthropic",
  display_name = "Anthropic",
  capabilities = {
    supports_reasoning = false,
    supports_thinking_budget = true,
    outputs_thinking = true,
    min_thinking_budget = 1024,
  },
  default_parameters = {
    thinking_budget = nil,
    cache_retention = "short",
  },
}

-- Anthropic's output_tokens already includes thinking tokens in the usage response,
-- so we should NOT add thoughts_tokens separately for cost calculation.
M.output_has_thoughts = true

---@param merged_config flemma.provider.Parameters
---@return flemma.provider.Anthropic
function M.new(merged_config)
  local provider = base.new(merged_config) -- Pass the already merged config to base

  -- Anthropic-specific state (endpoint, version)
  provider.endpoint = "https://api.anthropic.com/v1/messages"
  provider.api_version = "2023-06-01"

  -- Set metatable BEFORE reset so M.reset (not base.reset) initializes provider-specific state
  setmetatable(provider, { __index = setmetatable(M, { __index = base }) })
  provider:reset()

  ---@diagnostic disable-next-line: return-type-mismatch
  return provider
end

---@param self flemma.provider.Anthropic
function M.reset(self)
  base.reset(self)
  self._response_buffer.extra.accumulated_thinking = ""
  self._response_buffer.extra.accumulated_signature = ""
  self._response_buffer.extra.redacted_thinking_blocks = {}
  self._response_buffer.extra.current_block_type = nil
  self._response_buffer.extra.current_tool_use = nil
  self._response_buffer.extra.accumulated_tool_input = ""
  log.debug("anthropic.reset(): Reset Anthropic provider state")
end

---@param self flemma.provider.Anthropic
---@return string|nil
function M.get_api_key(self)
  -- Call the base implementation with Anthropic-specific parameters
  return base.get_api_key(self, {
    env_var_name = "ANTHROPIC_API_KEY",
    keyring_service_name = "anthropic",
    keyring_key_name = "api",
  })
end

---Build request body for Anthropic API
---
---@param prompt flemma.provider.Prompt The prepared prompt with history and system (from pipeline)
---@param _context? flemma.Context The shared context object (not used, parts already resolved)
---@return table<string, any> request_body The request body for the API
function M.build_request(self, prompt, _context) ---@diagnostic disable-line: unused-local
  local api_messages = {}

  for _, msg in ipairs(prompt.history) do
    if msg.role == "user" then
      -- Map generic parts (already resolved by pipeline) to Anthropic-specific format
      local content_blocks = {}

      -- Tool results must come first in user messages (Anthropic requirement)
      for _, part in ipairs(msg.parts or {}) do
        if part.kind == "tool_result" then
          -- Normalize tool ID for Anthropic compatibility (handles Vertex URN-style IDs)
          local normalized_id = base.normalize_tool_id(part.tool_use_id)
          table.insert(content_blocks, {
            type = "tool_result",
            tool_use_id = normalized_id,
            content = part.content,
            is_error = part.is_error or nil,
          })
          log.debug("anthropic.build_request: Added tool_result for " .. normalized_id)
        end
      end

      -- Then other content
      for _, part in ipairs(msg.parts or {}) do
        if part.kind == "text" then
          if vim.trim(part.text or "") ~= "" then
            table.insert(content_blocks, { type = "text", text = part.text })
          end
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
            'anthropic.build_request: Added image part for "'
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
            'anthropic.build_request: Added document part for "'
              .. (part.filename or "document")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "text_file" then
          table.insert(content_blocks, { type = "text", text = part.text })
          log.debug(
            'anthropic.build_request: Added text part for "'
              .. (part.filename or "text_file")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "unsupported_file" then
          table.insert(content_blocks, { type = "text", text = "@" .. (part.filename or "") })
        end
      end

      -- Skip empty user messages (Anthropic requires non-empty content)
      if #content_blocks > 0 then
        table.insert(api_messages, {
          role = msg.role,
          content = content_blocks,
        })
      else
        log.debug("anthropic.build_request: Skipping empty user message")
      end
    elseif msg.role == "assistant" then
      -- Build content blocks for assistant message
      -- Two-pass approach: thinking/redacted_thinking must precede text/tool_use (API requirement)
      local content_blocks = {}

      -- First pass: collect thinking blocks (only those with signatures or redacted)
      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "thinking" and p.redacted then
          table.insert(content_blocks, {
            type = "redacted_thinking",
            data = p.content,
          })
          log.debug("anthropic.build_request: Added redacted_thinking block")
        elseif p.kind == "thinking" and p.signature and p.signature.provider == "anthropic" then
          table.insert(content_blocks, {
            type = "thinking",
            thinking = p.content,
            signature = p.signature.value,
          })
          log.debug("anthropic.build_request: Added thinking block with signature")
        end
      end

      -- Second pass: collect text and tool_use
      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "text" then
          local text = vim.trim(p.text or "")
          if #text > 0 then
            table.insert(content_blocks, { type = "text", text = text })
          end
        elseif p.kind == "tool_use" then
          -- Normalize tool ID for Anthropic compatibility (handles Vertex URN-style IDs)
          local normalized_id = base.normalize_tool_id(p.id)
          table.insert(content_blocks, {
            type = "tool_use",
            id = normalized_id,
            name = p.name,
            input = p.input,
          })
          log.debug("anthropic.build_request: Added tool_use for " .. p.name .. " (" .. normalized_id .. ")")
        end
      end

      if #content_blocks > 0 then
        table.insert(api_messages, {
          role = msg.role,
          content = content_blocks,
        })
      else
        log.debug("anthropic.build_request: Skipping empty assistant message")
      end
    end
  end

  local cache_retention = self.parameters.cache_retention or "short"
  local cache_control
  if cache_retention == "short" then
    cache_control = { type = "ephemeral" }
  elseif cache_retention == "long" then
    cache_control = { type = "ephemeral", ttl = "1h" }
  end
  -- nil when "none"

  -- Build tools array from registry (filtered by per-buffer opts if present)
  local tools_module = require("flemma.tools")
  local all_tools = tools_module.get_for_prompt(prompt.opts)
  local tools_array = {}

  for _, def in pairs(all_tools) do
    table.insert(tools_array, {
      name = def.name,
      description = tools_module.build_description(def),
      input_schema = def.input_schema,
    })
  end

  -- Stable alphabetical ordering for cache efficiency
  table.sort(tools_array, function(a, b)
    return a.name < b.name
  end)

  -- Breakpoint 1: last tool definition
  if cache_control and #tools_array > 0 then
    tools_array[#tools_array].cache_control = cache_control
  end

  -- Breakpoint 3: last user message's last content block
  if cache_control then
    for i = #api_messages, 1, -1 do
      if api_messages[i].role == "user" then
        local content = api_messages[i].content
        if #content > 0 then
          content[#content].cache_control = cache_control
        end
        break
      end
    end
  end

  local request_body = {
    model = self.parameters.model,
    messages = api_messages,
    max_tokens = self.parameters.max_tokens,
    temperature = self.parameters.temperature,
    stream = true,
  }

  -- Breakpoint 2: system prompt
  if prompt.system and #prompt.system > 0 then
    if cache_control then
      request_body.system = {
        { type = "text", text = prompt.system, cache_control = cache_control },
      }
    else
      request_body.system = prompt.system
    end
  end

  -- Add tools if any are registered
  if #tools_array > 0 then
    request_body.tools = tools_array
    request_body.tool_choice = { type = "auto" }
    log.debug("anthropic.build_request: Added " .. #tools_array .. " tools to request")
  end

  -- Add thinking configuration if enabled
  local thinking_budget = self.parameters.thinking_budget

  if type(thinking_budget) == "number" and thinking_budget >= 1024 then
    request_body.thinking = {
      type = "enabled",
      budget_tokens = math.floor(thinking_budget),
    }
    -- Remove temperature when thinking is enabled (Anthropic API requirement)
    request_body.temperature = nil
    log.debug(
      "anthropic.build_request: Thinking enabled with budget: "
        .. thinking_budget
        .. ". Temperature removed from request."
    )
  elseif thinking_budget == 0 or thinking_budget == nil then
    log.debug("anthropic.build_request: Thinking disabled (budget is " .. tostring(thinking_budget) .. ")")
  else
    log.warn(
      "anthropic.build_request: Invalid thinking_budget value: "
        .. tostring(thinking_budget)
        .. ". Must be nil, 0, or >= 1024. Thinking disabled."
    )
  end

  return request_body
end

---@param self flemma.provider.Anthropic
---@return string[]
function M.get_request_headers(self)
  local api_key = self:get_api_key()

  return {
    "x-api-key: " .. api_key,
    "anthropic-version: " .. self.api_version,
    "content-type: application/json",
  }
end

-- Get API endpoint
--- Process a single line of Anthropic API streaming response
--- Parses Anthropic's server-sent events format and extracts content, usage, and error information
---@param self flemma.provider.Anthropic
---@param line string A single line from the Anthropic API response stream
---@param callbacks flemma.provider.Callbacks Table of callback functions to handle parsed data
function M.process_response_line(self, line, callbacks)
  -- Use base SSE parser
  local parsed = base._parse_sse_line(line)
  if not parsed then
    -- Handle non-SSE lines
    base._handle_non_sse_line(self, line, callbacks)
    return
  end

  -- Handle event lines
  if parsed.type == "event" then
    log.debug("anthropic.process_response_line(): Received event type: " .. parsed.event_type)
    return
  end

  -- Handle [DONE] message (Anthropic doesn't typically send this)
  if parsed.type == "done" then
    log.debug("anthropic.process_response_line(): Received [DONE] message (unexpected)")
    return
  end

  -- Parse JSON data
  local ok, data = pcall(vim.fn.json_decode, parsed.content)
  if not ok then
    log.error("anthropic.process_response_line(): Failed to parse JSON: " .. parsed.content)
    return
  end

  if type(data) ~= "table" then
    log.error("anthropic.process_response_line(): Expected table in response, got type: " .. type(data))
    return
  end

  -- Handle error responses
  if data.type == "error" then
    local msg = self:extract_json_response_error(data) or "Unknown API error"
    log.error("anthropic.process_response_line(): Anthropic API error: " .. log.inspect(msg))
    if callbacks.on_error then
      callbacks.on_error(msg)
    end
    return
  end

  -- Handle ping events
  if data.type == "ping" then
    log.debug("anthropic.process_response_line(): Received ping event")
    return
  end

  -- Track usage information from message_start event
  if data.type == "message_start" then
    log.debug("anthropic.process_response_line(): Received message_start event")
    if data.message and data.message.usage and data.message.usage.input_tokens then
      log.debug(
        "anthropic.process_response_line(): ... Input tokens from message_start: " .. data.message.usage.input_tokens
      )
      if callbacks.on_usage then
        callbacks.on_usage({
          type = "input",
          tokens = data.message.usage.input_tokens,
        })
      end
      -- Parse cache usage tokens from message_start
      local usage = data.message.usage
      if usage.cache_read_input_tokens and callbacks.on_usage then
        callbacks.on_usage({ type = "cache_read", tokens = usage.cache_read_input_tokens })
      end
      if usage.cache_creation_input_tokens and callbacks.on_usage then
        callbacks.on_usage({ type = "cache_creation", tokens = usage.cache_creation_input_tokens })
      end
    else
      log.debug("anthropic.process_response_line(): ... No usage information in message_start event")
    end
  end

  -- Track output tokens from usage field in any event (including message_delta)
  if type(data.usage) == "table" and data.usage.output_tokens then
    log.debug("anthropic.process_response_line(): ... Output tokens update: " .. data.usage.output_tokens)
    if callbacks.on_usage then
      callbacks.on_usage({
        type = "output",
        tokens = data.usage.output_tokens,
      })
    end
  end

  -- Handle message_delta event (mostly for logging the event type now)
  if data.type == "message_delta" then
    log.debug("anthropic.process_response_line(): Received message_delta event")
    -- Usage is handled above
  end

  -- Handle message_stop event
  if data.type == "message_stop" then
    log.debug("anthropic.process_response_line(): Received message_stop event")

    -- Append accumulated thinking at the end (after text content)
    local accumulated = self._response_buffer.extra.accumulated_thinking
    local signature = self._response_buffer.extra.accumulated_signature or ""

    if accumulated and #accumulated > 0 then
      local stripped = vim.trim(accumulated)
      -- Use single newline prefix if content already ends with newline, else double
      local prefix = self:_content_ends_with_newline() and "\n" or "\n\n"
      local open_tag
      if #signature > 0 then
        open_tag = '<thinking anthropic:signature="' .. signature .. '">'
      else
        open_tag = "<thinking>"
      end
      local thinking_block = prefix .. open_tag .. "\n" .. stripped .. "\n</thinking>\n"
      base._signal_content(self, thinking_block, callbacks)
      log.debug("anthropic.process_response_line(): Appended thinking block at end of response")
    elseif #signature > 0 then
      -- Signature but no thinking content — emit open/close tag (enables folding)
      local prefix = self:_content_ends_with_newline() and "\n" or "\n\n"
      local tag = prefix .. '<thinking anthropic:signature="' .. signature .. '">\n</thinking>\n'
      base._signal_content(self, tag, callbacks)
      log.debug("anthropic.process_response_line(): Appended empty thinking tag with signature")
    end

    -- Append redacted thinking blocks
    for _, redacted_data in ipairs(self._response_buffer.extra.redacted_thinking_blocks or {}) do
      local prefix = self:_content_ends_with_newline() and "" or "\n"
      local block = prefix .. "<thinking redacted>\n" .. redacted_data .. "\n</thinking>\n"
      base._signal_content(self, block, callbacks)
      log.debug("anthropic.process_response_line(): Appended redacted thinking block")
    end

    -- Reset accumulated state
    self._response_buffer.extra.accumulated_thinking = ""
    self._response_buffer.extra.accumulated_signature = ""
    self._response_buffer.extra.redacted_thinking_blocks = {}

    if callbacks.on_response_complete then
      callbacks.on_response_complete()
    end
  end

  -- Handle content_block_start event
  if data.type == "content_block_start" then
    log.debug(
      "anthropic.process_response_line(): Received content_block_start event for index " .. tostring(data.index)
    )
    if data.content_block and data.content_block.type then
      self._response_buffer.extra.current_block_type = data.content_block.type
      log.debug("anthropic.process_response_line(): Started block type: " .. data.content_block.type)

      -- Track redacted_thinking block
      if data.content_block.type == "redacted_thinking" then
        if not self._response_buffer.extra.redacted_thinking_blocks then
          self._response_buffer.extra.redacted_thinking_blocks = {}
        end
        table.insert(self._response_buffer.extra.redacted_thinking_blocks, data.content_block.data or "")
        log.debug("anthropic.process_response_line(): Captured redacted_thinking block")
      end

      -- Track tool_use block
      if data.content_block.type == "tool_use" then
        self._response_buffer.extra.current_tool_use = {
          id = data.content_block.id,
          name = data.content_block.name,
        }
        self._response_buffer.extra.accumulated_tool_input = ""
        log.debug(
          "anthropic.process_response_line(): Started tool_use block: "
            .. data.content_block.name
            .. " ("
            .. data.content_block.id
            .. ")"
        )
      end
    end
  end

  -- Handle content_block_stop event
  if data.type == "content_block_stop" then
    log.debug("anthropic.process_response_line(): Received content_block_stop event for index " .. tostring(data.index))

    -- Emit formatted tool_use block
    local current_tool = self._response_buffer.extra.current_tool_use
    if current_tool then
      local input_json = self._response_buffer.extra.accumulated_tool_input or ""
      local parse_ok, input = pcall(vim.fn.json_decode, input_json)
      if not parse_ok then
        input = {}
        log.warn("anthropic.process_response_line(): Failed to parse tool input JSON: " .. input_json)
      end

      -- Pretty-print JSON for display
      local json_str = vim.fn.json_encode(input)

      -- Determine fence length based on content (dynamic fence sizing)
      local max_ticks = 0
      for ticks in json_str:gmatch("`+") do
        max_ticks = math.max(max_ticks, #ticks)
      end
      local fence = string.rep("`", math.max(3, max_ticks + 1))

      -- Format for buffer display
      -- Use appropriate prefix based on what's already accumulated
      local prefix = ""
      if self:_has_content() then
        prefix = self:_content_ends_with_newline() and "\n" or "\n\n"
      end
      local formatted = string.format(
        "%s**Tool Use:** `%s` (`%s`)\n\n%sjson\n%s\n%s\n",
        prefix,
        current_tool.name,
        current_tool.id,
        fence,
        json_str,
        fence
      )

      base._signal_content(self, formatted, callbacks)
      log.debug("anthropic.process_response_line(): Emitted tool_use block for " .. current_tool.name)

      -- Reset tool state
      self._response_buffer.extra.current_tool_use = nil
      self._response_buffer.extra.accumulated_tool_input = ""
    end

    -- Reset block type tracker; thinking is emitted at message_stop
    self._response_buffer.extra.current_block_type = nil
  end

  -- Handle content_block_delta event
  if data.type == "content_block_delta" then
    if not data.delta then
      log.error("anthropic.process_response_line(): Received content_block_delta without delta: " .. log.inspect(data))
      return
    end

    if data.delta.type == "text_delta" and data.delta.text then
      log.debug("anthropic.process_response_line(): Content text delta: " .. log.inspect(data.delta.text))
      base._signal_content(self, data.delta.text, callbacks)
    elseif data.delta.type == "input_json_delta" and data.delta.partial_json ~= nil then
      log.debug("anthropic.process_response_line(): Content input_json_delta: " .. log.inspect(data.delta.partial_json))
      -- Accumulate tool input JSON
      self._response_buffer.extra.accumulated_tool_input = (self._response_buffer.extra.accumulated_tool_input or "")
        .. data.delta.partial_json
    elseif data.delta.type == "thinking_delta" and data.delta.thinking then
      log.debug("anthropic.process_response_line(): Content thinking delta: " .. log.inspect(data.delta.thinking))
      self._response_buffer.extra.accumulated_thinking = (self._response_buffer.extra.accumulated_thinking or "")
        .. data.delta.thinking
    elseif data.delta.type == "signature_delta" and data.delta.signature then
      self._response_buffer.extra.accumulated_signature = (self._response_buffer.extra.accumulated_signature or "")
        .. data.delta.signature
      log.debug("anthropic.process_response_line(): Content signature delta received")
    else
      log.error("anthropic.process_response_line(): Unknown delta type: " .. log.inspect(data.delta.type))
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
    log.error("anthropic.process_response_line(): Unknown event type: " .. log.inspect(data.type))
  end
end

---@param content string
---@return string
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

---@param lines string[]
---@return string
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

---@param content string|table
---@return string
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

---@param data table<string, any>
---@return string
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
function M.try_import_from_buffer(self, lines) ---@diagnostic disable-line: unused-local
  -- Extract and prepare content
  local content = import_extract_content(lines)
  if #content == 0 then
    vim.notify("No Anthropic API call found in buffer", vim.log.levels.ERROR)
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
