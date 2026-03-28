--- OpenAI provider for Flemma
--- Implements the OpenAI Responses API integration
local base = require("flemma.provider.base")
local json = require("flemma.utilities.json")
local log = require("flemma.logging")
local models = require("flemma.models")
local normalize = require("flemma.provider.normalize")
local s = require("flemma.schema")
local sink = require("flemma.sink")
local tools_module = require("flemma.tools")
local provider_registry = require("flemma.provider.registry")

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
  config_schema = s.object({
    reasoning_summary = s.optional(s.string("auto")),
    reasoning = s.optional(s.string()),
  }),
}

---@param params flemma.provider.Parameters
---@return flemma.provider.OpenAI
function M.new(params)
  local self = setmetatable({
    parameters = params or {},
    state = {},
    endpoint = "https://api.openai.com/v1/responses",
  }, { __index = setmetatable(M, { __index = base }) })
  self:_new_response_buffer()
  self._response_buffer.extra.tool_calls = {}
  self._response_buffer.extra.reasoning_sink = sink.create({
    name = "openai/reasoning",
  })
  self._response_buffer.extra.reasoning_item = nil
  return self --[[@as flemma.provider.OpenAI]]
end

---@param _self flemma.provider.OpenAI
---@return flemma.secrets.Credential
function M.get_credential(_self)
  return { kind = "api_key", service = "openai", description = "OpenAI API key" }
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
          local decode_ok, reasoning_item = pcall(json.decode, json_str)
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
            local text = vim.trim(table.concat(text_parts, ""))
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
            arguments = json.encode(p.input),
            status = "completed",
          })
          log.debug("openai.build_request: Added function_call for " .. p.name .. " (" .. normalized_id .. ")")
        end
      end

      -- Flush remaining text
      if #text_parts > 0 then
        local text = vim.trim(table.concat(text_parts, ""))
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
  local orphan_results = base._inject_orphan_results(self, prompt.pending_tool_calls, function(orphan)
    return {
      type = "function_call_output",
      call_id = base.normalize_tool_id(orphan.id),
      output = "Error: No result provided",
    }
  end)
  if orphan_results then
    for _, result in ipairs(orphan_results) do
      table.insert(input_items, result)
    end
  end

  -- Build tools array from registry (OpenAI format, filtered by per-buffer opts if present)
  local sorted_tools = tools_module.get_sorted_for_prompt(prompt.bufnr)
  local tools_array = {}

  for _, definition in ipairs(sorted_tools) do
    local tool_entry = {
      type = "function",
      name = definition.name,
      description = tools_module.build_description(definition),
      parameters = tools_module.to_json_schema(definition),
    }
    if definition.strict == true then
      tool_entry.strict = true
    end
    table.insert(tools_array, tool_entry)
  end

  local request_body = {
    model = self.parameters.model,
    input = input_items,
    stream = true,
    store = false,
    max_output_tokens = self.parameters.max_tokens,
    temperature = self.parameters.temperature,
  }

  -- Add tools if any are registered
  if #tools_array > 0 then
    request_body.tools = tools_array
    request_body.tool_choice = "auto"
    log.debug("openai.build_request: Added " .. #tools_array .. " tools to request")
  end

  -- Add reasoning configuration using unified resolution
  local model_info = provider_registry.get_model_info("openai", self.parameters.model)
  local thinking = normalize.resolve_thinking(self.parameters, M.metadata.capabilities, model_info)

  if thinking.enabled and thinking.effort then
    -- effort is already mapped to provider API value by resolve_thinking via thinking_effort_map
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

--- Trailing keys for cache-friendly JSON serialization.
--- OpenAI uses `input` (Responses API) as its messages array.
---@param self flemma.provider.OpenAI
---@return string[]
function M.get_trailing_keys(self)
  return { "tools", "input" }
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

--- Emit accumulated reasoning as a thinking block using base helper.
--- Called at response completion and incomplete events.
---@param self flemma.provider.OpenAI
---@param callbacks flemma.provider.Callbacks
local function emit_reasoning(self, callbacks)
  local reasoning_item = self._response_buffer.extra.reasoning_item
  if reasoning_item then
    local summary = self._response_buffer.extra.reasoning_sink:read()
    local signature = vim.base64.encode(json.encode(reasoning_item))
    base._emit_thinking_block(self, summary, signature, "openai", callbacks)
  end
end

--- Process parsed SSE data for OpenAI Responses API events.
--- Dispatches on data.type to handle content deltas, tool calls, reasoning,
--- usage, completion, and error events.
---@param self flemma.provider.OpenAI
---@param data table Parsed JSON event data
---@param _parsed flemma.provider.SSELine SSE line metadata (unused by OpenAI)
---@param callbacks flemma.provider.Callbacks Table of callback functions to handle parsed data
function M._process_data(self, data, _parsed, callbacks)
  local event_type = data.type

  if not event_type then
    log.trace("openai._process_data(): Data without type field, skipping")
    return
  end

  -- Handle text content deltas
  if event_type == "response.output_text.delta" then
    if data.delta then
      log.trace("openai._process_data(): Text delta: " .. log.inspect(data.delta))
      base._signal_content(self, data.delta, callbacks)
    end
    return
  end

  -- Handle incremental function call argument deltas (progress tracking only;
  -- the final args arrive via output_item.done which is the source of truth)
  if event_type == "response.function_call_arguments.delta" then
    if data.delta and callbacks.on_tool_input then
      callbacks.on_tool_input(data.delta)
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
        "openai._process_data(): Started function_call: "
          .. (data.item.name or "")
          .. " ("
          .. (data.item.call_id or "")
          .. ")"
      )
    elseif data.item and data.item.type == "reasoning" then
      self._response_buffer.extra.reasoning_sink:destroy()
      self._response_buffer.extra.reasoning_sink = sink.create({
        name = "openai/reasoning",
      })
      log.debug("openai._process_data(): Reasoning item started")
    end
    return
  end

  -- Handle function call completion
  if event_type == "response.output_item.done" then
    if data.item and data.item.type == "function_call" then
      -- Preserve the original JSON string from the API to avoid decode/re-encode
      -- roundtrips that alter formatting and hurt prompt caching hit rates.
      local arguments_json = data.item.arguments or ""
      local parse_ok, _ = pcall(json.decode, arguments_json)
      if not parse_ok then
        log.warn("openai._process_data(): Failed to parse tool arguments JSON: " .. arguments_json)
        arguments_json = "{}"
      end

      base._emit_tool_use_block(self, data.item.name or "", data.item.call_id or "", arguments_json, callbacks)

      -- Reset tool state for this output index
      self._response_buffer.extra.tool_calls[data.output_index] = nil
    elseif data.item and data.item.type == "reasoning" then
      -- Store the full reasoning item for signature (includes encrypted_content)
      self._response_buffer.extra.reasoning_item = data.item
      log.debug("openai._process_data(): Reasoning item completed")
    end
    return
  end

  -- Handle reasoning summary text deltas
  if event_type == "response.reasoning_summary_text.delta" then
    if data.delta then
      self._response_buffer.extra.reasoning_sink:write(data.delta)
      if callbacks.on_thinking then
        callbacks.on_thinking(data.delta)
      end
    end
    return
  end

  -- Handle response completion with usage
  if event_type == "response.completed" then
    log.debug("openai._process_data(): Response completed")

    -- Emit any accumulated reasoning as a thinking block
    emit_reasoning(self, callbacks)

    self:_extract_usage(data, callbacks)
    if callbacks.on_response_complete then
      callbacks.on_response_complete()
    end
    return
  end

  -- Handle incomplete response (truncation due to max_output_tokens, etc.)
  if event_type == "response.incomplete" then
    log.warn("openai._process_data(): Response incomplete")

    local reason = data.response and data.response.incomplete_details and data.response.incomplete_details.reason
      or "unknown"
    vim.notify("Flemma: OpenAI response was truncated (reason: " .. reason .. ")", vim.log.levels.WARN)
    -- Emit any accumulated reasoning before completing
    emit_reasoning(self, callbacks)

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
    log.error("openai._process_data(): " .. error_message)
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
    log.error("openai._process_data(): " .. error_message)
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
  log.warn("openai._process_data(): Ignoring unknown event type: " .. event_type)
end

---Validate provider-specific parameters
---@param model_name string The model name
---@param parameters table<string, any> The parameters to validate
---@return boolean success Always true (warnings don't fail validation)
---@return string[]|nil warnings Human-readable warning strings, or nil when clean
function M.validate_parameters(model_name, parameters)
  local warnings = {}

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
      table.insert(
        warnings,
        string.format("'reasoning' is not supported by '%s' and may be ignored or cause an API error", model_name)
      )
    end
  end

  if #warnings > 0 then
    return true, warnings
  end
  return true
end

return M
