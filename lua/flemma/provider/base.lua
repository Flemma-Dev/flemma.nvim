--- Base provider for Flemma
--- Defines the interface that all providers must implement

--[[
Provider Contract
=================

This module is the authoritative reference for implementing custom providers.
Every provider must inherit from `base` and satisfy the contract below.

Required class-level fields
---------------------------
- `output_has_thoughts` (boolean) — whether `output_tokens` already includes
  thinking tokens for cost calculation.  Default `false` (thinking is reported
  separately); set `true` if the provider bundles them together.
- `endpoint` (string) — base API URL.
- `api_version` (string|nil) — optional API version identifier.

Required method overrides
-------------------------
- `new(opts)` — constructor; must call `base.new(opts)` and set provider-
  specific fields.
- `get_api_key(self, opts)` — authentication; call `base.get_api_key()` with
  the appropriate env/keyring opts table.
- `get_endpoint(self)` — return the API URL (default returns `self.endpoint`).
- `get_request_headers(self)` — return a string array of HTTP headers.
- `build_request(self, prompt, context)` — convert a canonical `Prompt` into
  the provider's API request format.
- `process_response_line(self, line, callbacks)` — parse one SSE line and call
  the appropriate callbacks.
- `reset(self)` — call `base.reset(self)` plus any provider-specific state
  initialization.

Optional method overrides
-------------------------
- `validate_parameters(model_name, parameters)` — parameter validation
  (warnings, not failures).
- `finalize_response(self, exit_code, callbacks)` — post-request cleanup.
- `extract_json_response_error(self, data)` — custom error extraction from
  JSON responses.
- `try_import_from_buffer(self, lines)` — import conversations from external
  formats.

Callbacks contract (`callbacks` table passed to `process_response_line`)
------------------------------------------------------------------------
- `on_content(text)` — streamed text content.
- `on_thinking(text)` — streamed thinking/reasoning content (optional).
- `on_usage(usage_data)` — token usage; `usage_data.type` is one of:
  `"input"`, `"output"`, `"thoughts"`, `"cache_read"`, `"cache_creation"`.
- `on_error(message)` — API error string.
- `on_response_complete()` — signals end of response content.

Capabilities contract (registered via `registry.register`)
----------------------------------------------------------
- `supports_reasoning` — provider accepts a reasoning effort level.
- `supports_thinking_budget` — provider accepts a token budget for thinking.
- `outputs_thinking` — provider streams thinking content into the buffer.
- `min_thinking_budget` — minimum valid thinking budget value (omit if N/A).

Missing boolean capabilities default to `false` at registration time.

Helper methods available to providers (call via `self:method()`)
----------------------------------------------------------------
- `_parse_sse_line(line, opts)` — parse SSE `data:`/`event:` lines.
- `_signal_content(self, text, callbacks)` — emit content and mark response
  successful.
- `_handle_non_sse_line(self, line, callbacks)` — buffer non-SSE lines and try
  JSON error parsing.
- `_has_content(self)` / `_content_ends_with_newline(self)` — query accumulated
  content.
- `normalize_tool_id(id)` — convert URN-style Flemma tool IDs to
  `[a-zA-Z0-9_-]+` format.
]]

local log = require("flemma.logging")

---@class flemma.provider.UsageData
---@field type "input"|"output"|"thoughts"|"cache_read"|"cache_creation" Type of token usage
---@field tokens number Number of tokens used

---@class flemma.provider.Callbacks
---@field on_error fun(message: string) Called when an API error occurs
---@field on_usage fun(usage_data: flemma.provider.UsageData) Called when token usage information is received
---@field on_response_complete fun() Called when the AI response content is complete
---@field on_content fun(text: string) Called when response content is received
---@field on_thinking? fun(text: string) Called when thinking/reasoning content is received (optional)

---@class flemma.provider.ProviderState
---@field api_key string|nil Cached API key

--- Flattened per-provider parameters (result of config_manager.merge_parameters on flemma.config.Parameters).
--- Provider-specific sub-tables (e.g. `vertex`, `openai`) are merged to top level.
---@class flemma.provider.Parameters
---@field model string Model name (always present after initialization)
---@field max_tokens? integer Maximum tokens in the response
---@field temperature? number Sampling temperature
---@field timeout? integer Response timeout in seconds
---@field connect_timeout? integer Connection timeout in seconds
---@field [string] any Provider-specific parameters

---@class flemma.provider.ResponseBuffer
---@field lines string[]
---@field successful boolean
---@field extra table<string, any>
---@field content string

---@class flemma.provider.Base
---@field output_has_thoughts boolean
---@field parameters flemma.provider.Parameters
---@field state flemma.provider.ProviderState
---@field endpoint? string
---@field api_version? string
---@field _response_buffer? flemma.provider.ResponseBuffer
---@field set_parameter_overrides fun(self, overrides: table<string, any>|nil)
local M = {}

--- Whether output_tokens already includes thoughts_tokens for this provider.
--- - true: thoughts already counted in output (OpenAI, Anthropic) - don't add for cost
--- - false: thoughts are separate (Vertex) - add to output for cost
M.output_has_thoughts = false

---@param opts flemma.provider.Parameters|nil
---@return flemma.provider.Base
function M.new(opts)
  local base_params = opts or {}
  local overrides = nil

  local params_proxy = setmetatable({}, {
    __index = function(_, k)
      if overrides and overrides[k] ~= nil then
        return overrides[k]
      end
      return base_params[k]
    end,
    __newindex = function(_, k, v)
      base_params[k] = v
    end,
  })

  local provider = setmetatable({
    parameters = params_proxy,
    state = {
      api_key = nil,
    },
  }, { __index = M })

  --- Set per-request parameter overrides (from frontmatter).
  --- Each call replaces any previous overrides; pass nil to clear.
  ---@param new_overrides table<string, any>|nil
  function provider.set_parameter_overrides(_, new_overrides)
    overrides = new_overrides
  end

  ---@diagnostic disable-next-line: return-type-mismatch
  return provider
end

---@param service_name string
---@param key_name string
---@param project_id string|nil
---@return string|nil
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

---@class flemma.provider.ApiKeyOpts
---@field env_var_name? string
---@field keyring_service_name? string
---@field keyring_key_name? string
---@field keyring_project_id? string

--- Get API key from environment, keyring, or prompt
---@param self flemma.provider.Base
---@param opts flemma.provider.ApiKeyOpts|nil
---@return string|nil
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

---@class flemma.provider.HistoryMessage
---@field role "user"|"assistant"
---@field parts flemma.ast.GenericPart[]

---@class flemma.provider.Prompt
---@field history flemma.provider.HistoryMessage[] User/assistant messages (canonical roles)
---@field system string|nil The system instruction, if any
---@field opts flemma.opt.ResolvedOpts|nil Per-buffer options from frontmatter
---@field pending_tool_calls flemma.pipeline.UnresolvedTool[]|nil Tool calls without matching results

---Prepare prompt from raw messages
---
---This is a default implementation that normalizes messages into a provider-agnostic
---Prompt structure with canonical roles ('user' and 'assistant'). System messages
---are extracted separately. If multiple system messages exist, last one wins.
---
---Providers can override this if they need custom normalization, but in most cases
---the provider-specific role mapping should happen in build_request instead.
---
---@param messages { type: string, content: string }[] The raw messages to prepare
---@return flemma.provider.Prompt prompt The prepared prompt with history and system (canonical roles)
function M.prepare_prompt(self, messages) ---@diagnostic disable-line: unused-local
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
---@param prompt flemma.provider.Prompt The prepared prompt with history and system
---@param context? flemma.Context The shared context object for resolving file paths
---@return table<string, any> request_body The request body for the API
function M.build_request(self, prompt, context) ---@diagnostic disable-line: unused-local
  -- To be implemented by specific providers
  return {}
end

--- Get request headers (to be implemented by specific providers)
---@param self flemma.provider.Base
---@return string[]|nil
function M.get_request_headers(self) ---@diagnostic disable-line: unused-local
  -- To be implemented by specific providers
end

--- Get API endpoint (to be implemented by specific providers)
---@param self flemma.provider.Base
---@return string|nil
function M.get_endpoint(self)
  -- Default implementation returns self.endpoint
  -- Providers like Vertex can override to construct dynamic URLs
  return self.endpoint
end

--- Process a single line of API response data
--- This method is called for each line of data received from the streaming API response.
--- Providers should parse the line, extract content/usage information, and call appropriate callbacks.
---@param self flemma.provider.Base The provider instance
---@param line string A single line from the API response stream
---@param callbacks flemma.provider.Callbacks Table of callback functions to handle parsed data
function M.process_response_line(self, line, callbacks) ---@diagnostic disable-line: unused-local
  -- To be implemented by specific providers
end

--- Create a new response buffer for accumulating non-processable lines
---@param self flemma.provider.Base
function M._new_response_buffer(self)
  self._response_buffer = {
    lines = {},
    successful = false,
    extra = {},
    content = "", -- Accumulated content for spacing decisions
  }
end

--- Buffer a non-processable response line for later analysis
---@param self flemma.provider.Base
---@param line string
function M._buffer_response_line(self, line)
  if not self._response_buffer then
    self:_new_response_buffer()
  end
  table.insert(self._response_buffer.lines, line)
end

--- Mark that response processing has been successful
---@param self flemma.provider.Base
function M._mark_response_successful(self)
  if not self._response_buffer then
    self:_new_response_buffer()
  end
  self._response_buffer.successful = true
end

--- Check buffered response lines for JSON errors
---@param self flemma.provider.Base
---@param callbacks flemma.provider.Callbacks
---@return boolean
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

--- Extract error message from response JSON data (override point for providers)
--- Base implementation handles common error patterns across different APIs
---@param self flemma.provider.Base
---@param data table<string, any>
---@return string|nil
function M.extract_json_response_error(self, data) ---@diagnostic disable-line: unused-local
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

--- Normalize tool call ID for provider compatibility
--- Ensures the ID satisfies all provider constraints:
--- - Only contains characters matching [a-zA-Z0-9_-]
--- - Maximum 64 characters (Anthropic's documented limit)
--- - No trailing underscores (rejected by some providers)
---@param id string The tool call ID to normalize
---@return string normalized_id The normalized ID safe for all supported providers
function M.normalize_tool_id(id)
  if not id then
    return id
  end
  -- Replace any character not in [a-zA-Z0-9_-] with underscore
  local normalized = id:gsub("[^a-zA-Z0-9_%-]", "_")
  -- Enforce maximum length of 64 characters
  if #normalized > 64 then
    normalized = normalized:sub(1, 64)
  end
  -- Strip trailing underscores
  normalized = normalized:gsub("_+$", "")
  return normalized
end

--- Detect whether an error message indicates a context window overflow
--- Providers can override this to add provider-specific patterns.
---@param message string|nil The error message to check
---@return boolean
function M:is_context_overflow(message)
  if not message or type(message) ~= "string" then
    return false
  end
  local lower = message:lower()
  -- Anthropic: "prompt is too long: N tokens > M maximum"
  if lower:match("prompt is too long") then
    return true
  end
  -- OpenAI: "exceeds the context window" / "maximum context length"
  if lower:match("exceeds the context window") then
    return true
  end
  if lower:match("maximum context length") then
    return true
  end
  -- Vertex/Google: "input token count (N) exceeds the maximum"
  if lower:match("input token count") and lower:match("exceeds the maximum") then
    return true
  end
  -- Generic fallbacks
  if lower:match("context[_ ]length[_ ]exceeded") then
    return true
  end
  if lower:match("too many tokens") then
    return true
  end
  if lower:match("token limit exceeded") then
    return true
  end
  return false
end

---@class flemma.provider.SSELine
---@field type "data"|"event"|"done"
---@field content? string Present when type="data"
---@field event_type? string Present when type="event"

---Parse a single SSE (Server-Sent Events) line (internal)
---@param line string The raw line from the stream
---@param opts? { allow_done?: boolean }
---@return flemma.provider.SSELine|nil
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
---@param self flemma.provider.Base The provider instance
---@param line string The non-SSE line to handle
---@param callbacks flemma.provider.Callbacks Table of callback functions
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
---@param self flemma.provider.Base The provider instance
---@param text string The content text to signal
---@param callbacks flemma.provider.Callbacks Table of callback functions
function M._signal_content(self, text, callbacks)
  self:_mark_response_successful()
  self._response_buffer.content = self._response_buffer.content .. text
  if callbacks.on_content then
    callbacks.on_content(text)
  end
end

---Check if any content has been accumulated in the response buffer
---@param self flemma.provider.Base The provider instance
---@return boolean has_content True if content has been accumulated
function M._has_content(self)
  return self._response_buffer.content and #self._response_buffer.content > 0
end

---Check if the last character of accumulated content is a newline
---@param self flemma.provider.Base The provider instance
---@return boolean ends_with_newline True if content ends with newline
function M._content_ends_with_newline(self)
  local content = self._response_buffer.content or ""
  return content:sub(-1) == "\n"
end

--- Reset provider state before a new request
--- This can be overridden by specific providers to reset their state
---@param self flemma.provider.Base
function M.reset(self)
  -- Create response buffer for all providers
  self:_new_response_buffer()
end

--- Finalize response processing and handle provider-specific cleanup
--- This method is called when the HTTP request process completes, allowing providers
--- to perform cleanup tasks like processing any remaining buffered data.
---@param self flemma.provider.Base The provider instance
---@param exit_code number The HTTP request exit code (0 for success, non-zero for failure)
---@param callbacks flemma.provider.Callbacks Table of callback functions for any remaining data processing
function M.finalize_response(self, exit_code, callbacks) ---@diagnostic disable-line: unused-local
  -- Check buffered response if we haven't processed content successfully
  if self._response_buffer and not self._response_buffer.successful then
    self:_check_buffered_response(callbacks)
  end
end

--- Try to import from buffer lines (to be implemented by specific providers)
---@param self flemma.provider.Base
---@param lines string[]
---@return string|nil
function M.try_import_from_buffer(self, lines) ---@diagnostic disable-line: unused-local
  -- To be implemented by specific providers
  return nil
end

---Validate provider-specific parameters (base implementation)
---Providers can override this to add custom validation logic
---@param model_name string The model name
---@param parameters table<string, any> The parameters to validate
---@return boolean success True if validation passes (warnings don't fail)
function M.validate_parameters(model_name, parameters) ---@diagnostic disable-line: unused-local
  return true
end

return M
