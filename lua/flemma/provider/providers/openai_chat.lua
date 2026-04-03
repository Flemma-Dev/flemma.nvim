--- OpenAI Chat Completions intermediate base provider for Flemma
---
--- Implements the shared wire format for OpenAI-compatible Chat Completions APIs.
--- This is an intermediate base class — concrete providers (e.g., Moonshot) inherit
--- from it and override extension points for provider-specific behavior.
---
--- Metatable chain: concrete_provider -> openai_chat -> base
local base = require("flemma.provider.base")
local json = require("flemma.utilities.json")
local log = require("flemma.logging")
local normalize = require("flemma.provider.normalize")
local provider_registry = require("flemma.provider.registry")
local sink = require("flemma.sink")
local tools_module = require("flemma.tools")

---@class flemma.provider.OpenAIChat : flemma.provider.Base
---@field metadata flemma.provider.Metadata Inherited from concrete subclass via __index chain (concrete providers define M.metadata)
local M = {}

-- Inherit from base provider
setmetatable(M, { __index = base })

-- ============================================================================
-- Extension points — concrete providers may override these
-- ============================================================================

--- Return the request body key for maximum output tokens.
--- Default is "max_tokens" (standard Chat Completions).
--- Override for providers that use a different key (e.g., "max_completion_tokens").
---@param self flemma.provider.OpenAIChat
---@return string
function M._max_tokens_key(self)
  return "max_tokens"
end

--- Apply provider-specific thinking/reasoning configuration to the request body.
--- Default is a no-op. Override for providers that support extended thinking
--- (e.g., deep thinking modes that require additional request parameters).
---@param self flemma.provider.OpenAIChat
---@param _body table<string, any> The request body (mutated in place)
---@param _resolution flemma.provider.ThinkingResolution The resolved thinking configuration
function M._apply_thinking(self, _body, _resolution)
  -- No-op by default; concrete providers override as needed
end

--- Apply additional provider-specific parameters to the request body.
--- Called after all standard parameters are set. Override for custom fields
--- that don't fit into standard Chat Completions parameters.
---@param self flemma.provider.OpenAIChat
---@param _body table<string, any> The request body (mutated in place)
---@param _context? flemma.Context The shared context object
function M._apply_provider_params(self, _body, _context)
  -- No-op by default; concrete providers override as needed
end

--- Build an image content part for the Chat Completions messages array.
--- Default returns standard `image_url` format with data URL.
--- Override for providers that use a different image part schema.
---@param self flemma.provider.OpenAIChat
---@param part flemma.ast.GenericImagePart The image part from the canonical prompt
---@return table image_part The provider-specific image content part
function M._build_image_part(self, part)
  return {
    type = "image_url",
    image_url = { url = part.data_url },
  }
end

--- Return the provider prefix for thinking block signatures.
--- Default returns nil (no thinking signature support).
--- Override for providers that support extended thinking with signatures.
---@param self flemma.provider.OpenAIChat
---@return string|nil
function M._thinking_provider_prefix(self)
  return nil
end

-- ============================================================================
-- Test helper
-- ============================================================================

--- Create a minimal concrete instance for testing the base class.
--- Avoids the need for a full concrete provider module during unit tests.
---@param opts? {model?: string, max_tokens?: integer, temperature?: number, [string]: any}
---@return flemma.provider.OpenAIChat
function M._new_concrete(opts)
  local params = opts or {}
  params.model = params.model or "test-model"
  params.max_tokens = params.max_tokens or 4096
  local self = setmetatable({
    parameters = params,
    state = {},
    endpoint = "https://api.example.com/v1/chat/completions",
    metadata = {
      name = "openai_chat_test",
      display_name = "OpenAI Chat Test",
      capabilities = {
        supports_reasoning = false,
        supports_thinking_budget = false,
        outputs_thinking = false,
        output_has_thoughts = false,
      },
    },
  }, { __index = setmetatable(M, { __index = base }) })
  self:_new_response_buffer()
  self._response_buffer.extra.tool_calls = {}
  self._response_buffer.extra.thinking_sink = sink.create({ name = "openai_chat_test/thinking" })
  self._response_buffer.extra.usage_emitted = false
  return self --[[@as flemma.provider.OpenAIChat]]
end

-- ============================================================================
-- Abstract — still requires concrete providers to implement
-- ============================================================================

-- get_credential and get_request_headers remain abstract from base.
-- Concrete providers MUST implement them.

-- ============================================================================
-- Request building
-- ============================================================================

---Build request body for Chat Completions API.
---
---Converts a canonical Prompt into the Chat Completions wire format.
---Extension points allow concrete providers to customize specific aspects
---without reimplementing the entire request builder.
---@param self flemma.provider.OpenAIChat
---@param prompt flemma.provider.Prompt The prepared prompt with history and system
---@param context? flemma.Context The shared context object
---@return table<string, any> request_body The request body for the API
function M.build_request(self, prompt, context)
  local messages = {}

  -- System message
  if prompt.system and #prompt.system > 0 then
    table.insert(messages, {
      role = "system",
      content = prompt.system,
    })
  end

  for _, msg in ipairs(prompt.history) do
    if msg.role == "user" then
      -- Tool results emitted FIRST as separate role="tool" messages
      for _, part in ipairs(msg.parts or {}) do
        if part.kind == "tool_result" then
          -- Chat Completions IDs pass through verbatim — no normalization.
          -- Anthropic's restricted charset/length constraints don't apply here.
          local tool_id = part.tool_use_id
          local tool_name = part.name or tool_id

          -- Chat Completions only supports text in tool results.
          -- Concatenate text parts; non-text parts become placeholders with a warning.
          local text_pieces = {}
          for _, rp in ipairs(part.parts or {}) do
            if rp.kind == "text" then
              if rp.text and #rp.text > 0 then
                table.insert(text_pieces, rp.text)
              end
            elseif rp.kind == "text_file" then
              if rp.text and #rp.text > 0 then
                table.insert(text_pieces, rp.text)
              end
            else
              local label = rp.filename or "unknown"
              local mime = rp.mime_type or ""
              if mime ~= "" then
                label = label .. " (" .. mime .. ")"
              end
              table.insert(text_pieces, "[binary file: " .. label .. "]")
              log.warn(
                "openai_chat.build_request: Non-text part (kind="
                  .. rp.kind
                  .. ") in tool result for "
                  .. tool_id
                  .. "; replaced with placeholder"
              )
            end
          end

          local content = table.concat(text_pieces, "")
          if part.is_error then
            content = "Error: " .. (content ~= "" and content or "Tool execution failed")
          end
          table.insert(messages, {
            role = "tool",
            tool_call_id = tool_id,
            name = base.encode_tool_name(tool_name),
            content = content,
          })
          log.debug("openai_chat.build_request: Added tool result for " .. tool_id)
        end
      end

      -- Then user content
      local has_media = false
      local text_parts = {}

      for _, part in ipairs(msg.parts or {}) do
        if part.kind == "text" then
          if vim.trim(part.text or "") ~= "" then
            table.insert(text_parts, part.text)
          end
        elseif part.kind == "image" then
          has_media = true
        elseif part.kind == "text_file" then
          if vim.trim(part.text or "") ~= "" then
            table.insert(text_parts, part.text)
          end
        elseif part.kind == "unsupported_file" then
          table.insert(text_parts, "@" .. (part.filename or ""))
        end
      end

      if has_media then
        -- Multimodal: content is array of typed parts
        local content_parts = {}
        for _, part in ipairs(msg.parts or {}) do
          if part.kind == "text" then
            if vim.trim(part.text or "") ~= "" then
              table.insert(content_parts, { type = "text", text = part.text })
            end
          elseif part.kind == "image" then
            table.insert(content_parts, self:_build_image_part(part))
            log.debug(
              'openai_chat.build_request: Added image part for "'
                .. (part.filename or "image")
                .. '" (MIME: '
                .. part.mime_type
                .. ")"
            )
          elseif part.kind == "text_file" then
            if vim.trim(part.text or "") ~= "" then
              table.insert(content_parts, { type = "text", text = part.text })
            end
          elseif part.kind == "unsupported_file" then
            table.insert(content_parts, { type = "text", text = "@" .. (part.filename or "") })
          end
        end
        if #content_parts > 0 then
          table.insert(messages, { role = "user", content = content_parts })
        end
      elseif #text_parts > 0 then
        -- Text-only: content is a plain string
        table.insert(messages, { role = "user", content = table.concat(text_parts, "") })
      end
    elseif msg.role == "assistant" then
      local text_parts = {}
      local tool_calls = {}
      local reasoning_content = nil

      for _, part in ipairs(msg.parts or {}) do
        if part.kind == "text" then
          local text = vim.trim(part.text or "")
          if #text > 0 then
            table.insert(text_parts, text)
          end
        elseif part.kind == "tool_use" then
          table.insert(tool_calls, {
            id = part.id,
            type = "function",
            ["function"] = {
              name = base.encode_tool_name(part.name),
              arguments = json.encode(part.input),
            },
          })
          log.debug("openai_chat.build_request: Added tool_call for " .. part.name .. " (" .. part.id .. ")")
        elseif part.kind == "thinking" then
          -- Preserve reasoning_content for multi-turn thinking models
          if part.content and #vim.trim(part.content) > 0 then
            reasoning_content = part.content
          end
        end
      end

      local assistant_msg = { role = "assistant" } --[[@as table<string, any>]]
      if #text_parts > 0 then
        assistant_msg.content = table.concat(text_parts, "")
      end
      if #tool_calls > 0 then
        assistant_msg.tool_calls = tool_calls
      end
      if reasoning_content then
        assistant_msg.reasoning_content = reasoning_content
      end
      -- Only add if there's content or tool calls
      if assistant_msg.content or assistant_msg.tool_calls then
        table.insert(messages, assistant_msg)
      else
        log.debug("openai_chat.build_request: Skipping empty assistant message")
      end
    end
  end

  -- Inject synthetic tool messages for orphaned tool calls
  local orphan_results = base._inject_orphan_results(self, prompt.pending_tool_calls, function(orphan)
    return {
      role = "tool",
      tool_call_id = orphan.id,
      name = base.encode_tool_name(orphan.name),
      content = "Error: No result provided",
    }
  end)
  if orphan_results then
    for _, result in ipairs(orphan_results) do
      table.insert(messages, result)
    end
  end

  -- Build tools array from registry
  local sorted_tools = tools_module.get_sorted_for_prompt(prompt.bufnr)
  local tools_array = {}
  for _, definition in ipairs(sorted_tools) do
    table.insert(tools_array, {
      type = "function",
      ["function"] = {
        name = base.encode_tool_name(definition.name),
        description = tools_module.build_description(definition),
        parameters = tools_module.to_json_schema(definition),
      },
    })
  end

  -- Build request body
  ---@type table<string, any>
  local body = {
    model = self.parameters.model,
    messages = messages,
    stream = true,
    stream_options = { include_usage = true },
  }

  -- Max tokens
  local max_tokens_key = self:_max_tokens_key()
  body[max_tokens_key] = self.parameters.max_tokens

  -- Temperature
  if self.parameters.temperature then
    body.temperature = self.parameters.temperature
  end

  -- Tools
  if #tools_array > 0 then
    body.tools = tools_array
    body.tool_choice = "auto"
    log.debug("openai_chat.build_request: Added " .. #tools_array .. " tools to request")
  end

  -- Thinking/reasoning extension point — always called so providers can
  -- handle both enabled and disabled states (e.g., Moonshot locks temperature
  -- to 0.6 when thinking is disabled on kimi-k2.5)
  local model_info = provider_registry.get_model_info(self.metadata.name, self.parameters.model)
  local thinking = normalize.resolve_thinking(self.parameters, self.metadata.capabilities, model_info)
  self:_apply_thinking(body, thinking)

  -- Provider-specific parameters extension point
  self:_apply_provider_params(body, context)

  return body
end

--- Trailing keys for cache-friendly JSON serialization.
--- Tools and messages trail because messages grow each turn.
---@param self flemma.provider.OpenAIChat
---@return string[]
function M.get_trailing_keys(self)
  return { "tools", "messages" }
end

-- ============================================================================
-- Streaming parser
-- ============================================================================

--- Extract usage from a Chat Completions chunk.
--- Usage can appear in two locations:
---   1. On the finish_reason chunk: `choices[0].usage` (sibling of delta)
---   2. On a separate final chunk: empty choices + top-level `data.usage`
---
--- Cached token format varies by provider:
---   - Moonshot: flat `usage.cached_tokens` AND nested `usage.prompt_tokens_details.cached_tokens`
---     (both present, identical values)
---   - Standard OpenAI Chat Completions: nested `usage.prompt_tokens_details.cached_tokens` only
--- Both formats are handled — flat key is checked first, nested as fallback.
---@param self flemma.provider.OpenAIChat
---@param data table The parsed JSON chunk
---@param callbacks flemma.provider.Callbacks
function M._extract_usage(self, data, callbacks)
  local usage = nil

  -- Location 1: sibling of delta on finish_reason chunk
  if data.choices and data.choices[1] and data.choices[1].usage then
    usage = data.choices[1].usage
  end

  -- Location 2: top-level usage on final chunk (stream_options.include_usage)
  if not usage and data.usage then
    usage = data.usage
  end

  if not usage or not callbacks.on_usage then
    return
  end

  -- Cached tokens — read flat key first (Moonshot), fall back to nested (standard OpenAI).
  local cached_tokens = usage.cached_tokens
    or (usage.prompt_tokens_details and usage.prompt_tokens_details.cached_tokens)
    or 0

  if usage.prompt_tokens then
    callbacks.on_usage({ type = "input", tokens = usage.prompt_tokens - cached_tokens })
  end

  if usage.completion_tokens then
    callbacks.on_usage({ type = "output", tokens = usage.completion_tokens })
  end

  if cached_tokens > 0 then
    callbacks.on_usage({ type = "cache_read", tokens = cached_tokens })
    log.debug("openai_chat._extract_usage(): Cached tokens: " .. tostring(cached_tokens))
  end
end

--- Emit accumulated thinking content and reset the thinking sink.
---@param self flemma.provider.OpenAIChat
---@param callbacks flemma.provider.Callbacks
local function flush_thinking(self, callbacks)
  local thinking_content = self._response_buffer.extra.thinking_sink:read()
  if #vim.trim(thinking_content) > 0 then
    local thinking_prefix = self:_thinking_provider_prefix() or self.metadata.name
    base._emit_thinking_block(self, thinking_content, nil, thinking_prefix, callbacks)
  end
  self._response_buffer.extra.thinking_sink:destroy()
  self._response_buffer.extra.thinking_sink = sink.create({ name = self.metadata.name .. "/thinking" })
end

--- Process parsed SSE data for Chat Completions streaming responses.
--- Called by base.process_response_line() after SSE parsing, JSON decode, and error checks.
---@param self flemma.provider.OpenAIChat
---@param data table The parsed JSON data from the SSE line
---@param _parsed flemma.provider.SSELine The original parsed SSE line (unused)
---@param callbacks flemma.provider.Callbacks Table of callback functions
function M._process_data(self, data, _parsed, callbacks)
  -- Handle final usage-only chunk (empty choices with top-level usage).
  -- Skip if we already extracted usage from the finish_reason chunk.
  if data.choices and #data.choices == 0 and data.usage then
    if not self._response_buffer.extra.usage_emitted then
      M._extract_usage(self, data, callbacks)
      self._response_buffer.extra.usage_emitted = true
    end
    return
  end

  -- Require at least one choice
  if not data.choices or not data.choices[1] then
    log.trace("openai_chat._process_data(): No choices in chunk, skipping")
    return
  end

  local choice = data.choices[1]
  local delta = choice.delta
  local finish_reason = choice.finish_reason

  -- Process delta content
  if delta then
    -- Skip role-only markers (assistant role without content/tools)
    local has_content = delta.content ~= nil
    local has_tool_calls = delta.tool_calls ~= nil
    local has_reasoning = delta.reasoning_content ~= nil
    local is_role_only = delta.role ~= nil and not has_content and not has_tool_calls and not has_reasoning

    if is_role_only then
      log.trace("openai_chat._process_data(): Skipping role-only delta")
    else
      -- Reasoning content (always precedes regular content)
      if has_reasoning and delta.reasoning_content ~= "" then
        self._response_buffer.extra.thinking_sink:write(delta.reasoning_content)
        if callbacks.on_thinking then
          callbacks.on_thinking(delta.reasoning_content)
        end
        self:_mark_response_successful()
      end

      -- Regular text content
      if has_content and delta.content ~= "" then
        base._signal_content(self, delta.content, callbacks)
      end

      -- Tool calls (index-based accumulation)
      if has_tool_calls then
        for _, tc in ipairs(delta.tool_calls) do
          local index = tc.index
          if tc.id then
            -- First chunk for this index: has id, type, function.name
            self._response_buffer.extra.tool_calls[index] = {
              id = tc.id,
              name = tc["function"] and tc["function"].name or "",
              arguments = tc["function"] and tc["function"].arguments or "",
            }
            log.debug(
              "openai_chat._process_data(): Started tool_call at index "
                .. tostring(index)
                .. ": "
                .. (tc["function"] and tc["function"].name or "")
            )
          else
            -- Subsequent chunks: only function.arguments
            local existing = self._response_buffer.extra.tool_calls[index]
            if existing and tc["function"] and tc["function"].arguments then
              existing.arguments = existing.arguments .. tc["function"].arguments
            end
          end
          -- Progress tracking
          if callbacks.on_tool_input and tc["function"] and tc["function"].arguments then
            callbacks.on_tool_input(tc["function"].arguments)
          end
        end
        self:_mark_response_successful()
      end
    end
  end

  -- Handle finish_reason
  if finish_reason then
    -- Extract usage from the finish_reason chunk (primary location for Moonshot)
    if not self._response_buffer.extra.usage_emitted then
      M._extract_usage(self, data, callbacks)
      self._response_buffer.extra.usage_emitted = true
    end

    if finish_reason == "stop" or finish_reason == "tool_calls" then
      -- Emit accumulated tool call blocks
      local tool_calls = self._response_buffer.extra.tool_calls
      local sorted_indices = {}
      for idx, _ in pairs(tool_calls) do
        table.insert(sorted_indices, idx)
      end
      table.sort(sorted_indices)

      for _, idx in ipairs(sorted_indices) do
        local tc = tool_calls[idx]
        -- Validate the arguments JSON
        local parse_ok, _ = pcall(json.decode, tc.arguments)
        if not parse_ok then
          log.warn("openai_chat._process_data(): Failed to parse tool arguments JSON: " .. tc.arguments)
          tc.arguments = "{}"
        end
        base._emit_tool_use_block(self, tc.name, tc.id, tc.arguments, callbacks)
      end
      self._response_buffer.extra.tool_calls = {}

      flush_thinking(self, callbacks)

      if callbacks.on_response_complete then
        callbacks.on_response_complete()
      end
    elseif finish_reason == "length" then
      flush_thinking(self, callbacks)
      base._warn_truncated(self, callbacks)
    else
      base._signal_blocked(self, finish_reason, callbacks)
    end
  end
end

return M
