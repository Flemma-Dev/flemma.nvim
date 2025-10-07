--- Google Vertex AI provider for Flemma
--- Implements the Google Vertex AI API integration
local base = require("flemma.provider.base")
local log = require("flemma.logging")
-- local mime_util = require("flemma.mime") -- Moved to base provider
local message_parts = require("flemma.message_parts")
local M = {}

-- Private helper to validate required configuration
local function _validate_config(self)
  local project_id = self.parameters.project_id
  if not project_id or project_id == "" then
    error(
      "Vertex AI project_id is required. Please configure it in `parameters.vertex.project_id` or via :FlemmaSwitch.",
      0
    )
  end
  -- NOTE: Location has a default, and model is handled by provider_config, so only project_id is strictly required here.
end

-- Utility function to generate access token from service account JSON
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
  local output = nil
  local token = nil
  local err = nil

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

-- Create a new Google Vertex AI provider instance
function M.new(provider_config)
  local provider = base.new(provider_config) -- Pass the flattened config to base

  -- Vertex AI-specific state is accessed via self.parameters
  -- self.parameters.project_id is required
  -- self.parameters.location has a default
  -- self.parameters.model is set via base.new

  -- Set the API version
  provider.api_version = "v1" -- Or potentially make this configurable in future

  provider:reset()

  -- Set metatable to use Vertex AI methods
  return setmetatable(provider, { __index = setmetatable(M, { __index = base }) })
end

-- Reset provider state before a new request
function M.reset(self)
  base.reset(self)
  -- Add Vertex-specific extension
  self._response_buffer.extra.accumulated_thoughts = ""
  log.debug("vertex.reset(): Reset Vertex AI provider state")
end

-- Get access token from environment, keyring, or prompt
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

---Build request body for Vertex AI API
---
---@param prompt Prompt The prepared prompt with history and system
---@param context Context The shared context object for resolving file paths
---@return table request_body The request body for the API
function M.build_request(self, prompt, context)
  -- Convert prompt.history to Vertex AI format
  local contents = {}
  local collected_warnings = {} -- Collect all warnings to notify user

  for _, msg in ipairs(prompt.history) do
    -- Map canonical role to Vertex-specific role
    local vertex_role = msg.role == "assistant" and "model" or msg.role
    
    local parts = {}
    if msg.role == "user" then
      -- Parse content into generic parts
      local generic_parts, warnings = message_parts.parse(msg.content, context)
      for _, warning in ipairs(warnings) do
        table.insert(collected_warnings, warning)
      end

      -- Map generic parts to Vertex-specific format
      for _, part in ipairs(generic_parts) do
        if part.kind == "text" then
          table.insert(parts, { text = part.text })
        elseif part.kind == "text_file" then
          table.insert(parts, { text = part.text })
          log.debug('build_request: Added text part for "' .. part.filename .. '" (MIME: ' .. part.mime_type .. ")")
        elseif part.kind == "image" or part.kind == "pdf" then
          table.insert(parts, {
            inlineData = {
              mimeType = part.mime_type,
              data = part.data,
              displayName = vim.fn.fnamemodify(part.filename, ":t"),
            },
          })
          log.debug('build_request: Added inlineData part for "' .. part.filename .. '" (MIME: ' .. part.mime_type .. ")")
        elseif part.kind == "unsupported_file" then
          table.insert(parts, { text = "@" .. part.raw_filename })
        end
      end

      -- Ensure parts is not empty if the original message content was not empty.
      -- This handles cases where content might be, e.g., only unreadable files
      -- or if the parser yields nothing for some valid non-empty inputs.
      if #parts == 0 and msg.content and #msg.content > 0 then
        log.debug(
          "build_request: User content resulted in empty 'parts' after parsing. Original content: \""
            .. msg.content
            .. '". Adding original content as a single text part as fallback.'
        )
        table.insert(parts, { text = msg.content })
      elseif #parts == 0 then -- Original content was empty or only whitespace, or parser yielded nothing.
        log.debug(
          "build_request: User content resulted in empty 'parts' (likely empty or whitespace input). Original content: \""
            .. (msg.content or "")
            .. '". Adding an empty text part.'
        )
        -- Vertex might require a 'parts' array, even if it contains an empty text string.
        table.insert(parts, { text = "" })
      end
    else
      -- For model messages, strip out <thinking>...</thinking> blocks and add the content as a single text part
      local content_without_thoughts = msg.content:gsub("\n?<thinking>.-</thinking>\n?", "")
      table.insert(parts, { text = content_without_thoughts })
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

  -- Notify user of any file-related warnings
  message_parts.notify_warnings("Vertex AI", collected_warnings)

  return request_body
end

-- Get request headers for Vertex AI API
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

-- Get API endpoint for Vertex AI
function M.get_endpoint(self)
  -- Access project_id and location directly from self.parameters
  -- Validate required configuration first
  _validate_config(self)

  -- Access project_id and location directly from self.parameters
  local project_id = self.parameters.project_id
  local location = self.parameters.location

  -- We still need project_id and location for the URL construction.

  if not location then
    log.error( -- Location has a default, so erroring might be too strict, but logging is fine.
      "vertex.get_endpoint(): Vertex AI location is required but missing in parameters: "
        .. log.inspect(self.parameters)
    ) -- Should have a default, but check anyway
    return nil
  end

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
---@param self table The Vertex AI provider instance
---@param line string A single line from the Vertex AI API response stream
---@param callbacks ProviderCallbacks Table of callback functions to handle parsed data
function M.process_response_line(self, line, callbacks)
  -- Skip empty lines
  if not line or line == "" or line == "\r" then
    return
  end

  -- Check for expected format: lines should start with "data: "
  if not line:match("^data: ") then
    -- This is not a standard SSE data line or potentially a non-SSE JSON error
    log.debug("vertex.process_response_line(): Received non-SSE line, adding to accumulator: " .. line)

    -- Add to response accumulator for potential multi-line JSON response
    self:_buffer_response_line(line)

    -- Try parsing as a direct JSON error response (for single-line errors)
    local ok, error_data = pcall(vim.fn.json_decode, line)
    if ok and error_data.error then
      local msg = "Vertex AI API error"
      if error_data.error and error_data.error.message then
        msg = error_data.error.message
      end

      -- Log the error
      log.error("vertex.process_response_line(): Vertex AI API error (parsed from non-SSE line): " .. log.inspect(msg))

      if callbacks.on_error then
        callbacks.on_error(msg) -- Keep original message for user notification
      end
      return
    end

    -- If we can't parse it as an error, continue accumulating
    return
  end

  -- Extract JSON from data: prefix
  local json_str = line:gsub("^data: ", "")
  local parse_ok, data = pcall(vim.fn.json_decode, json_str)
  if not parse_ok then
    log.error("vertex.process_response_line(): Failed to parse JSON from Vertex AI SSE response: " .. json_str)
    return
  end

  -- Validate the response structure
  if type(data) ~= "table" then
    log.error(
      "vertex.process_response_line(): Expected table in Vertex AI SSE response, got type: "
        .. type(data)
        .. ", data: "
        .. log.inspect(data)
    )
    return
  end

  -- Handle error responses
  if data.error then
    local msg = "Vertex AI API error"
    if data.error and data.error.message then
      msg = data.error.message
    end

    log.error("vertex.process_response_line(): Vertex AI API error in SSE response data: " .. log.inspect(msg))

    if callbacks.on_error then
      callbacks.on_error(msg) -- Keep original message for user notification
    end
    return
  end

  -- Process content parts (thoughts or text)
  if data.candidates and data.candidates[1] and data.candidates[1].content and data.candidates[1].content.parts then
    for _, part in ipairs(data.candidates[1].content.parts) do
      if part.thought and part.text and #part.text > 0 then
        log.debug("vertex.process_response_line(): Accumulating thought text: " .. log.inspect(part.text))
        self._response_buffer.extra.accumulated_thoughts = (self._response_buffer.extra.accumulated_thoughts or "")
          .. part.text
      elseif not part.thought and part.text and #part.text > 0 then -- Not a thought, but has text
        log.debug("vertex.process_response_line(): ... Content text: " .. log.inspect(part.text))
        self:_mark_response_successful()
        if callbacks.on_content then
          callbacks.on_content(part.text)
        end
      end
    end
  end

  -- Process usage information if available (can come with content or with finishReason)
  if data.usageMetadata then
    local usage = data.usageMetadata
    -- Handle input tokens
    if usage.promptTokenCount and callbacks.on_usage then
      callbacks.on_usage({ type = "input", tokens = usage.promptTokenCount })
    end
    -- Handle output tokens
    if usage.candidatesTokenCount and callbacks.on_usage then
      callbacks.on_usage({ type = "output", tokens = usage.candidatesTokenCount })
    end
    -- Handle thoughts tokens
    if usage.thoughtsTokenCount and callbacks.on_usage then
      callbacks.on_usage({ type = "thoughts", tokens = usage.thoughtsTokenCount })
    end
  end

  -- Check for finish reason (this indicates the end of the stream for this candidate)
  if data.candidates and data.candidates[1] and data.candidates[1].finishReason then
    log.debug(
      "vertex.process_response_line(): Received finish reason: " .. log.inspect(data.candidates[1].finishReason)
    )

    -- Append aggregated thoughts if any
    if self._response_buffer.extra.accumulated_thoughts and #self._response_buffer.extra.accumulated_thoughts > 0 then
      -- Strip leading/trailing whitespace (including newlines) from thoughts
      local stripped_thoughts = vim.trim(self._response_buffer.extra.accumulated_thoughts)
      -- Construct the thoughts block according to specified formatting:
      -- - Two newlines for separation (ensuring at least one blank line) from previous content.
      -- - <thinking> tag followed by a newline.
      -- - The stripped thoughts content.
      -- - A newline after the thoughts content.
      -- - </thinking> tag followed by a newline.
      local thoughts_block = "\n\n<thinking>\n" .. stripped_thoughts .. "\n</thinking>\n"
      log.debug("vertex.process_response_line(): Appending aggregated thoughts: " .. log.inspect(thoughts_block))
      if callbacks.on_content then
        callbacks.on_content(thoughts_block)
      end
      self._response_buffer.extra.accumulated_thoughts = "" -- Reset for next potential full message
    end

    -- Signal response completion (after all content, including thoughts, has been sent)
    if callbacks.on_response_complete then
      callbacks.on_response_complete()
    end

    return -- Important to return after handling finishReason
  end
end

-- Override base class error extraction to handle Vertex AI specific error formats
function M.extract_json_response_error(self, data)
  -- First try Vertex AI specific patterns

  -- Pattern 1: Array response with error [{ error: { ... } }]
  if vim.tbl_islist(data) and #data > 0 and type(data[1]) == "table" and data[1].error then
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
