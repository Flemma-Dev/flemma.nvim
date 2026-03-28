--- Google Vertex AI provider for Flemma
--- Implements the Google Vertex AI API integration
local base = require("flemma.provider.base")
local json = require("flemma.utilities.json")
local log = require("flemma.logging")
local normalize = require("flemma.provider.normalize")
local s = require("flemma.schema")
local sink = require("flemma.sink")
local tools_module = require("flemma.tools")
local provider_registry = require("flemma.provider.registry")

--- Maps Vertex AI finish reasons to normalized stop outcomes.
--- Only STOP and MAX_TOKENS are non-error; everything else (SAFETY, RECITATION, etc.) is an error.
---@type table<string, "stop"|"length">
local FINISH_REASON_MAP = {
  STOP = "stop",
  MAX_TOKENS = "length",
}

---@class flemma.provider.Vertex : flemma.provider.Base
local M = {}

-- Inherit from base provider
setmetatable(M, { __index = base })

---@type flemma.provider.Metadata
M.metadata = {
  name = "vertex",
  display_name = "Vertex AI",
  models = { "flemma.models.vertex" },
  capabilities = {
    supports_reasoning = false,
    supports_thinking_budget = true,
    outputs_thinking = true,
    output_has_thoughts = false,
    min_thinking_budget = 1,
  },
  config_schema = s.object({
    project_id = s.optional(s.string()),
    location = s.optional(s.string("global")),
    thinking_budget = s.optional(s.integer()),
  }),
}

---@param self flemma.provider.Vertex
local function _validate_config(self)
  local project_id = self.parameters.project_id
  if not project_id or project_id == "" then
    error(
      "Vertex AI project_id is required. Please configure it in `parameters.vertex.project_id` or via :Flemma switch.",
      0
    )
  end
  -- NOTE: Location has a default, and model is handled by provider_config, so only project_id is strictly required here.
end

---@param params flemma.provider.Parameters
---@return flemma.provider.Vertex
function M.new(params)
  local self = setmetatable({
    parameters = params or {},
    state = {},
    api_version = "v1beta1", -- v1beta1 supports parametersJsonSchema for full JSON Schema compatibility
  }, { __index = setmetatable(M, { __index = base }) })
  self:_new_response_buffer()
  self._response_buffer.extra.thinking_sink = sink.create({
    name = "vertex/thinking",
  })
  self._response_buffer.extra.thought_signature = nil
  return self --[[@as flemma.provider.Vertex]]
end

---@param self flemma.provider.Vertex
---@return flemma.secrets.Credential
function M.get_credential(self)
  _validate_config(self)
  return {
    kind = "access_token",
    service = "vertex",
    description = "Vertex AI access token",
    ttl = 3600,
    ttl_scale = 0.925,
    aliases = { "VERTEX_AI_ACCESS_TOKEN" },
  }
end

--- Extract function name from Flemma synthetic ID
--- Format: urn:flemma:tool:<name>:<unique>
---@param tool_use_id string The synthetic tool use ID
---@return string function_name The extracted function name, or "unknown" if extraction fails
local function extract_function_name_from_id(tool_use_id)
  local function_name = tool_use_id:match("^urn:flemma:tool:([^:]+):")
  if not function_name then
    log.warn("vertex.extract_function_name_from_id: Could not extract function name from ID: " .. tool_use_id)
    return "unknown"
  end
  return function_name
end

---Build request body for Vertex AI API
---
---@param prompt flemma.provider.Prompt The prepared prompt with history and system
---@param _context? flemma.Context The shared context object for resolving file paths
---@return table<string, any> request_body The request body for the API
function M.build_request(self, prompt, _context)
  -- Convert prompt.history to Vertex AI format
  local contents = {}

  for _, msg in ipairs(prompt.history) do
    -- Map canonical role to Vertex-specific role
    local vertex_role = msg.role == "assistant" and "model" or msg.role

    local parts = {}
    if msg.role == "user" then
      -- Tool results must come first in user messages (similar to Anthropic)
      for _, part in ipairs(msg.parts or {}) do
        if part.kind == "tool_result" then
          -- Extract function name from the synthetic ID
          local function_name = extract_function_name_from_id(part.tool_use_id)

          -- Build response object: use { output: ... } for success, { error: ... } for errors
          -- (matches the official Google SDK convention that Pi/Gemini models expect)
          local response_obj
          if part.is_error then
            response_obj = { error = part.content }
          else
            response_obj = { output = part.content }
          end

          table.insert(parts, {
            functionResponse = {
              name = function_name,
              response = response_obj,
            },
          })
          log.debug("vertex.build_request: Added functionResponse for " .. function_name)
        end
      end

      -- Then other content
      for _, part in ipairs(msg.parts or {}) do
        if part.kind == "text" then
          if vim.trim(part.text or "") ~= "" then
            table.insert(parts, { text = part.text })
          end
        elseif part.kind == "text_file" then
          table.insert(parts, { text = part.text })
          log.debug(
            'build_request: Added text part for "'
              .. (part.filename or "text_file")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "image" or part.kind == "pdf" then
          table.insert(parts, {
            inlineData = {
              mimeType = part.mime_type,
              data = part.data,
              displayName = part.filename and vim.fn.fnamemodify(part.filename, ":t") or "file",
            },
          })
          log.debug(
            'build_request: Added inlineData part for "'
              .. (part.filename or "file")
              .. '" (MIME: '
              .. part.mime_type
              .. ")"
          )
        elseif part.kind == "unsupported_file" then
          table.insert(parts, { text = "@" .. (part.filename or "") })
        end
        -- tool_result already handled above
      end

      -- Ensure parts is not empty
      if #parts == 0 then
        log.debug("build_request: User content resulted in empty 'parts'. Adding an empty text part.")
        table.insert(parts, { text = "" })
      end
    else
      -- For model/assistant messages, extract text from parts, handle tool_use, skip thinking
      local text_parts = {}
      local function_calls = {}
      local thought_signature = nil

      -- First pass: extract signature from thinking parts
      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "thinking" and p.signature and p.signature.provider == "vertex" then
          thought_signature = p.signature.value
          log.debug("vertex.build_request: Found thought signature in thinking part")
        end
      end

      -- Second pass: build content
      for _, p in ipairs(msg.parts or {}) do
        if p.kind == "text" then
          table.insert(text_parts, p.text or "")
        elseif p.kind == "tool_use" then
          -- Convert tool_use to Vertex functionCall format
          local fc_part = {
            functionCall = {
              name = p.name,
              args = p.input,
            },
          }
          -- Attach thought signature to first function call (per Vertex API requirements)
          if thought_signature and #function_calls == 0 then
            fc_part.thoughtSignature = thought_signature
            log.debug("vertex.build_request: Attached thoughtSignature to functionCall for " .. p.name)
          end
          table.insert(function_calls, fc_part)
          log.debug("vertex.build_request: Added functionCall for " .. p.name)
        elseif p.kind == "thinking" then
          -- Skip thinking nodes - Vertex handles extended thinking internally
          -- Signature already extracted above
        end
      end
      -- Add text if any
      local combined_text = vim.trim(table.concat(text_parts, ""))
      if #combined_text > 0 then
        local text_part = { text = combined_text }
        -- If we have a signature but no function calls, attach signature to the text part
        if thought_signature and #function_calls == 0 then
          text_part.thoughtSignature = thought_signature
          log.debug("vertex.build_request: Attached thoughtSignature to text part (no function calls)")
        end
        table.insert(parts, text_part)
      end
      -- Add function calls
      for _, fc in ipairs(function_calls) do
        table.insert(parts, fc)
      end
      -- Ensure parts is not empty for model messages
      if #parts == 0 then
        local empty_part = { text = "" }
        -- Even for empty parts, attach signature if present and no function calls
        if thought_signature and #function_calls == 0 then
          empty_part.thoughtSignature = thought_signature
          log.debug("vertex.build_request: Attached thoughtSignature to empty text part (no function calls)")
        end
        table.insert(parts, empty_part)
      end
    end

    -- Add the message with its Vertex-specific role and parts to the contents list
    table.insert(contents, {
      role = vertex_role,
      parts = parts,
    })
  end

  -- Inject synthetic error results for orphaned tool calls
  local orphan_results = base._inject_orphan_results(self, prompt.pending_tool_calls, function(orphan)
    return {
      functionResponse = {
        name = orphan.name,
        response = { error = "No result provided", success = false },
      },
    }
  end)
  if orphan_results then
    table.insert(contents, {
      role = "user",
      parts = orphan_results,
    })
  end

  local request_body = {
    contents = contents,
    generationConfig = {
      maxOutputTokens = self.parameters.max_tokens,
      temperature = self.parameters.temperature,
    },
  }

  -- Add thinking configuration using unified resolution
  local model_info = provider_registry.get_model_info("vertex", self.parameters.model)
  local thinking = normalize.resolve_thinking(self.parameters, M.metadata.capabilities, model_info)

  if thinking.enabled then
    local thinking_config = { includeThoughts = true }

    if thinking.mapped_effort then
      -- Gemini 3+ models: effort from resolve_thinking's mapped_effort
      thinking_config.thinkingLevel = thinking.mapped_effort
      log.debug("build_request: Vertex AI thinkingConfig included with thinkingLevel: " .. thinking.mapped_effort)
    elseif thinking.budget then
      -- Gemini 2.5 and earlier: use thinkingBudget (numeric token count)
      thinking_config.thinkingBudget = thinking.budget
      log.debug("build_request: Vertex AI thinkingConfig included with thinkingBudget: " .. thinking.budget)
    end

    request_body.generationConfig = request_body.generationConfig or {}
    request_body.generationConfig.thinkingConfig = thinking_config
  else
    log.debug("build_request: Vertex AI thinkingConfig not included in the request.")
  end

  -- Add system instruction if provided
  if prompt.system then
    request_body.systemInstruction = {
      parts = {
        { text = prompt.system },
      },
    }
  end

  -- Build tools array from registry (Vertex AI format, filtered by per-buffer opts if present)
  local sorted_tools = tools_module.get_sorted_for_prompt(prompt.bufnr)
  local function_declarations = {}

  for _, definition in ipairs(sorted_tools) do
    table.insert(function_declarations, {
      name = definition.name,
      description = tools_module.build_description(definition),
      parametersJsonSchema = tools_module.to_json_schema(definition),
    })
  end

  -- Add tools if any are registered
  if #function_declarations > 0 then
    request_body.tools = {
      {
        functionDeclarations = function_declarations,
      },
    }
    request_body.toolConfig = {
      functionCallingConfig = {
        mode = "AUTO",
      },
    }
    log.debug("vertex.build_request: Added " .. #function_declarations .. " function declarations to request")
  end

  return request_body
end

--- Trailing keys for cache-friendly JSON serialization.
--- Vertex uses `contents` as its messages array.
---@param self flemma.provider.Vertex
---@return string[]
function M.get_trailing_keys(self)
  return { "tools", "contents" }
end

---@param self flemma.provider.Vertex
---@return string[]
function M.get_request_headers(self)
  local access_token = self:get_api_key()
  if not access_token then
    error("No Vertex AI access token available. Please set up a service account or provide an access token.", 0)
  end

  return {
    "Authorization: Bearer " .. access_token,
    "Content-Type: application/json",
  }
end

---@param self flemma.provider.Vertex
---@return string
function M.get_endpoint(self)
  -- Access project_id and location directly from self.parameters
  -- Validate required configuration first
  _validate_config(self)

  -- Access project_id and location directly from self.parameters
  local project_id = self.parameters.project_id
  local location = self.parameters.location or "global" -- Fallback to default if missing

  -- Ensure we're using the streamGenerateContent endpoint with SSE format
  local hostname
  if location == "global" then
    hostname = "aiplatform.googleapis.com"
  else
    hostname = location .. "-aiplatform.googleapis.com"
  end

  local endpoint = string.format(
    "https://%s/%s/projects/%s/locations/%s/publishers/google/models/%s:streamGenerateContent?alt=sse",
    hostname,
    self.api_version,
    project_id,
    location,
    self.parameters.model -- Use model from parameters
  )

  log.debug("vertex.get_endpoint(): Using Vertex AI endpoint: " .. endpoint)
  return endpoint
end

--- Process parsed SSE data for Vertex AI.
--- Called by base.process_response_line() after SSE parsing, JSON decoding, and error detection.
---@param self flemma.provider.Vertex
---@param data table Parsed JSON data from the SSE line
---@param _parsed flemma.provider.SSELine The parsed SSE line metadata (unused by Vertex)
---@param callbacks flemma.provider.Callbacks Table of callback functions to handle parsed data
function M._process_data(self, data, _parsed, callbacks)
  -- Process content parts (thoughts, text, or functionCall)
  if data.candidates and data.candidates[1] and data.candidates[1].content and data.candidates[1].content.parts then
    for _, part in ipairs(data.candidates[1].content.parts) do
      -- Retain thoughtSignature for state preservation with thinking mode.
      -- Only overwrite when incoming is a non-empty string to prevent empty chunks
      -- from clobbering a valid signature (matches Pi's retainThoughtSignature logic).
      if type(part.thoughtSignature) == "string" and #part.thoughtSignature > 0 then
        self._response_buffer.extra.thought_signature = part.thoughtSignature
        log.trace("vertex._process_data(): Captured thoughtSignature from part")
      end

      if part.thought and part.text and #part.text > 0 then
        log.trace("vertex._process_data(): Accumulating thought text: " .. log.inspect(part.text))
        self._response_buffer.extra.thinking_sink:write(part.text)
        if callbacks.on_thinking then
          callbacks.on_thinking(part.text)
        end
      elseif part.functionCall then
        -- Handle function call
        local fc = part.functionCall
        if fc.name then
          -- Generate synthetic ID: urn:flemma:tool:<name>:<unique>
          local unique_suffix = string.format("%x", os.time()) .. string.format("%04x", math.random(0, 65535))
          local generated_id = string.format("urn:flemma:tool:%s:%s", fc.name, unique_suffix)

          local json_str = json.encode(fc.args or {})
          -- Notify progress tracking with the complete tool input (Vertex delivers
          -- args in one shot, not streamed incrementally like Anthropic)
          if callbacks.on_tool_input then
            callbacks.on_tool_input(json_str)
          end
          base._emit_tool_use_block(self, fc.name, generated_id, json_str, callbacks)
        else
          log.warn("vertex._process_data(): Received functionCall without name")
        end
      elseif not part.thought and part.text then
        -- Only emit text that contains non-whitespace (skip whitespace-only chunks
        -- that would cause prefix issues with subsequent tool use blocks)
        if part.text:match("%S") then
          log.trace("vertex._process_data(): Content text: " .. log.inspect(part.text))
          base._signal_content(self, part.text, callbacks)
        end
      end
    end
  end

  -- Process usage information if available (can come with content or with finishReason)
  if data.usageMetadata then
    local usage = data.usageMetadata
    -- Extract cached tokens first so we can subtract from promptTokenCount.
    -- Vertex's promptTokenCount includes cachedContentTokenCount as a subset, so we
    -- normalize to make input_tokens mean "non-cached input" (matching Anthropic's semantics).
    local cached_tokens = (usage.cachedContentTokenCount and usage.cachedContentTokenCount > 0)
        and usage.cachedContentTokenCount
      or 0

    -- Handle input tokens
    if usage.promptTokenCount and callbacks.on_usage then
      callbacks.on_usage({ type = "input", tokens = usage.promptTokenCount - cached_tokens })
    end
    -- Handle output tokens
    if usage.candidatesTokenCount and callbacks.on_usage then
      callbacks.on_usage({ type = "output", tokens = usage.candidatesTokenCount })
    end
    -- Handle thoughts tokens
    if usage.thoughtsTokenCount and callbacks.on_usage then
      callbacks.on_usage({ type = "thoughts", tokens = usage.thoughtsTokenCount })
    end
    -- Handle cached content tokens (implicit caching on Gemini 2.5+ models)
    if cached_tokens > 0 and callbacks.on_usage then
      callbacks.on_usage({ type = "cache_read", tokens = cached_tokens })
      log.debug("vertex._process_data(): Cached content tokens: " .. tostring(cached_tokens))
    end
  end

  -- Check for finish reason (this indicates the end of the stream for this candidate)
  if data.candidates and data.candidates[1] and data.candidates[1].finishReason then
    log.debug("vertex._process_data(): Received finish reason: " .. log.inspect(data.candidates[1].finishReason))

    -- Emit aggregated thinking block (handles content, signature, empty-tag, and prefix)
    local accumulated_thoughts = self._response_buffer.extra.thinking_sink:read()
    base._emit_thinking_block(
      self,
      accumulated_thoughts,
      self._response_buffer.extra.thought_signature,
      "vertex",
      callbacks
    )

    -- Reset thinking state for next potential full message
    self._response_buffer.extra.thinking_sink:destroy()
    self._response_buffer.extra.thinking_sink = sink.create({
      name = "vertex/thinking",
    })
    self._response_buffer.extra.thought_signature = nil

    -- Map the finish reason to a normalized outcome
    local raw_reason = data.candidates[1].finishReason
    local mapped = FINISH_REASON_MAP[raw_reason] -- nil → error (anything not STOP or MAX_TOKENS)

    if mapped == "length" then
      base._warn_truncated(self, callbacks)
    elseif mapped == "stop" then
      -- STOP: normal completion
      if callbacks.on_response_complete then
        callbacks.on_response_complete()
      end
    else
      base._signal_blocked(self, tostring(raw_reason), callbacks)
    end

    return -- Important to return after handling finishReason
  end
end

---@param self flemma.provider.Vertex
---@param data table<string, any>
---@return string|nil
function M.extract_json_response_error(self, data)
  -- First try Vertex AI specific patterns

  -- Pattern 1: Array response with error [{ error: { ... } }]
  if vim.islist(data) and #data > 0 and type(data[1]) == "table" and data[1].error then
    local error_data = data[1]
    local msg = "Vertex AI API error"

    if error_data.error then
      if error_data.error.message then
        msg = error_data.error.message
      end

      if error_data.error.status then
        msg = msg .. " (Status: " .. error_data.error.status .. ")"
      end

      -- Include details if available
      if error_data.error.details and #error_data.error.details > 0 then
        for _, detail in ipairs(error_data.error.details) do
          if detail["@type"] and detail["@type"]:match("BadRequest") and detail.fieldViolations then
            for _, violation in ipairs(detail.fieldViolations) do
              if violation.description then
                msg = msg .. "\n" .. violation.description
              end
            end
          end
        end
      end
    end

    return msg
  end

  -- Pattern 2: Non-array object response { error: { message, status, details } }
  if not vim.islist(data) and type(data.error) == "table" and data.error.message then
    local msg = data.error.message
    if data.error.status then
      msg = msg .. " (Status: " .. data.error.status .. ")"
    end
    if data.error.details and type(data.error.details) == "table" and #data.error.details > 0 then
      for _, detail in ipairs(data.error.details) do
        if detail["@type"] and detail["@type"]:match("BadRequest") and detail.fieldViolations then
          for _, violation in ipairs(detail.fieldViolations) do
            if violation.description then
              msg = msg .. "\n" .. violation.description
            end
          end
        end
      end
    end
    return msg
  end

  -- If Vertex-specific patterns don't match, fall back to base class patterns
  return base.extract_json_response_error(self, data)
end

--- Validate Vertex-specific parameters.
--- Warns early about missing required configuration that would cause a request-time error.
---@param _model_name string The model name
---@param parameters table<string, any> The parameters to validate
---@return boolean success Always true (warnings don't fail validation)
---@return string[]|nil warnings Human-readable warning strings, or nil when clean
function M.validate_parameters(_model_name, parameters)
  if not parameters.project_id or parameters.project_id == "" then
    return true, { "project_id is required — configure it in `parameters.vertex.project_id` or via :Flemma switch" }
  end
  return true
end

--- Detect whether an error message indicates an authentication failure.
--- Overrides base virtual to match Vertex-specific UNAUTHENTICATED patterns.
---@param self flemma.provider.Vertex
---@param message string|nil The error message to check
---@return boolean
function M.is_auth_error(self, message)
  if not message or type(message) ~= "string" then
    return false
  end
  local lower = message:lower()
  if lower:match("unauthenticated") then
    return true
  end
  if lower:match("invalid authentication credentials") then
    return true
  end
  return false
end

return M
