--- Base provider for Flemma
--- Defines the interface that all providers must implement
local log = require("flemma.logging")

---@class UsageData
---@field type "input"|"output"|"thoughts" Type of token usage
---@field tokens number Number of tokens used

---@class ProviderCallbacks
---@field on_error fun(message: string) Called when an API error occurs
---@field on_usage fun(usage_data: UsageData) Called when token usage information is received
---@field on_response_complete fun() Called when the AI response content is complete
---@field on_content fun(text: string) Called when response content is received
---@field on_thinking? fun(text: string) Called when thinking/reasoning content is received (optional)

local M = {}

-- Provider constructor
function M.new(opts)
  local provider = setmetatable({
    parameters = opts or {}, -- parameters now includes the model
    state = {
      api_key = nil,
    },
  }, { __index = M })

  return provider
end

-- Try to get API key from system keyring (local helper function)
local function try_keyring(service_name, key_name, project_id)
  if vim.fn.has("linux") == 1 then
    local cmd
    if project_id then
      -- Include project_id in the lookup if provided
      cmd = string.format(
        "secret-tool lookup service %s key %s project_id %s 2>/dev/null",
        service_name,
        key_name,
        project_id
      )
    else
      cmd = string.format("secret-tool lookup service %s key %s 2>/dev/null", service_name, key_name)
    end

    local handle = io.popen(cmd)
    if handle then
      local result = handle:read("*a")
      handle:close()
      if result and #result > 0 then
        return result:gsub("%s+$", "") -- Trim whitespace
      end
    end
  end
  return nil
end

-- Get API key from environment, keyring, or prompt
function M.get_api_key(self, opts)
  -- Return cached key if we have it and it's not empty
  if self.state.api_key and self.state.api_key ~= "" then
    log.debug("get_api_key(): Using cached API key")
    return self.state.api_key
  end

  -- Reset the API key to nil to ensure we don't use an empty string
  self.state.api_key = nil

  -- Try environment variable if provided
  if opts and opts.env_var_name then
    local env_key = os.getenv(opts.env_var_name)
    -- Only set if not empty
    if env_key and env_key ~= "" then
      self.state.api_key = env_key
    end
  end

  -- Try system keyring if no env var and service/key names are provided
  if not self.state.api_key and opts and opts.keyring_service_name and opts.keyring_key_name then
    -- First try with project_id if provided
    if opts.keyring_project_id then
      local key = try_keyring(opts.keyring_service_name, opts.keyring_key_name, opts.keyring_project_id)
      if key and key ~= "" then
        self.state.api_key = key
        log.debug(
          "get_api_key(): Retrieved API key from keyring with project ID: " .. log.inspect(opts.keyring_project_id)
        )
      end
    end

    -- Fall back to generic lookup if project-specific key wasn't found
    if not self.state.api_key then
      local key = try_keyring(opts.keyring_service_name, opts.keyring_key_name)
      if key and key ~= "" then
        self.state.api_key = key
      end
    end
  end

  return self.state.api_key
end

---@class Prompt
---@field history table[] User/assistant messages only (canonical roles: 'user', 'assistant')
---@field system string|nil The system instruction, if any

---Prepare prompt from raw messages
---
---This is a default implementation that normalizes messages into a provider-agnostic
---Prompt structure with canonical roles ('user' and 'assistant'). System messages
---are extracted separately. If multiple system messages exist, last one wins.
---
---Providers can override this if they need custom normalization, but in most cases
---the provider-specific role mapping should happen in build_request instead.
---
---@param messages table[] The raw messages to prepare
---@return Prompt prompt The prepared prompt with history and system (canonical roles)
function M.prepare_prompt(self, messages)
  local history = {}
  local system = nil

  -- Extract system message (last wins policy)
  for _, msg in ipairs(messages) do
    if msg.type == "System" then
      system = vim.trim(msg.content or "")
    end
  end

  -- Add user and assistant messages with canonical roles
  for _, msg in ipairs(messages) do
    local role = nil
    if msg.type == "You" then
      role = "user"
    elseif msg.type == "Assistant" then
      role = "assistant"
    end

    if role then
      table.insert(history, {
        role = role,
        content = vim.trim(msg.content or ""),
      })
    end
  end

  return { history = history, system = system }
end

---Build request body for API (to be implemented by specific providers)
---
---Contract: This method receives a prepared Prompt and converts it into the
---provider's specific API request format. Each provider decides how to incorporate
---the system instruction into its wire format.
---
---@param prompt Prompt The prepared prompt with history and system
---@param context Context The shared context object for resolving file paths
---@return table request_body The request body for the API
function M.build_request(self, prompt, context)
  -- To be implemented by specific providers
  return {}
end

-- Get request headers (to be implemented by specific providers)
function M.get_request_headers(self)
  -- To be implemented by specific providers
end

-- Get API endpoint (to be implemented by specific providers)
function M.get_endpoint(self)
  -- Default implementation returns self.endpoint
  -- Providers like Vertex can override to construct dynamic URLs
  return self.endpoint
end

--- Process a single line of API response data
--- This method is called for each line of data received from the streaming API response.
--- Providers should parse the line, extract content/usage information, and call appropriate callbacks.
---@param self table The provider instance
---@param line string A single line from the API response stream
---@param callbacks ProviderCallbacks Table of callback functions to handle parsed data
function M.process_response_line(self, line, callbacks)
  -- To be implemented by specific providers
end

-- Create a new response buffer for accumulating non-processable lines
function M._new_response_buffer(self)
  self._response_buffer = {
    lines = {},
    successful = false,
    extra = {},
  }
end

-- Buffer a non-processable response line for later analysis
function M._buffer_response_line(self, line)
  if not self._response_buffer then
    self:_new_response_buffer()
  end
  table.insert(self._response_buffer.lines, line)
end

-- Mark that response processing has been successful
function M._mark_response_successful(self)
  if not self._response_buffer then
    self:_new_response_buffer()
  end
  self._response_buffer.successful = true
end

-- Check buffered response lines for JSON errors
function M._check_buffered_response(self, callbacks)
  if not self._response_buffer or #self._response_buffer.lines == 0 then
    return false
  end

  local body = table.concat(self._response_buffer.lines, "\n")
  local ok, data = pcall(vim.fn.json_decode, body)
  if not ok then
    return false
  end

  local msg = self:extract_json_response_error(data)
  if msg and callbacks.on_error then
    callbacks.on_error(msg)
    return true
  end
  return false
end

-- Extract error message from response JSON data (override point for providers)
-- Base implementation handles common error patterns across different APIs
function M.extract_json_response_error(self, data)
  if type(data) ~= "table" then
    return nil
  end

  -- Try common error patterns in order of likelihood

  -- Pattern 1: { error: { message: "..." } } (OpenAI, Anthropic style)
  if data.error and type(data.error) == "table" and data.error.message then
    return data.error.message
  end

  -- Pattern 2: { error: "..." } (simple error string)
  if data.error and type(data.error) == "string" then
    return data.error
  end

  -- Pattern 3: { message: "..." } (direct message field)
  if data.message and type(data.message) == "string" then
    return data.message
  end

  -- Pattern 4: { errors: [{ message: "..." }] } (array of errors)
  if data.errors and type(data.errors) == "table" and #data.errors > 0 then
    local first_error = data.errors[1]
    if type(first_error) == "table" and first_error.message then
      return first_error.message
    end
  end

  -- No recognizable error pattern found
  return nil
end

---Parse a single SSE (Server-Sent Events) line (internal)
---@param line string The raw line from the stream
---@param opts? table Optional parsing options { allow_done?: boolean }
---@return table|nil parsed { type: "data"|"event"|"done", content?: string, event_type?: string }
function M._parse_sse_line(line, opts)
  opts = opts or {}

  -- Skip empty lines
  if not line or line == "" or line == "\r" then
    return nil
  end

  -- Handle event lines (event: type)
  if line:match("^event: ") then
    local event_type = line:gsub("^event: ", "")
    return { type = "event", event_type = event_type }
  end

  -- Handle data lines (data: ...)
  if line:match("^data: ") then
    local content = line:gsub("^data: ", "")

    -- Handle [DONE] message
    if content == "[DONE]" and opts.allow_done ~= false then
      return { type = "done" }
    end

    return { type = "data", content = content }
  end

  -- Not an SSE line
  return nil
end

---Handle a non-SSE line by buffering it and attempting to parse as JSON error (internal)
---@param self table The provider instance
---@param line string The non-SSE line to handle
---@param callbacks ProviderCallbacks Table of callback functions
---@return boolean handled True if the line was successfully parsed as an error
function M._handle_non_sse_line(self, line, callbacks)
  log.debug("base.handle_non_sse_line(): Received non-SSE line, buffering: " .. line)

  -- Buffer the line for later analysis
  self:_buffer_response_line(line)

  -- Try parsing as a direct JSON error response (for single-line errors)
  local ok, error_data = pcall(vim.fn.json_decode, line)
  if ok and error_data and type(error_data) == "table" then
    local msg = self:extract_json_response_error(error_data)
    if msg and callbacks.on_error then
      log.error("base.handle_non_sse_line(): Parsed JSON error from non-SSE line: " .. log.inspect(msg))
      callbacks.on_error(msg)
      return true
    end
  end

  return false
end

---Signal content to the caller and mark response as successful (internal)
---@param self table The provider instance
---@param text string The content text to signal
---@param callbacks ProviderCallbacks Table of callback functions
function M._signal_content(self, text, callbacks)
  self:_mark_response_successful()
  if callbacks.on_content then
    callbacks.on_content(text)
  end
end

-- Reset provider state before a new request
-- This can be overridden by specific providers to reset their state
function M.reset(self)
  -- Create response buffer for all providers
  self:_new_response_buffer()
end

--- Finalize response processing and handle provider-specific cleanup
--- This method is called when the HTTP request process completes, allowing providers
--- to perform cleanup tasks like processing any remaining buffered data.
---@param self table The provider instance
---@param exit_code number The HTTP request exit code (0 for success, non-zero for failure)
---@param callbacks ProviderCallbacks Table of callback functions for any remaining data processing
function M.finalize_response(self, exit_code, callbacks)
  -- Check buffered response if we haven't processed content successfully
  if self._response_buffer and not self._response_buffer.successful then
    self:_check_buffered_response(callbacks)
  end
end

-- Try to import from buffer lines (to be implemented by specific providers)
function M.try_import_from_buffer(self, lines)
  -- To be implemented by specific providers
  return nil
end

---Validate provider-specific parameters (base implementation)
---Providers can override this to add custom validation logic
---@param model_name string The model name
---@param parameters table The parameters to validate
---@return boolean success True if validation passes (warnings don't fail)
function M.validate_parameters(model_name, parameters)
  return true
end

return M
