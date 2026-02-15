--- OpenAI provider for Flemma
--- Implements the OpenAI Responses API integration
local base = require("flemma.provider.base")
local log = require("flemma.logging")
local models = require("flemma.models")

---@class flemma.provider.OpenAI : flemma.provider.Base
local M = {}

-- Inherit from base provider
setmetatable(M, { __index = base })

-- Known informational events that require no action.
-- Handled as explicit no-ops to suppress debug logging noise.
-- stylua: ignore
local NOOP_EVENTS = {
  ["response.created"]                      = true, -- response object created
  ["response.in_progress"]                  = true, -- response processing started
  ["response.content_part.added"]           = true, -- content part started; we accumulate via text.delta
  ["response.content_part.done"]            = true, -- content part finished; final text in response.completed
  ["response.output_text.done"]             = true, -- final text for output; redundant with accumulated deltas
  ["response.function_call_arguments.delta"] = true, -- incremental args; final args come via output_item.done
  ["response.function_call_arguments.done"] = true, -- final args; redundant with output_item.done
  ["response.reasoning_summary_part.added"] = true, -- reasoning summary part started
  ["response.reasoning_summary_part.done"]  = true, -- reasoning summary part finished
  ["response.reasoning_summary_text.done"]  = true, -- final reasoning summary; redundant with accumulated deltas
}

---@type flemma.provider.Metadata
M.metadata = {
  name = "openai",
  display_name = "OpenAI",
  capabilities = {
    supports_reasoning = true,
    supports_thinking_budget = false,
    outputs_thinking = true,
    output_has_thoughts = true,
  },
  default_parameters = {
    reasoning_summary = "auto",
  },
}

---@param merged_config flemma.provider.Parameters
---@return flemma.provider.OpenAI
function M.new(merged_config)
  local provider = base.new(merged_config) -- Pass the already merged config to base

  -- OpenAI Responses API endpoint
  provider.endpoint = "https://api.openai.com/v1/responses"

  -- Set metatable BEFORE reset so M.reset (not base.reset) initializes provider-specific state
  setmetatable(provider, { __index = setmetatable(M, { __index = base }) })
  provider:reset()

  return provider --[[@as flemma.provider.OpenAI]]
end

---@param self flemma.provider.OpenAI
function M.reset(self)
  base.reset(self)
  self._response_buffer.extra.tool_calls = {}
  self._response_buffer.extra.accumulated_reasoning_summary = ""
  self._response_buffer.extra.reasoning_item = nil
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
    -- Responses API uses "developer" role (replaces Chat Completions "system" role)
    local system_role = "developer"
    table.insert(input_items, {
      role = system_role,
      content = prompt.system,
    })
  end

  local msg_index = 0
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
      -- Two-pass approach: reasoning items must precede text/function_calls (API requirement)
      msg_index = msg_index + 1

      -- First pass: reconstruct reasoning items from thinking blocks with signatures
      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "thinking" and p.signature and p.signature.provider == "openai" then
          local json_str = vim.base64.decode(p.signature.value)
          local decode_ok, reasoning_item = pcall(vim.fn.json_decode, json_str)
          if decode_ok and type(reasoning_item) == "table" then
            table.insert(input_items, reasoning_item)
            log.debug("openai.build_request: Added reasoning item from thinking block signature")
          end
        end
      end

      -- Second pass: collect text and tool_use
      local text_parts = {}
      local item_index = 0

      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "text" then
          table.insert(text_parts, p.text or "")
        elseif p.kind == "thinking" then
          -- Already handled in first pass
        elseif p.kind == "tool_use" then
          -- Flush any accumulated text before the tool call
          if #text_parts > 0 then
            local text = table.concat(text_parts, "")
            if #text > 0 then
              item_index = item_index + 1
              table.insert(input_items, {
                type = "message",
                role = "assistant",
                id = "msg_" .. tostring(msg_index) .. "_" .. tostring(item_index),
                content = { { type = "output_text", text = text, annotations = {} } },
                status = "completed",
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
            status = "completed",
          })
          log.debug("openai.build_request: Added function_call for " .. p.name .. " (" .. normalized_id .. ")")
        end
      end

      -- Flush remaining text
      if #text_parts > 0 then
        local text = table.concat(text_parts, "")
        if #text > 0 then
          item_index = item_index + 1
          table.insert(input_items, {
            type = "message",
            role = "assistant",
            id = "msg_" .. tostring(msg_index) .. "_" .. tostring(item_index),
            content = { { type = "output_text", text = text, annotations = {} } },
            status = "completed",
          })
        end
      end
    end
  end

  -- Inject synthetic error results for orphaned tool calls
  local pending = prompt.pending_tool_calls
  if pending and #pending > 0 then
    for _, orphan in ipairs(pending) do
      table.insert(input_items, {
        type = "function_call_output",
        call_id = base.normalize_tool_id(orphan.id),
        output = "Error: No result provided",
      })
      log.debug(
        "openai.build_request: Injected synthetic function_call_output for orphaned "
          .. orphan.name
          .. " ("
          .. orphan.id
          .. ")"
      )
    end
  end

  -- Build tools array from registry (OpenAI format, filtered by per-buffer opts if present)
  local tools_module = require("flemma.tools")
  local all_tools = tools_module.get_for_prompt(prompt.opts)
  local tools_array = {}

  for _, definition in pairs(all_tools) do
    local tool_entry = {
      type = "function",
      name = definition.name,
      description = tools_module.build_description(definition),
      parameters = definition.input_schema,
    }
    if definition.strict == true then
      tool_entry.strict = true
    end
    table.insert(tools_array, tool_entry)
  end

  -- Sort for deterministic ordering (improves prompt caching hit rates)
  table.sort(tools_array, function(a, b)
    return a.name < b.name
  end)

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

  -- Add reasoning configuration using unified resolution
  local thinking = base.resolve_thinking(self.parameters, M.metadata.capabilities)

  if thinking.enabled and thinking.effort then
    local reasoning_summary = self.parameters.reasoning_summary or "auto"
    request_body.reasoning = {
      effort = thinking.effort,
      summary = reasoning_summary,
    }
    request_body.include = { "reasoning.encrypted_content" }
    log.debug(
      "openai.build_request: Using max_output_tokens: "
        .. tostring(self.parameters.max_tokens)
        .. " and reasoning.effort: "
        .. thinking.effort
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

---Emit accumulated reasoning as a thinking block (called at response completion)
---@param self flemma.provider.OpenAI
---@param callbacks flemma.provider.Callbacks
function M._emit_reasoning_block(self, callbacks)
  local reasoning_item = self._response_buffer.extra.reasoning_item
  if not reasoning_item then
    return
  end

  local summary = self._response_buffer.extra.accumulated_reasoning_summary or ""
  local stripped = vim.trim(summary)

  -- Serialize the full reasoning item as base64 for the signature attribute
  local signature = vim.base64.encode(vim.fn.json_encode(reasoning_item))

  local prefix = self:_content_ends_with_newline() and "\n" or "\n\n"
  if #stripped > 0 then
    local thinking_block = prefix
      .. '<thinking openai:signature="'
      .. signature
      .. '">\n'
      .. stripped
      .. "\n</thinking>\n"
    base._signal_content(self, thinking_block, callbacks)
  else
    -- Signature but no visible summary — emit open/close tag (enables folding)
    local tag = prefix .. '<thinking openai:signature="' .. signature .. '">\n</thinking>\n'
    base._signal_content(self, tag, callbacks)
  end
  log.debug("openai._emit_reasoning_block(): Emitted thinking block")
end

---Extract usage data from a response.completed or response.incomplete event
---@param self flemma.provider.OpenAI
---@param data table<string, any>
---@param callbacks flemma.provider.Callbacks
function M._extract_usage(self, data, callbacks)
  if not (data.response and data.response.usage and type(data.response.usage) == "table") then
    return
  end

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
    log.debug("openai._extract_usage(): Cached input tokens: " .. tostring(cached_tokens))
  end
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

  -- Handle output item start (function_call or reasoning)
  if event_type == "response.output_item.added" then
    if data.item and data.item.type == "function_call" then
      self._response_buffer.extra.tool_calls[data.output_index] = {
        name = data.item.name or "",
        call_id = data.item.call_id or "",
      }
      log.debug(
        "openai.process_response_line(): Started function_call: "
          .. (data.item.name or "")
          .. " ("
          .. (data.item.call_id or "")
          .. ")"
      )
    elseif data.item and data.item.type == "reasoning" then
      self._response_buffer.extra.accumulated_reasoning_summary = ""
      log.debug("openai.process_response_line(): Reasoning item started")
    end
    return
  end

  -- Handle function call completion
  if event_type == "response.output_item.done" then
    if data.item and data.item.type == "function_call" then
      -- Preserve the original JSON string from the API to avoid decode/re-encode
      -- roundtrips that alter formatting and hurt prompt caching hit rates.
      local arguments_json = data.item.arguments or ""
      local parse_ok, _ = pcall(vim.fn.json_decode, arguments_json)
      if not parse_ok then
        log.warn("openai.process_response_line(): Failed to parse tool arguments JSON: " .. arguments_json)
        arguments_json = "{}"
      end

      local max_ticks = 0
      for ticks in arguments_json:gmatch("`+") do
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
        arguments_json,
        fence
      )

      base._signal_content(self, formatted, callbacks)
      log.debug("openai.process_response_line(): Emitted tool_use block for " .. (data.item.name or ""))

      -- Reset tool state for this output index
      self._response_buffer.extra.tool_calls[data.output_index] = nil
    elseif data.item and data.item.type == "reasoning" then
      -- Store the full reasoning item for signature (includes encrypted_content)
      self._response_buffer.extra.reasoning_item = data.item
      log.debug("openai.process_response_line(): Reasoning item completed")
    end
    return
  end

  -- Handle reasoning summary text deltas
  if event_type == "response.reasoning_summary_text.delta" then
    if data.delta then
      self._response_buffer.extra.accumulated_reasoning_summary = (
        self._response_buffer.extra.accumulated_reasoning_summary or ""
      ) .. data.delta
      if callbacks.on_thinking then
        callbacks.on_thinking(data.delta)
      end
    end
    return
  end

  -- Handle response completion with usage
  if event_type == "response.completed" then
    log.debug("openai.process_response_line(): Response completed")

    -- Emit any accumulated reasoning as a thinking block
    self:_emit_reasoning_block(callbacks)

    self:_extract_usage(data, callbacks)
    if callbacks.on_response_complete then
      callbacks.on_response_complete()
    end
    return
  end

  -- Handle incomplete response (truncation due to max_output_tokens, etc.)
  if event_type == "response.incomplete" then
    log.warn("openai.process_response_line(): Response incomplete")

    local reason = data.response and data.response.incomplete_details and data.response.incomplete_details.reason
      or "unknown"
    vim.notify(
      "Flemma: OpenAI response was truncated (reason: " .. reason .. ")",
      vim.log.levels.WARN,
      { title = "Flemma" }
    )
    -- Emit any accumulated reasoning before completing
    self:_emit_reasoning_block(callbacks)

    self:_extract_usage(data, callbacks)
    if callbacks.on_response_complete then
      callbacks.on_response_complete()
    end
    return
  end

  -- Handle top-level stream error event (distinct from response.failed)
  if event_type == "error" then
    local error_message = "OpenAI stream error"
    if data.code then
      error_message = error_message .. " (code: " .. tostring(data.code) .. ")"
    end
    if data.message then
      error_message = error_message .. ": " .. data.message
    end
    log.error("openai.process_response_line(): " .. error_message)
    if callbacks.on_error then
      callbacks.on_error(error_message)
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

  -- Suppress known informational events that we intentionally don't act on
  if NOOP_EVENTS[event_type] then
    return
  end

  -- Truly unknown events get logged for debugging
  log.debug("openai.process_response_line(): Ignoring unknown event type: " .. event_type)
end

---Validate provider-specific parameters
---@param model_name string The model name
---@param parameters table<string, any> The parameters to validate
---@return boolean success True if validation passes (warnings don't fail)
function M.validate_parameters(model_name, parameters)
  -- Resolve effective reasoning: provider-specific `reasoning` > unified `thinking`
  local reasoning_value = parameters.reasoning
  if (reasoning_value == nil or reasoning_value == "") and parameters.thinking ~= nil then
    local thinking = parameters.thinking
    if thinking ~= false and thinking ~= 0 then
      reasoning_value = type(thinking) == "string" and thinking or "medium"
    end
  end

  -- Check for reasoning parameter support
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
