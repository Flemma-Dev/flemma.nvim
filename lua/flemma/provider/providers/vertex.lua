--- Google Vertex AI provider for Flemma
--- Implements the Google Vertex AI API integration
local base = require("flemma.provider.base")
local log = require("flemma.logging")

---@class flemma.provider.Vertex : flemma.provider.Base
local M = {}

-- Inherit from base provider
setmetatable(M, { __index = base })

---@type flemma.provider.Metadata
M.metadata = {
  name = "vertex",
  display_name = "Vertex AI",
  capabilities = {
    supports_reasoning = false,
    supports_thinking_budget = true,
    outputs_thinking = true,
    min_thinking_budget = 1,
  },
  default_parameters = {
    project_id = nil,
    location = "global",
    thinking_budget = nil,
  },
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

---@param service_account_json string
---@return string|nil token
---@return string|nil error
local function generate_access_token(service_account_json)
  -- Create a temporary file with the service account JSON
  local tmp_file = os.tmpname()
  local f = io.open(tmp_file, "w")
  if not f then
    return nil, "Failed to create temporary file for service account"
  end
  f:write(service_account_json)
  f:close()

  -- Schedule deletion of the temporary file after 60 seconds as a safety measure
  -- This ensures the file is deleted even if there's an unhandled error
  vim.defer_fn(function()
    if vim.fn.filereadable(tmp_file) == 1 then
      log.debug("vertex.generate_access_token(): Safety timer: removing temporary service account file: " .. tmp_file)
      os.remove(tmp_file)
    end
  end, 60 * 1000) -- 60 seconds in milliseconds

  -- First check if gcloud is installed
  local check_cmd = "command -v gcloud >/dev/null 2>&1"
  local check_result = os.execute(check_cmd)

  if check_result ~= 0 then
    -- Clean up the temporary file
    os.remove(tmp_file)
    return nil,
      "gcloud command not found. Please install the Google Cloud CLI or set VERTEX_AI_ACCESS_TOKEN environment variable."
  end

  -- Use gcloud to generate an access token
  -- Capture both stdout and stderr for better error reporting
  local cmd = string.format("GOOGLE_APPLICATION_CREDENTIALS=%s gcloud auth print-access-token 2>&1", tmp_file)
  local handle = io.popen(cmd)
  local output, token, err

  if handle then
    output = handle:read("*a")
    local success, _, code = handle:close()

    -- Clean up the temporary file immediately after use
    os.remove(tmp_file)

    if success and output and #output > 0 then
      -- Check if the output looks like a token (no error messages)
      if
        not output:match("ERROR:")
        and not output:match("command not found")
        and not output:match("not recognized")
      then
        -- Trim whitespace
        token = output:gsub("%s+$", "")
        -- Basic validation: tokens are usually long strings without spaces
        if #token > 20 and not token:match("%s") then
          return token
        else
          err = "Invalid token format received from gcloud"
          log.debug("vertex.generate_access_token(): Invalid token format received from gcloud: " .. output)
        end
      else
        -- This is an error message from gcloud
        err = "gcloud error: " .. output
        log.debug("vertex.generate_access_token(): gcloud command output: " .. output)
      end
    else
      err = "Failed to generate access token (exit code: " .. tostring(code) .. ")"
      if output and #output > 0 then
        err = err .. "\nOutput: " .. output
        log.debug("vertex.generate_access_token(): gcloud command output: " .. output)
      end
    end
  else
    -- Clean up the temporary file
    os.remove(tmp_file)
    err = "Failed to execute gcloud command"
  end

  return nil, err
end

---@param provider_config flemma.provider.Parameters
---@return flemma.provider.Vertex
function M.new(provider_config)
  local provider = base.new(provider_config) -- Pass the flattened config to base

  -- Vertex AI-specific state is accessed via self.parameters
  -- self.parameters.project_id is required
  -- self.parameters.location has a default
  -- self.parameters.model is set via base.new

  -- Set the API version
  provider.api_version = "v1" -- Or potentially make this configurable in future

  -- Set metatable BEFORE reset so M.reset (not base.reset) initializes provider-specific state
  setmetatable(provider, { __index = setmetatable(M, { __index = base }) })
  provider:reset()

  ---@diagnostic disable-next-line: return-type-mismatch
  return provider
end

---@param self flemma.provider.Vertex
function M.reset(self)
  base.reset(self)
  -- Add Vertex-specific extension
  self._response_buffer.extra.accumulated_thoughts = ""
  -- Track thought signature for state preservation (used with thinking mode + function calls)
  self._response_buffer.extra.thought_signature = nil
  log.debug("vertex.reset(): Reset Vertex AI provider state")
end

---@param self flemma.provider.Vertex
---@return string|nil
function M.get_api_key(self)
  -- Validate required configuration first
  _validate_config(self)

  -- Access project_id directly from self.parameters (needed for keyring lookup)
  local project_id = self.parameters.project_id

  -- First try to get token from environment variable
  local env_token = os.getenv("VERTEX_AI_ACCESS_TOKEN")
  if env_token and #env_token > 0 then
    self.state.api_key = env_token
    return env_token
  end

  -- Try to get service account JSON from keyring
  local service_account_json = base.get_api_key(self, {
    env_var_name = "VERTEX_SERVICE_ACCOUNT",
    keyring_service_name = "vertex",
    keyring_key_name = "api",
    keyring_project_id = project_id, -- Use project_id from parameters
  })

  -- If we have service account JSON, try to generate an access token
  if service_account_json and service_account_json:match("service_account") then
    log.debug("vertex.get_api_key(): Found service account JSON, attempting to generate access token")

    local generated_token, err = generate_access_token(service_account_json)
    if generated_token then
      log.debug("vertex.get_api_key(): Successfully generated access token from service account")
      self.state.api_key = generated_token
      return generated_token
    else
      log.error("vertex.get_api_key(): Failed to generate access token: " .. (err or "unknown error"))
      if err then
        error(
          err
            .. "\n\n---\n\nVertex AI requires the Google Cloud CLI (gcloud) to generate access tokens from service accounts.\n"
            .. "Please install gcloud or set VERTEX_AI_ACCESS_TOKEN environment variable.",
          0
        )
      else
        error(
          "Vertex AI requires the Google Cloud CLI (gcloud) to generate access tokens from service accounts.\n"
            .. "Please install gcloud or set VERTEX_AI_ACCESS_TOKEN environment variable.",
          0
        )
      end
    end
  end

  -- If we have something but it's not a service account JSON, it might be a direct token
  if service_account_json and #service_account_json > 0 then
    self.state.api_key = service_account_json
    return service_account_json
  end

  return nil
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
function M.build_request(self, prompt, _context) ---@diagnostic disable-line: unused-local
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

          -- Build response object: wrap string in {result: ...}, pass JSON through
          local response_obj
          if part.is_error then
            response_obj = { error = part.content, success = false }
          else
            -- Try to parse as JSON first
            local ok, parsed = pcall(vim.fn.json_decode, part.content)
            if ok and type(parsed) == "table" then
              response_obj = parsed
            else
              response_obj = { result = part.content }
            end
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
      local combined_text = table.concat(text_parts, "")
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

  local request_body = {
    contents = contents,
    generationConfig = {
      maxOutputTokens = self.parameters.max_tokens,
      temperature = self.parameters.temperature,
    },
  }

  -- Add thinking budget if configured
  local configured_budget = self.parameters.thinking_budget
  local add_thinking_config = false -- Default to false, only set true if budget >= 1
  local api_budget_value

  if type(configured_budget) == "number" and configured_budget >= 1 then
    -- Thinking is enabled and budget is specified
    api_budget_value = math.floor(configured_budget)
    add_thinking_config = true -- Set to true as budget is valid for thinking
    log.debug(
      "build_request: Vertex AI thinking_budget is "
        .. tostring(configured_budget)
        .. ". Enabling thinking and setting API thinkingBudget to: "
        .. api_budget_value
        .. "."
    )
  elseif configured_budget == 0 then
    -- Thinking is explicitly disabled by setting budget to 0
    log.debug("build_request: Vertex AI thinking_budget is 0. Thinking is disabled. Not sending thinkingConfig.")
    -- add_thinking_config remains false
  elseif configured_budget == nil then
    -- Thinking budget is not set (nil), so default behavior (no thinkingConfig)
    log.debug("build_request: Vertex AI thinking_budget is nil. Not sending thinkingConfig.")
    -- add_thinking_config remains false
  else
    -- Handles negative numbers or other invalid types if they somehow get here.
    log.warn(
      "build_request: Vertex AI thinking_budget ("
        .. log.inspect(configured_budget)
        .. ") is invalid. Not sending thinkingConfig."
    )
    -- add_thinking_config remains false
  end

  if add_thinking_config then
    -- This block now only executes if configured_budget is a number and >= 1
    request_body.generationConfig = request_body.generationConfig or {}
    request_body.generationConfig.thinkingConfig = {
      thinkingBudget = api_budget_value,
      includeThoughts = true, -- If thinkingConfig is sent, includeThoughts should be true
    }
    log.debug(
      "build_request: Vertex AI thinkingConfig included with thinkingBudget: "
        .. api_budget_value
        .. " and includeThoughts: true."
    )
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
  local tools_module = require("flemma.tools")
  local all_tools = tools_module.get_for_prompt(prompt.opts)
  local function_declarations = {}

  for _, def in pairs(all_tools) do
    table.insert(function_declarations, {
      name = def.name,
      description = tools_module.build_description(def),
      parameters = def.input_schema,
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

--- Process a single line of Vertex AI API streaming response
--- Parses Vertex AI's JSON response format and extracts content, reasoning, usage, and completion information
---@param self flemma.provider.Vertex
---@param line string A single line from the Vertex AI API response stream
---@param callbacks flemma.provider.Callbacks Table of callback functions to handle parsed data
function M.process_response_line(self, line, callbacks)
  -- Use base SSE parser
  local parsed = base._parse_sse_line(line)
  if not parsed then
    -- Handle non-SSE lines
    base._handle_non_sse_line(self, line, callbacks)
    return
  end

  -- Vertex doesn't send events or [DONE], only data
  if parsed.type ~= "data" then
    return
  end

  -- Parse JSON data
  local ok, data = pcall(vim.fn.json_decode, parsed.content)
  if not ok then
    log.error("vertex.process_response_line(): Failed to parse JSON: " .. parsed.content)
    return
  end

  if type(data) ~= "table" then
    log.error("vertex.process_response_line(): Expected table in response, got type: " .. type(data))
    return
  end

  -- Handle error responses
  if data.error then
    local msg = self:extract_json_response_error(data) or "Unknown API error"
    log.error("vertex.process_response_line(): Vertex AI API error: " .. log.inspect(msg))
    if callbacks.on_error then
      callbacks.on_error(msg)
    end
    return
  end

  -- Process content parts (thoughts, text, or functionCall)
  if data.candidates and data.candidates[1] and data.candidates[1].content and data.candidates[1].content.parts then
    for _, part in ipairs(data.candidates[1].content.parts) do
      -- Capture thoughtSignature if present on ANY part (for state preservation with thinking mode)
      -- This is a generic solution - Vertex can return thoughtSignature on any part type
      if part.thoughtSignature then
        self._response_buffer.extra.thought_signature = part.thoughtSignature
        log.debug("vertex.process_response_line(): Captured thoughtSignature from part")
      end

      if part.thought and part.text and #part.text > 0 then
        log.debug("vertex.process_response_line(): Accumulating thought text: " .. log.inspect(part.text))
        self._response_buffer.extra.accumulated_thoughts = (self._response_buffer.extra.accumulated_thoughts or "")
          .. part.text
      elseif part.functionCall then
        -- Handle function call
        local fc = part.functionCall
        if fc.name then
          -- Generate synthetic ID: urn:flemma:tool:<name>:<unique>
          local unique_suffix = string.format("%x", os.time()) .. string.format("%04x", math.random(0, 65535))
          local generated_id = string.format("urn:flemma:tool:%s:%s", fc.name, unique_suffix)

          -- Determine fence length for JSON content
          local json_str = vim.fn.json_encode(fc.args or {})
          local max_ticks = 0
          for ticks in json_str:gmatch("`+") do
            max_ticks = math.max(max_ticks, #ticks)
          end
          local fence = string.rep("`", math.max(3, max_ticks + 1))

          -- Format for buffer display (matches Anthropic format)
          -- Use appropriate prefix based on what's already accumulated
          local prefix = ""
          if self:_has_content() then
            prefix = self:_content_ends_with_newline() and "\n" or "\n\n"
          end
          local formatted = string.format(
            "%s**Tool Use:** `%s` (`%s`)\n\n%sjson\n%s\n%s\n",
            prefix,
            fc.name,
            generated_id,
            fence,
            json_str,
            fence
          )

          base._signal_content(self, formatted, callbacks)
          log.debug(
            "vertex.process_response_line(): Emitted function call for " .. fc.name .. " (" .. generated_id .. ")"
          )
        else
          log.warn("vertex.process_response_line(): Received functionCall without name")
        end
      elseif not part.thought and part.text then
        -- Only emit text that contains non-whitespace (skip whitespace-only chunks
        -- that would cause prefix issues with subsequent tool use blocks)
        if part.text:match("%S") then
          log.debug("vertex.process_response_line(): Content text: " .. log.inspect(part.text))
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
      log.debug("vertex.process_response_line(): Cached content tokens: " .. tostring(cached_tokens))
    end
  end

  -- Check for finish reason (this indicates the end of the stream for this candidate)
  if data.candidates and data.candidates[1] and data.candidates[1].finishReason then
    log.debug(
      "vertex.process_response_line(): Received finish reason: " .. log.inspect(data.candidates[1].finishReason)
    )

    -- Append aggregated thoughts if any (or emit empty thinking tag if we have a signature)
    local has_thoughts = self._response_buffer.extra.accumulated_thoughts
      and #self._response_buffer.extra.accumulated_thoughts > 0
    local has_signature = self._response_buffer.extra.thought_signature ~= nil

    if has_thoughts or has_signature then
      -- Use single newline prefix if content already ends with newline, else double
      local prefix = self:_content_ends_with_newline() and "\n" or "\n\n"

      local thoughts_block
      if has_thoughts then
        -- Strip leading/trailing whitespace (including newlines) from thoughts
        local stripped_thoughts = vim.trim(self._response_buffer.extra.accumulated_thoughts)

        if has_signature then
          -- Include signature attribute on opening tag (namespaced for Vertex)
          thoughts_block = prefix
            .. '<thinking vertex:signature="'
            .. self._response_buffer.extra.thought_signature
            .. '">\n'
            .. stripped_thoughts
            .. "\n</thinking>\n"
        else
          -- No signature, simple tag
          thoughts_block = prefix .. "<thinking>\n" .. stripped_thoughts .. "\n</thinking>\n"
        end
      else
        -- No thinking content but have signature — emit open/close tag (enables folding)
        thoughts_block = prefix
          .. '<thinking vertex:signature="'
          .. self._response_buffer.extra.thought_signature
          .. '">\n</thinking>\n'
      end

      log.debug("vertex.process_response_line(): Appending thinking block: " .. log.inspect(thoughts_block))
      base._signal_content(self, thoughts_block, callbacks)

      -- Reset for next potential full message
      self._response_buffer.extra.accumulated_thoughts = ""
      self._response_buffer.extra.thought_signature = nil
    end

    -- Signal response completion (after all content, including thoughts, has been sent)
    if callbacks.on_response_complete then
      callbacks.on_response_complete()
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

  -- If Vertex-specific patterns don't match, fall back to base class patterns
  return base.extract_json_response_error(self, data)
end

return M
