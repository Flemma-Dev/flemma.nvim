--- Anthropic provider for Flemma
--- Implements the Anthropic (Claude) API integration
local base = require("flemma.provider.base")
local json = require("flemma.utilities.json")
local log = require("flemma.logging")
local normalize = require("flemma.provider.normalize")
local s = require("flemma.config.schema")
local sink = require("flemma.sink")
local tools_module = require("flemma.tools")
local provider_registry = require("flemma.provider.registry")

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
    output_has_thoughts = true,
    min_thinking_budget = 1024,
  },
  config_schema = s.object({
    thinking_budget = s.optional(s.integer()),
  }),
}

---@param params flemma.provider.Parameters
---@return flemma.provider.Anthropic
function M.new(params)
  local self = setmetatable({
    parameters = params or {},
    state = {},
    endpoint = "https://api.anthropic.com/v1/messages",
    api_version = "2023-06-01",
  }, { __index = setmetatable(M, { __index = base }) })
  self:_new_response_buffer()
  self._response_buffer.extra.thinking_sink = sink.create({
    name = "anthropic/thinking",
  })
  self._response_buffer.extra.accumulated_signature = ""
  self._response_buffer.extra.redacted_thinking_blocks = {}
  self._response_buffer.extra.current_block_type = nil
  self._response_buffer.extra.current_tool_use = nil
  self._response_buffer.extra.tool_input_sink = sink.create({
    name = "anthropic/tool-input",
  })
  return self --[[@as flemma.provider.Anthropic]]
end

---@param _self flemma.provider.Anthropic
---@return flemma.secrets.Credential
function M.get_credential(_self)
  return { kind = "api_key", service = "anthropic", description = "Anthropic API key" }
end

--- Anthropic uses `data.type == "error"` for errors (not `data.error`).
---@param self flemma.provider.Anthropic
---@param data table
---@return boolean
function M._is_error_response(self, data)
  return data.type == "error"
end

---Build request body for Anthropic API
---
---@param prompt flemma.provider.Prompt The prepared prompt with history and system (from pipeline)
---@param _context? flemma.Context The shared context object (not used, parts already resolved)
---@return table<string, any> request_body The request body for the API
function M.build_request(self, prompt, _context)
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

  -- Inject synthetic error results for orphaned tool calls
  local orphan_results = base._inject_orphan_results(self, prompt.pending_tool_calls, function(orphan)
    return {
      type = "tool_result",
      tool_use_id = base.normalize_tool_id(orphan.id),
      content = "No result provided",
      is_error = true,
    }
  end)
  if orphan_results then
    table.insert(api_messages, { role = "user", content = orphan_results })
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
  local sorted_tools = tools_module.get_sorted_for_prompt(prompt.bufnr)
  local tools_array = {}
  for _, def in ipairs(sorted_tools) do
    table.insert(tools_array, {
      name = def.name,
      description = tools_module.build_description(def),
      input_schema = def.input_schema,
    })
  end

  -- Breakpoint 1: last tool definition
  if cache_control and #tools_array > 0 then
    tools_array[#tools_array].cache_control = cache_control
  end

  local request_body = {
    model = self.parameters.model,
    messages = api_messages,
    max_tokens = self.parameters.max_tokens,
    temperature = self.parameters.temperature,
    stream = true,
  }

  -- Auto-caching: top-level cache_control auto-advances a breakpoint to the last
  -- cacheable block (the conversation tail). Combined with the explicit breakpoints on
  -- tools and system prompt above, this gives a 3-breakpoint hybrid: stable prefixes are
  -- cached independently while the conversation tail is tracked automatically.
  if cache_control then
    request_body.cache_control = cache_control
  end

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

  -- Add thinking configuration using unified resolution
  local model_info = provider_registry.get_model_info("anthropic", self.parameters.model)
  local thinking = normalize.resolve_thinking(self.parameters, M.metadata.capabilities, model_info)

  if thinking.enabled then
    local is_adaptive = model_info and model_info.supports_adaptive_thinking

    if is_adaptive then
      -- 4.6+ adaptive thinking: effort from resolve_thinking's mapped_effort
      local effort = thinking.mapped_effort or "high"
      request_body.thinking = { type = "adaptive" }
      request_body.output_config = { effort = effort }
      log.debug("anthropic.build_request: Adaptive thinking enabled with effort: " .. effort)
    elseif thinking.budget and thinking.mapped_effort then
      -- Opus 4.5: budget-based thinking with effort parameter alongside
      request_body.thinking = { type = "enabled", budget_tokens = thinking.budget }
      request_body.output_config = { effort = thinking.mapped_effort }
      log.debug(
        "anthropic.build_request: Budget thinking with effort: "
          .. thinking.mapped_effort
          .. ", budget: "
          .. thinking.budget
      )
    elseif thinking.budget then
      local budget = thinking.budget
      local max_tokens = self.parameters.max_tokens
      if budget >= max_tokens then
        budget = max_tokens - 1
        local min_budget = M.metadata.capabilities.min_thinking_budget or 1024
        if budget < min_budget then
          budget = min_budget
          log.debug("anthropic.build_request: max_tokens too low for thinking budget, clamped to min")
        end
        log.debug(
          "anthropic.build_request: Clamped budget_tokens to "
            .. budget
            .. " (must be < max_tokens "
            .. max_tokens
            .. ")"
        )
      end
      request_body.thinking = {
        type = "enabled",
        budget_tokens = budget,
      }
      log.debug("anthropic.build_request: Thinking enabled with budget: " .. budget)
    end
    -- Remove temperature when thinking is enabled (Anthropic API requirement)
    request_body.temperature = nil
  else
    log.debug("anthropic.build_request: Thinking disabled")
  end

  return request_body
end

--- Trailing keys for cache-friendly JSON serialization.
--- Static config keys are sorted alphabetically first; system, tools, and messages
--- trail because messages grow each turn (and tools/system are semi-static).
---@param self flemma.provider.Anthropic
---@return string[]
function M.get_trailing_keys(self)
  return { "system", "tools", "messages" }
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

--- Process parsed SSE data for Anthropic API streaming responses.
--- Called by base.process_response_line() after SSE parsing, JSON decode, and error checks.
---@param self flemma.provider.Anthropic
---@param data table The parsed JSON data from the SSE line
---@param _parsed flemma.provider.SSELine The original parsed SSE line (unused by Anthropic)
---@param callbacks flemma.provider.Callbacks Table of callback functions to handle parsed data
function M._process_data(self, data, _parsed, callbacks)
  -- Handle ping events
  if data.type == "ping" then
    log.trace("anthropic._process_data(): Received ping event")
    return
  end

  -- Track usage information from message_start event
  if data.type == "message_start" then
    log.debug("anthropic._process_data(): Received message_start event")
    if data.message and data.message.usage and data.message.usage.input_tokens then
      log.debug("anthropic._process_data(): ... Input tokens from message_start: " .. data.message.usage.input_tokens)
      if callbacks.on_usage then
        callbacks.on_usage({
          type = "input",
          tokens = data.message.usage.input_tokens,
        })
      end
      -- Parse cache usage tokens from message_start
      local usage = data.message.usage
      if usage.cache_read_input_tokens and callbacks.on_usage then
        log.debug("anthropic._process_data(): ... Cache read input tokens: " .. usage.cache_read_input_tokens)
        callbacks.on_usage({ type = "cache_read", tokens = usage.cache_read_input_tokens })
      end
      if usage.cache_creation_input_tokens and callbacks.on_usage then
        log.debug("anthropic._process_data(): ... Cache creation input tokens: " .. usage.cache_creation_input_tokens)
        callbacks.on_usage({ type = "cache_creation", tokens = usage.cache_creation_input_tokens })
      end
    else
      log.debug("anthropic._process_data(): ... No usage information in message_start event")
    end
  end

  -- Track output tokens from usage field in any event (including message_delta)
  if type(data.usage) == "table" and data.usage.output_tokens then
    log.debug("anthropic._process_data(): ... Output tokens update: " .. data.usage.output_tokens)
    if callbacks.on_usage then
      callbacks.on_usage({
        type = "output",
        tokens = data.usage.output_tokens,
      })
    end
  end

  -- Handle message_delta event — capture stop_reason for completion branching
  if data.type == "message_delta" then
    log.debug("anthropic._process_data(): Received message_delta event")
    if data.delta and data.delta.stop_reason then
      self._response_buffer.extra.stop_reason = data.delta.stop_reason
      log.debug("anthropic._process_data(): Captured stop_reason: " .. data.delta.stop_reason)
    end
  end

  -- Handle message_stop event
  if data.type == "message_stop" then
    log.debug("anthropic._process_data(): Received message_stop event")

    -- Append accumulated thinking at the end (after text content)
    local accumulated = self._response_buffer.extra.thinking_sink:read()
    local signature = self._response_buffer.extra.accumulated_signature or ""
    base._emit_thinking_block(self, accumulated, (#signature > 0) and signature or nil, "anthropic", callbacks)

    -- Append redacted thinking blocks
    for _, redacted_data in ipairs(self._response_buffer.extra.redacted_thinking_blocks or {}) do
      base._emit_redacted_thinking(self, redacted_data, callbacks)
    end

    -- Reset accumulated state
    self._response_buffer.extra.thinking_sink:destroy()
    self._response_buffer.extra.thinking_sink = sink.create({
      name = "anthropic/thinking",
    })
    self._response_buffer.extra.accumulated_signature = ""
    self._response_buffer.extra.redacted_thinking_blocks = {}

    -- Branch on captured stop_reason (from message_delta)
    local stop_reason = self._response_buffer.extra.stop_reason

    if stop_reason == "max_tokens" then
      base._warn_truncated(self, callbacks)
    elseif stop_reason == "refusal" or stop_reason == "sensitive" then
      base._signal_blocked(self, stop_reason, callbacks)
    else
      -- end_turn, tool_use, stop_sequence, pause_turn, nil — normal completion
      if callbacks.on_response_complete then
        callbacks.on_response_complete()
      end
    end
  end

  -- Handle content_block_start event
  if data.type == "content_block_start" then
    log.debug("anthropic._process_data(): Received content_block_start event for index " .. tostring(data.index))
    if data.content_block and data.content_block.type then
      self._response_buffer.extra.current_block_type = data.content_block.type
      log.debug("anthropic._process_data(): Started block type: " .. data.content_block.type)

      -- Track redacted_thinking block
      if data.content_block.type == "redacted_thinking" then
        if not self._response_buffer.extra.redacted_thinking_blocks then
          self._response_buffer.extra.redacted_thinking_blocks = {}
        end
        table.insert(self._response_buffer.extra.redacted_thinking_blocks, data.content_block.data or "")
        log.debug("anthropic._process_data(): Captured redacted_thinking block")
      end

      -- Track tool_use block
      if data.content_block.type == "tool_use" then
        self._response_buffer.extra.current_tool_use = {
          id = data.content_block.id,
          name = data.content_block.name,
        }
        self._response_buffer.extra.tool_input_sink:destroy()
        self._response_buffer.extra.tool_input_sink = sink.create({
          name = "anthropic/tool-input",
        })
        log.debug(
          "anthropic._process_data(): Started tool_use block: "
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
    log.debug("anthropic._process_data(): Received content_block_stop event for index " .. tostring(data.index))

    -- Emit formatted tool_use block
    local current_tool = self._response_buffer.extra.current_tool_use
    if current_tool then
      local input_json = self._response_buffer.extra.tool_input_sink:read()
      local parse_ok, input = pcall(json.decode, input_json)
      if not parse_ok then
        input = {}
        log.warn("anthropic._process_data(): Failed to parse tool input JSON: " .. input_json)
      end

      -- Re-encode for normalized display
      local json_str = json.encode(input)
      base._emit_tool_use_block(self, current_tool.name, current_tool.id, json_str, callbacks)
      log.debug("anthropic._process_data(): Emitted tool_use block for " .. current_tool.name)

      -- Reset tool state
      self._response_buffer.extra.current_tool_use = nil
      self._response_buffer.extra.tool_input_sink:destroy()
      self._response_buffer.extra.tool_input_sink = sink.create({
        name = "anthropic/tool-input",
      })
    end

    -- Reset block type tracker; thinking is emitted at message_stop
    self._response_buffer.extra.current_block_type = nil
  end

  -- Handle content_block_delta event
  if data.type == "content_block_delta" then
    if not data.delta then
      log.error("anthropic._process_data(): Received content_block_delta without delta: " .. log.inspect(data))
      return
    end

    if data.delta.type == "text_delta" and data.delta.text then
      log.trace("anthropic._process_data(): Content text delta: " .. log.inspect(data.delta.text))
      base._signal_content(self, data.delta.text, callbacks)
    elseif data.delta.type == "input_json_delta" and data.delta.partial_json ~= nil then
      log.trace("anthropic._process_data(): Content input_json_delta: " .. log.inspect(data.delta.partial_json))
      -- Accumulate tool input JSON
      self._response_buffer.extra.tool_input_sink:write(data.delta.partial_json)
      -- Notify progress tracking (optional callback, may not be provided)
      if callbacks.on_tool_input then
        callbacks.on_tool_input(data.delta.partial_json)
      end
    elseif data.delta.type == "thinking_delta" and data.delta.thinking then
      log.trace("anthropic._process_data(): Content thinking delta: " .. log.inspect(data.delta.thinking))
      self._response_buffer.extra.thinking_sink:write(data.delta.thinking)
      if callbacks.on_thinking then
        callbacks.on_thinking(data.delta.thinking)
      end
    elseif data.delta.type == "signature_delta" and data.delta.signature then
      self._response_buffer.extra.accumulated_signature = (self._response_buffer.extra.accumulated_signature or "")
        .. data.delta.signature
      log.trace("anthropic._process_data(): Content signature delta received")
    else
      log.warn("anthropic._process_data(): Unknown delta type: " .. log.inspect(data.delta.type))
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
    log.warn("anthropic._process_data(): Unknown event type: " .. log.inspect(data.type))
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
    table.insert(output, "@System:")
    table.insert(output, data.system)
    table.insert(output, "")
  end

  -- Process messages
  for _, msg in ipairs(data.messages or {}) do
    local role_marker = msg.role == "user" and "@You:" or "@Assistant:"
    local text = import_get_message_text(msg.content)

    -- Add blank line before message if needed
    if #output > 0 and output[#output] ~= "" then
      table.insert(output, "")
    end

    table.insert(output, role_marker)
    table.insert(output, text)
  end

  return table.concat(output, "\n")
end

-- Try to import from buffer lines (Claude Workbench format)
---@param lines string[]
---@return string|nil
function M.try_import_from_buffer(lines)
  -- Extract and prepare content
  local content = import_extract_content(lines)
  if #content == 0 then
    vim.notify("No Anthropic API call found in buffer", vim.log.levels.ERROR)
    return nil
  end

  local json_str = import_prepare_json(content)

  -- Parse JSON with better error handling
  local ok, data = pcall(json.decode, json_str)
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
