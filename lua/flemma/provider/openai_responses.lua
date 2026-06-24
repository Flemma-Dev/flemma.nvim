--- OpenAI Responses API intermediate base provider for Flemma
---
--- Implements the shared wire format for OpenAI Responses API.
--- This is an intermediate base class — concrete providers (e.g., OpenAI, Codex)
--- inherit from it and override extension points for provider-specific behavior.
---
--- Metatable chain: concrete_provider -> openai_responses -> base
local base = require("flemma.provider.base")
local json = require("flemma.utilities.json")
local log = require("flemma.logging")
local notify = require("flemma.notify")
local sink = require("flemma.sink")
local tools_module = require("flemma.tools")

---@class flemma.provider.OpenAIResponses : flemma.provider.Base
---@field metadata flemma.provider.Metadata Inherited from concrete subclass via __index chain
local M = {}

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

-- ============================================================================
-- Extension points — concrete providers may override these
-- ============================================================================

--- Pre-build hook called before request construction begins.
--- Default: no-op. OpenAI overrides to initialize phase diagnostics.
---@param self flemma.provider.OpenAIResponses
function M._init_build(self) end

--- Place the system prompt into the request.
--- Default: prepend a developer-role input item.
--- Called after history is built, so uses table.insert(items, 1, ...) to prepend.
---@param self flemma.provider.OpenAIResponses
---@param _body table<string, any> The request body (mutated in place)
---@param input_items table[] The input items array (mutated in place)
---@param system_text string The system prompt text
function M._apply_system(self, _body, input_items, system_text)
  table.insert(input_items, 1, { role = "developer", content = system_text })
end

--- Return the request body key for maximum output tokens.
--- Default is "max_output_tokens" (standard Responses API).
--- Override for backends that use a different key (e.g., Codex uses "max_tokens").
---@param self flemma.provider.OpenAIResponses
---@return string
function M._max_tokens_key(self)
  return "max_output_tokens"
end

--- Apply reasoning configuration to the request body.
--- Default: no-op. Concrete providers override based on model capabilities.
---@param self flemma.provider.OpenAIResponses
---@param _body table<string, any> The request body (mutated in place)
function M._apply_reasoning(self, _body) end

--- Apply provider-specific body fields after core construction.
--- Default: no-op. OpenAI overrides for prompt caching; Codex for store/text.
---@param self flemma.provider.OpenAIResponses
---@param _body table<string, any> The request body (mutated in place)
---@param _context? flemma.Context The shared context object
function M._apply_extra_body(self, _body, _context) end

--- Decorate an assistant message item during request building.
--- Default: no-op. OpenAI overrides to set phase labels and diagnostics.
---@param self flemma.provider.OpenAIResponses
---@param _item table The assistant message item being built
---@param _phase string The resolved phase ("commentary" or "final_answer")
function M._decorate_assistant_item(self, _item, _phase) end

--- Handle a completed output message item from the stream.
--- Default: no-op. OpenAI overrides to record expected phase diagnostics.
---@param self flemma.provider.OpenAIResponses
---@param _item table The completed output item
function M._on_output_message_done(self, _item) end

-- ============================================================================
-- Test helper
-- ============================================================================

--- Create a minimal concrete instance for testing the base class.
--- Avoids the need for a full concrete provider module during unit tests.
---@param opts? {model?: string, max_tokens?: integer, temperature?: number, [string]: any}
---@return flemma.provider.OpenAIResponses
function M._new_concrete(opts)
  local params = opts or {}
  params.model = params.model or "test-model"
  params.max_tokens = params.max_tokens or 4096
  local self = setmetatable({
    parameters = params,
    state = {},
    endpoint = "https://api.example.com/v1/responses",
    metadata = {
      name = "openai_responses_test",
      display_name = "OpenAI Responses Test",
      capabilities = {
        supports_reasoning = false,
        supports_thinking_budget = false,
        outputs_thinking = true,
        output_has_thoughts = true,
      },
    },
  }, { __index = setmetatable(M, { __index = base }) })
  self:_new_response_buffer()
  return self --[[@as flemma.provider.OpenAIResponses]]
end

-- ============================================================================
-- Abstract — still requires concrete providers to implement
-- ============================================================================

-- get_credential and get_request_headers remain abstract from base.
-- Concrete providers MUST implement them.

-- ============================================================================
-- Response buffer setup
-- ============================================================================

--- Override base _new_response_buffer to add Responses API-specific extras.
---@param self flemma.provider.OpenAIResponses
function M._new_response_buffer(self)
  base._new_response_buffer(self)
  self._response_buffer.extra.tool_calls = {}
  self._response_buffer.extra.reasoning_sink = sink.create({
    name = "openai_responses/reasoning",
  })
  self._response_buffer.extra.reasoning_item = nil
end

-- ============================================================================
-- Helpers
-- ============================================================================

---@param msg flemma.provider.HistoryMessage
---@return boolean
local function message_has_tool_use(msg)
  for _, part in ipairs(msg.parts or {}) do
    if part.kind == "tool_use" then
      return true
    end
  end
  return false
end

--- Emit accumulated reasoning as a thinking block using base helper.
--- Called at response completion and incomplete events.
---@param self flemma.provider.OpenAIResponses
---@param callbacks flemma.provider.Callbacks
function M.emit_reasoning(self, callbacks)
  local reasoning_item = self._response_buffer.extra.reasoning_item
  if reasoning_item then
    local summary = self._response_buffer.extra.reasoning_sink:read()
    local signature = vim.base64.encode(json.encode(reasoning_item))
    base._emit_thinking_block(self, summary, signature, callbacks)
  end
end

-- ============================================================================
-- Request building
-- ============================================================================

---Build request body for OpenAI Responses API
---
---@param self flemma.provider.OpenAIResponses
---@param prompt flemma.provider.Prompt The prepared prompt with history and system (from pipeline)
---@param context? flemma.Context The shared context object (used for prompt caching hints)
---@return table<string, any> request_body The request body for the API
function M.build_request(self, prompt, context)
  local input_items = {}

  self:_init_build()

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
            'openai_responses.build_request: Added input_image part for "'
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
            'openai_responses.build_request: Added file part for PDF "'
              .. (part.filename or "document")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "text_file" then
          table.insert(content_parts_for_api, { type = "input_text", text = part.text })
          log.debug(
            'openai_responses.build_request: Added input_text part for "'
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

          -- Map .parts to Responses API format for tool results
          local has_non_text = false
          local output_parts = {}
          for _, rp in ipairs(part.parts or {}) do
            if rp.kind == "text" then
              if rp.text and #rp.text > 0 then
                table.insert(output_parts, { type = "input_text", text = rp.text })
              end
            elseif rp.kind == "image" then
              has_non_text = true
              table.insert(output_parts, {
                type = "input_image",
                image_url = rp.data_url,
                detail = "auto",
              })
            elseif rp.kind == "pdf" then
              has_non_text = true
              table.insert(output_parts, {
                type = "input_file",
                filename = rp.filename or "document.pdf",
                file_data = rp.data_url,
              })
            elseif rp.kind == "text_file" then
              table.insert(output_parts, { type = "input_text", text = rp.text })
            elseif rp.kind == "unsupported_file" then
              table.insert(output_parts, {
                type = "input_text",
                text = "[binary file: " .. (rp.filename or "unknown") .. "]",
              })
            end
          end

          -- When all parts are text, collapse to a plain string
          local result_output
          if not has_non_text then
            local texts = {}
            for _, op in ipairs(output_parts) do
              table.insert(texts, op.text)
            end
            result_output = table.concat(texts, "")
            -- OpenAI doesn't have is_error field; prefix content with "Error: " for text-only results
            if part.is_error then
              result_output = "Error: " .. (result_output ~= "" and result_output or "Tool execution failed")
            end
          else
            -- Mixed content (images, PDFs, etc.): prepend an error text block when is_error
            if part.is_error then
              table.insert(output_parts, 1, { type = "input_text", text = "Error:" })
            end
            result_output = output_parts
          end

          table.insert(tool_results, {
            call_id = normalized_id,
            content = result_output,
          })
          log.debug("openai_responses.build_request: Added tool_result for " .. normalized_id)
        end
      end

      -- Add tool results FIRST as top-level function_call_output items
      -- Tool results must come before any new user content in the same turn
      for _, tr in ipairs(tool_results) do
        table.insert(input_items, {
          type = "function_call_output",
          call_id = tr.call_id,
          output = tr.content,
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
        if p.kind == "thinking" and self:is_native_thinking(p) then
          local json_str = vim.base64.decode(p.signature.value)
          local decode_ok, reasoning_item = pcall(json.decode, json_str)
          if decode_ok and type(reasoning_item) == "table" then
            table.insert(input_items, reasoning_item)
            log.debug("openai_responses.build_request: Added reasoning item from thinking block signature")
          end
        end
      end

      -- Inject foreign thinking as text (between native reasoning and regular text)
      local foreign = self:wrap_foreign_thinking(msg.parts)

      -- Second pass: collect text and tool_use
      local text_parts = {}
      if foreign then
        table.insert(text_parts, foreign)
      end
      local item_index = 0
      local phase = message_has_tool_use(msg) and "commentary" or "final_answer"

      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "text" then
          table.insert(text_parts, p.text or "")
        elseif p.kind == "tool_use" then
          -- Flush any accumulated text before the tool call
          if #text_parts > 0 then
            local text = vim.trim(table.concat(text_parts, ""))
            if #text > 0 then
              item_index = item_index + 1
              local item = {
                type = "message",
                role = "assistant",
                id = "msg_" .. tostring(msg_index) .. "_" .. tostring(item_index),
                content = { { type = "output_text", text = text, annotations = {} } },
                status = "completed",
              }
              self:_decorate_assistant_item(item, phase)
              table.insert(input_items, item)
            end
            text_parts = {}
          end

          -- Normalize tool ID for OpenAI compatibility (handles Vertex URN-style IDs)
          local normalized_id = base.normalize_tool_id(p.id)
          table.insert(input_items, {
            type = "function_call",
            call_id = normalized_id,
            name = base.encode_tool_name(p.name),
            arguments = json.encode(p.input),
            status = "completed",
          })
          log.debug(
            "openai_responses.build_request: Added function_call for " .. p.name .. " (" .. normalized_id .. ")"
          )
        end
      end

      -- Flush remaining text
      if #text_parts > 0 then
        local text = vim.trim(table.concat(text_parts, ""))
        if #text > 0 then
          item_index = item_index + 1
          local item = {
            type = "message",
            role = "assistant",
            id = "msg_" .. tostring(msg_index) .. "_" .. tostring(item_index),
            content = { { type = "output_text", text = text, annotations = {} } },
            status = "completed",
          }
          self:_decorate_assistant_item(item, phase)
          table.insert(input_items, item)
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
      name = base.encode_tool_name(definition.name),
      description = tools_module.build_description(definition),
      parameters = tools_module.to_json_schema_for_prompt(definition),
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
    [self:_max_tokens_key()] = self.parameters.max_tokens,
    temperature = self.parameters.temperature,
  }

  -- Add tools if any are registered
  if #tools_array > 0 then
    request_body.tools = tools_array
    request_body.tool_choice = "auto"
    log.debug("openai_responses.build_request: Added " .. #tools_array .. " tools to request")
  end

  -- Apply system prompt (may insert input item or set body field like instructions)
  if prompt.system and #prompt.system > 0 then
    self:_apply_system(request_body, input_items, prompt.system)
  end

  -- Extension points for provider-specific behavior
  self:_apply_reasoning(request_body)
  self:_apply_extra_body(request_body, context)

  return request_body
end

--- Trailing keys for cache-friendly JSON serialization.
--- OpenAI Responses API uses `input` as its messages array.
---@param self flemma.provider.OpenAIResponses
---@return string[]
function M.get_trailing_keys(self)
  return { "tools", "input" }
end

-- ============================================================================
-- Streaming parser
-- ============================================================================

---Extract usage data from a response.completed or response.incomplete event
---@param self flemma.provider.OpenAIResponses
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
    log.debug("openai_responses._extract_usage(): Cached input tokens: " .. tostring(cached_tokens))
  end
end

--- Process parsed SSE data for OpenAI Responses API events.
--- Dispatches on data.type to handle content deltas, tool calls, reasoning,
--- usage, completion, and error events.
---@param self flemma.provider.OpenAIResponses
---@param data table Parsed JSON event data
---@param _parsed flemma.provider.SSELine SSE line metadata (unused by Responses API)
---@param callbacks flemma.provider.Callbacks Table of callback functions to handle parsed data
function M._process_data(self, data, _parsed, callbacks)
  local event_type = data.type

  if not event_type then
    log.trace("openai_responses._process_data(): Data without type field, skipping")
    return
  end

  -- Handle text content deltas
  if event_type == "response.output_text.delta" then
    if data.delta then
      log.trace("openai_responses._process_data(): Text delta: " .. log.inspect(data.delta))
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
        "openai_responses._process_data(): Started function_call: "
          .. (data.item.name or "")
          .. " ("
          .. (data.item.call_id or "")
          .. ")"
      )
      if callbacks.on_tool_call_start then
        callbacks.on_tool_call_start(data.item.name or "")
      end
    elseif data.item and data.item.type == "reasoning" then
      self._response_buffer.extra.reasoning_sink:destroy()
      self._response_buffer.extra.reasoning_sink = sink.create({
        name = "openai_responses/reasoning",
      })
      log.debug("openai_responses._process_data(): Reasoning item started")
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
        log.warn("openai_responses._process_data(): Failed to parse tool arguments JSON: " .. arguments_json)
        arguments_json = "{}"
      end

      base._emit_tool_use_block(self, data.item.name or "", data.item.call_id or "", arguments_json, callbacks)

      -- Reset tool state for this output index
      self._response_buffer.extra.tool_calls[data.output_index] = nil
    elseif data.item and data.item.type == "reasoning" then
      -- Store the full reasoning item for signature (includes encrypted_content)
      self._response_buffer.extra.reasoning_item = data.item
      log.debug("openai_responses._process_data(): Reasoning item completed")
    elseif data.item and data.item.type == "message" then
      self:_on_output_message_done(data.item)
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
    log.debug("openai_responses._process_data(): Response completed")

    -- Emit any accumulated reasoning as a thinking block
    self:emit_reasoning(callbacks)

    self:_extract_usage(data, callbacks)
    if callbacks.on_response_complete then
      callbacks.on_response_complete()
    end
    return
  end

  -- Handle incomplete response (truncation due to max_output_tokens, etc.)
  if event_type == "response.incomplete" then
    log.warn("openai_responses._process_data(): Response incomplete")

    local reason = data.response and data.response.incomplete_details and data.response.incomplete_details.reason
      or "unknown"
    notify.warn("Response was truncated (reason: " .. reason .. ")")
    -- Emit any accumulated reasoning before completing
    self:emit_reasoning(callbacks)

    self:_extract_usage(data, callbacks)
    if callbacks.on_response_complete then
      callbacks.on_response_complete()
    end
    return
  end

  -- Handle top-level stream error event (distinct from response.failed)
  if event_type == "error" then
    local error_message = "Stream error"
    if data.code then
      error_message = error_message .. " (code: " .. tostring(data.code) .. ")"
    end
    if data.message then
      error_message = error_message .. ": " .. data.message
    end
    log.error("openai_responses._process_data(): " .. error_message)
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
    log.error("openai_responses._process_data(): " .. error_message)
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
  log.warn("openai_responses._process_data(): Ignoring unknown event type: " .. event_type)
end

return M
