--- Base provider for Flemma
--- Defines the interface that all providers must implement

--[[
Provider Contract
=================

This module is the authoritative reference for implementing custom providers.
Every provider must inherit from `base` and satisfy the contract below.

Methods are grouped into three categories:

  Abstract — provider MUST override; base raises an error
  --------------------------------------------------------
  - `build_request(self, prompt, context)` — convert a canonical `Prompt`
    into the provider's API request format.
  - `get_request_headers(self)` — return a string array of HTTP headers.
  - `_process_data(self, data, parsed, callbacks)` — handle a single parsed
    SSE data event (JSON already decoded, errors already checked).

  Template method — base drives, provider hooks
  ----------------------------------------------
  - `process_response_line(self, line, callbacks)` — SSE parsing, JSON
    decoding, error detection; delegates to `_process_data`.
  - `_is_error_response(self, data)` — detect provider-specific error shapes
    (default: `data.error ~= nil`).

  Required — provider MUST implement
  -----------------------------------
  - `new(params)` — constructor; creates the instance with plain
    `self.parameters` table, sets metatable chain, calls
    `self:_new_response_buffer()`, and performs any provider-specific
    response buffer setup. See concrete providers for the pattern.
  - `get_credential(self)` — return a `flemma.secrets.Credential` table
    describing what this provider needs (kind, service, description, etc.).
    `get_api_key()` in base calls this, then resolves via `secrets.resolve()`.

  Virtual — sensible default provided, override only if needed
  -------------------------------------------------------------
  - `get_endpoint(self)` — return the API URL (default: `self.endpoint`).
  - `validate_parameters(model_name, parameters)` — returns `true, warnings[]`.
    Providers collect warnings; caller handles logging/notification.
  - `finalize_response(self, exit_code, callbacks)` — post-request cleanup.
    Auto-destroys sinks in `_response_buffer.extra`.
  - `extract_json_response_error(self, data)` — custom error extraction
    from JSON responses.
  - `try_import_from_buffer(lines)` — import conversations from
    external formats (static, no instance state).
  - `is_context_overflow(self, message)` — detect context window overflow
    from error messages.
  - `is_auth_error(self, message)` — detect authentication failures
    (default `false`; override for providers with expiring tokens).

Required class-level fields
---------------------------
- `endpoint` (string) — base API URL.
- `api_version` (string|nil) — optional API version identifier.

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
- `output_has_thoughts` — whether `output_tokens` already includes thinking
  tokens for cost calculation (default `false`).
- `min_thinking_budget` — minimum valid thinking budget value (omit if N/A).

Missing boolean capabilities default to `false` at registration time.
]]

local json = require("flemma.utilities.json")
local log = require("flemma.logging")
local secrets = require("flemma.secrets")
local sink = require("flemma.sink")

-- ============================================================================
-- Type definitions
-- ============================================================================

---@class flemma.provider.UsageData
---@field type "input"|"output"|"thoughts"|"cache_read"|"cache_creation" Type of token usage
---@field tokens number Number of tokens used

---@class flemma.provider.Callbacks
---@field on_error fun(message: string) Called when an API error occurs
---@field on_usage fun(usage_data: flemma.provider.UsageData) Called when token usage information is received
---@field on_response_complete fun() Called when the AI response content is complete
---@field on_content fun(text: string) Called when response content is received
---@field on_thinking? fun(text: string) Called when thinking/reasoning content is received (optional)
---@field on_tool_input? fun(delta: string) Called when tool input JSON delta is received (optional, for progress tracking)

---@class flemma.provider.ProviderState

--- Flattened per-provider parameters (result of normalize.flatten_parameters).
--- Provider-specific sub-tables (e.g. `vertex`, `openai`) are merged to top level.
---@class flemma.provider.Parameters
---@field model string Model name (always present after initialization)
---@field max_tokens? integer Maximum tokens in the response
---@field temperature? number Sampling temperature
---@field timeout? integer Response timeout in seconds
---@field connect_timeout? integer Connection timeout in seconds
---@field [string] any Provider-specific parameters

---@class flemma.provider.ResponseBuffer
---@field lines_sink flemma.Sink
---@field successful boolean
---@field extra table<string, any>
---@field content string

---@class flemma.provider.Base
---@field parameters flemma.provider.Parameters
---@field state flemma.provider.ProviderState
---@field endpoint? string
---@field api_version? string
---@field metadata? flemma.provider.Metadata
---@field get_credential fun(self): flemma.secrets.Credential Credential descriptor (providers must override)
---@field get_api_key fun(self): string|nil, flemma.secrets.ResolverDiagnostic[]|nil Resolve credentials via secrets module
---@field _response_buffer? flemma.provider.ResponseBuffer
---@field _response_headers? table<string, string[]>
local M = {}

---@class flemma.provider.HistoryMessage
---@field role "user"|"assistant"
---@field parts flemma.ast.GenericPart[]

---@class flemma.provider.Prompt
---@field history flemma.provider.HistoryMessage[] User/assistant messages (canonical roles)
---@field system string|nil The system instruction, if any
---@field bufnr? integer Buffer number for per-buffer config resolution
---@field pending_tool_calls flemma.pipeline.UnresolvedTool[]|nil Tool calls without matching results

---@class flemma.provider.SSELine
---@field type "data"|"event"|"done"
---@field content? string Present when type="data"
---@field event_type? string Present when type="event"

-- ============================================================================
-- Abstract — providers MUST override these (base raises an error)
-- ============================================================================

--- @abstract
--- Build request body for the provider's API
---
--- Receives a prepared Prompt and converts it into the provider's specific API
--- request format. Each provider decides how to incorporate the system
--- instruction into its wire format.
---@param prompt flemma.provider.Prompt The prepared prompt with history and system
---@param context? flemma.Context The shared context object for resolving file paths
---@return table<string, any> request_body The request body for the API
function M.build_request(self, prompt, context)
  error("build_request() must be implemented by provider")
end

--- @abstract
--- Return the credential descriptor for this provider.
---@param self flemma.provider.Base
---@return flemma.secrets.Credential
function M.get_credential(self)
  error("get_credential() must be implemented by provider")
end

--- Resolve credentials via the secrets module using the provider's credential descriptor.
---@param self flemma.provider.Base
---@return string|nil value, flemma.secrets.ResolverDiagnostic[]|nil diagnostics
function M.get_api_key(self)
  local result, diagnostics = secrets.resolve(self:get_credential())
  if result then
    return result.value
  end
  return nil, diagnostics
end

--- @abstract
--- Return HTTP headers for the provider's API
---@param self flemma.provider.Base
---@return string[]|nil
function M.get_request_headers(self)
  error("get_request_headers() must be implemented by provider")
end

--- Process a single line of streaming API response data.
--- Handles SSE parsing, JSON decoding, and error detection.
--- Delegates to _process_data() for provider-specific event dispatch.
---@param self flemma.provider.Base
---@param line string A single line from the API response stream
---@param callbacks flemma.provider.Callbacks
function M.process_response_line(self, line, callbacks)
  local parsed = M._parse_sse_line(line)
  if not parsed then
    M._handle_non_sse_line(self, line, callbacks)
    return
  end

  -- Handle [DONE] and event: lines
  if parsed.type == "done" or parsed.type ~= "data" then
    return
  end

  local ok, data = pcall(json.decode, parsed.content)
  if not ok then
    log.error(self.metadata.name .. ".process_response_line(): Failed to parse JSON: " .. parsed.content)
    return
  end
  if type(data) ~= "table" then
    log.error(self.metadata.name .. ".process_response_line(): Expected table, got: " .. type(data))
    return
  end

  -- Provider-specific error detection
  if self:_is_error_response(data) then
    local message = self:extract_json_response_error(data) or "Unknown API error"
    log.error(self.metadata.name .. ".process_response_line(): API error: " .. log.inspect(message))
    if callbacks.on_error then
      callbacks.on_error(message)
    end
    return
  end

  self:_process_data(data, parsed, callbacks)
end

--- @abstract
--- Process parsed SSE data after base preamble (error checking, JSON decoding).
--- Providers MUST override this to dispatch provider-specific events.
---@param self flemma.provider.Base
---@param data table Parsed JSON data from the SSE line
---@param parsed flemma.provider.SSELine The parsed SSE line metadata
---@param callbacks flemma.provider.Callbacks
function M._process_data(self, data, parsed, callbacks)
  error("_process_data() must be implemented by provider")
end

-- ============================================================================
-- Required — providers MUST implement new(params) with this pattern:
--
--   function M.new(params)
--     local self = setmetatable({
--       parameters = params or {},
--       state = {},
--       endpoint = "...",
--     }, { __index = setmetatable(M, { __index = base }) })
--     self:_new_response_buffer()
--     -- Provider-specific response buffer setup here
--     return self
--   end
-- ============================================================================

--- Destroy all sink objects in a response buffer's extra table.
--- Finds values with a :destroy() method via duck typing.
---@param response_buffer flemma.provider.ResponseBuffer|nil
local function destroy_sinks(response_buffer)
  if not response_buffer or not response_buffer.extra then
    return
  end
  for _, value in pairs(response_buffer.extra) do
    if type(value) == "table" and type(value.destroy) == "function" then
      value:destroy()
    end
  end
end

-- ============================================================================
-- Virtual — sensible defaults provided, override only if needed
-- ============================================================================

--- Return the API endpoint URL.
--- Default returns `self.endpoint`. Override for dynamic URL construction
--- (e.g. Vertex embeds project/location in the URL).
---@param self flemma.provider.Base
---@return string|nil
function M.get_endpoint(self)
  return self.endpoint
end

--- Return keys that should appear last in the serialized JSON request body.
--- Providers override this to place dynamic content (messages, tools) after
--- static config keys, maximizing prefix-based prompt cache hits.
--- Non-trailing keys are sorted alphabetically; trailing keys appear in the
--- order returned by this method.
---@param self flemma.provider.Base
---@return string[]
function M.get_trailing_keys(self)
  return {}
end

--- Validate provider-specific parameters.
--- Override to collect warnings about invalid or unsupported parameter combinations.
--- Return true with no warnings for clean validation, or true + warnings array for
--- advisories. The caller (core.lua) handles logging and vim.notify — providers
--- never call vim.notify or log.warn from this method.
---@param model_name string The model name
---@param parameters table<string, any> The parameters to validate
---@return boolean success Always true (warnings don't fail validation)
---@return string[]|nil warnings Human-readable warning strings, or nil when clean
function M.validate_parameters(model_name, parameters)
  return true
end

--- Finalize response processing after the HTTP request completes.
--- Override to perform cleanup tasks like processing remaining buffered data.
---@param self flemma.provider.Base The provider instance
---@param exit_code number The HTTP request exit code (0 for success, non-zero for failure)
---@param callbacks flemma.provider.Callbacks Table of callback functions for any remaining data processing
function M.finalize_response(self, exit_code, callbacks)
  -- Destroy provider-specific sinks in extra
  destroy_sinks(self._response_buffer)
  -- Check buffered response if we haven't processed content successfully
  if self._response_buffer and not self._response_buffer.successful then
    self:_check_buffered_response(callbacks)
  end
  -- Destroy the response lines sink
  if self._response_buffer and self._response_buffer.lines_sink then
    self._response_buffer.lines_sink:destroy()
  end
end

--- Extract error message from response JSON data.
--- Base handles common patterns across APIs. Override to add provider-specific
--- error formats (e.g. Vertex's nested error structure).
---@param self flemma.provider.Base
---@param data table<string, any>
---@return string|nil
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

--- Try to import conversation from buffer lines in an external format.
--- Override to support importing from provider-specific formats (e.g. Anthropic
--- JSON exports). This is a static function — no instance state needed.
---@param lines string[]
---@return string|nil
function M.try_import_from_buffer(lines)
  return nil
end

--- Detect whether an error message indicates a context window overflow.
--- Override to add provider-specific patterns beyond the base set.
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

--- Detect whether an error message indicates an authentication failure.
--- Override to add provider-specific patterns (e.g. Vertex UNAUTHENTICATED).
--- Default returns false (most providers don't need reactive auth recovery).
---@param message string|nil The error message to check
---@return boolean
function M:is_auth_error(message)
  return false
end

--- Store parsed HTTP response headers from the current request.
---@param self flemma.provider.Base
---@param headers table<string, string[]>
function M:set_response_headers(headers)
  self._response_headers = headers
end

--- Detect whether an error message indicates a rate limit error.
--- Covers Anthropic ("rate limit"), OpenAI ("rate_limit_exceeded"),
--- Vertex ("resource exhausted"), and generic patterns.
---@param message string|nil The error message to check
---@return boolean
function M:is_rate_limit_error(message)
  if not message or type(message) ~= "string" then
    return false
  end
  local lower = message:lower()
  if lower:match("rate limit") then
    return true
  end
  if lower:match("rate_limit_exceeded") then
    return true
  end
  if lower:match("resource exhausted") then
    return true
  end
  if lower:match("too many requests") then
    return true
  end
  if lower:match("quota exceeded") then
    return true
  end
  if lower:match("overloaded") then
    return true
  end
  return false
end

---@param name string Lowercase header name
---@return boolean
local function is_rate_limit_header(name)
  return name == "retry-after" or name:match("ratelimit") ~= nil
end

--- Format rate limit details from HTTP response headers.
--- Returns a sorted, newline-separated string of relevant headers, or nil if none found.
---@param self flemma.provider.Base
---@return string|nil
function M:format_rate_limit_details()
  if not self._response_headers then
    return nil
  end
  local details = {}
  for name, values in pairs(self._response_headers) do
    if is_rate_limit_header(name) then
      for _, value in ipairs(values) do
        table.insert(details, name .. ": " .. value)
      end
    end
  end
  if #details > 0 then
    table.sort(details)
    return table.concat(details, "\n")
  end
  return nil
end

-- ============================================================================
-- Internal helpers — used by providers via self:method(), not meant to be overridden
-- ============================================================================

--- Normalize tool call ID for provider compatibility.
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

--- Parse a single SSE (Server-Sent Events) line
---@param line string The raw line from the stream
---@return flemma.provider.SSELine|nil
function M._parse_sse_line(line)
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
    if content == "[DONE]" then
      return { type = "done" }
    end

    return { type = "data", content = content }
  end

  -- Not an SSE line
  return nil
end

--- Create a new response buffer for accumulating non-processable lines
---@param self flemma.provider.Base
function M._new_response_buffer(self)
  self._response_buffer = {
    lines_sink = sink.create({ name = "provider/response-lines" }),
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
  self._response_buffer.lines_sink:write_lines({ line })
end

--- Mark that response processing has been successful
---@param self flemma.provider.Base
function M._mark_response_successful(self)
  if not self._response_buffer then
    self:_new_response_buffer()
  end
  self._response_buffer.successful = true
end

--- Check buffered response lines for errors.
--- Tries JSON parsing first; if that fails, surfaces the raw body as an error.
--- This handles non-JSON error responses (HTML pages, plain text) from proxies,
--- CDNs, or misconfigured endpoints.
---@param self flemma.provider.Base
---@param callbacks flemma.provider.Callbacks
---@return boolean
function M._check_buffered_response(self, callbacks)
  if not self._response_buffer then
    return false
  end

  local body = self._response_buffer.lines_sink:read()
  if body == "" then
    return false
  end

  -- Try JSON first — most API errors use structured JSON
  local ok, data = pcall(json.decode, body)
  if ok and type(data) == "table" then
    local msg = self:extract_json_response_error(data)
    if msg and callbacks.on_error then
      callbacks.on_error(msg)
      return true
    end
  end

  -- Non-JSON or unrecognized JSON structure — surface the raw body
  if callbacks.on_error then
    local MAX_BODY_LENGTH = 300
    local truncated = #body > MAX_BODY_LENGTH and body:sub(1, MAX_BODY_LENGTH) .. "..." or body
    -- Collapse whitespace for readability (HTML can be verbose)
    truncated = truncated:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    log.error("base._check_buffered_response(): Non-JSON or unrecognized error response: " .. truncated)
    callbacks.on_error("Unexpected API response: " .. truncated)
    return true
  end
  return false
end

--- Handle a non-SSE line by buffering it and attempting to parse as JSON error
---@param self flemma.provider.Base The provider instance
---@param line string The non-SSE line to handle
---@param callbacks flemma.provider.Callbacks Table of callback functions
---@return boolean handled True if the line was successfully parsed as an error
function M._handle_non_sse_line(self, line, callbacks)
  log.trace("base.handle_non_sse_line(): Received non-SSE line, buffering: " .. line)

  -- Buffer the line for later analysis
  self:_buffer_response_line(line)

  -- Try parsing as a direct JSON error response (for single-line errors)
  local ok, error_data = pcall(json.decode, line)
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

--- Signal content to the caller and mark response as successful
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

--- Check if any content has been accumulated in the response buffer
---@param self flemma.provider.Base The provider instance
---@return boolean has_content True if content has been accumulated
function M._has_content(self)
  return self._response_buffer.content and #self._response_buffer.content > 0
end

--- Check if the last character of accumulated content is a newline
---@param self flemma.provider.Base The provider instance
---@return boolean ends_with_newline True if content ends with newline
function M._content_ends_with_newline(self)
  local content = self._response_buffer.content or ""
  return content:sub(-1) == "\n"
end

-- ============================================================================
-- Shared emission helpers — used by providers to format response blocks
-- ============================================================================

--- Get the appropriate content prefix for the next block.
--- Returns "" if no content, "\n" if content ends with newline, "\n\n" otherwise.
---@param self flemma.provider.Base
---@return string prefix
function M._get_content_prefix(self)
  if not self:_has_content() then
    return ""
  end
  return self:_content_ends_with_newline() and "\n" or "\n\n"
end

--- Emit a formatted tool use block to the buffer.
--- Handles dynamic fence sizing, content prefix, and the standard format string.
---@param self flemma.provider.Base
---@param name string Tool name
---@param id string Tool call ID
---@param arguments_json string JSON string of tool arguments
---@param callbacks flemma.provider.Callbacks
function M._emit_tool_use_block(self, name, id, arguments_json, callbacks)
  local max_ticks = 0
  for ticks in arguments_json:gmatch("`+") do
    max_ticks = math.max(max_ticks, #ticks)
  end
  local fence = string.rep("`", math.max(3, max_ticks + 1))

  local prefix = self:_get_content_prefix()
  local formatted =
    string.format("%s**Tool Use:** `%s` (`%s`)\n\n%sjson\n%s\n%s\n", prefix, name, id, fence, arguments_json, fence)

  M._signal_content(self, formatted, callbacks)
  log.debug(self.metadata.name .. ".process_response_line(): Emitted tool_use block for " .. name)
end

--- Emit a thinking block to the buffer.
--- Handles content trimming, content prefix, signature attributes, and the fold-only empty tag case.
---@param self flemma.provider.Base
---@param content string Accumulated thinking text (may be empty)
---@param signature string|nil Signature value (provider-prepared)
---@param provider_prefix string Provider namespace for the signature attribute ("anthropic", "openai", "vertex")
---@param callbacks flemma.provider.Callbacks
function M._emit_thinking_block(self, content, signature, provider_prefix, callbacks)
  local stripped = vim.trim(content)
  local has_content = #stripped > 0
  local has_signature = signature ~= nil and signature ~= ""

  if not has_content and not has_signature then
    return
  end

  local prefix = self:_get_content_prefix()
  local open_tag
  if has_signature then
    open_tag = "<thinking " .. provider_prefix .. ':signature="' .. signature .. '">'
  else
    open_tag = "<thinking>"
  end

  local block
  if has_content then
    block = prefix .. open_tag .. "\n" .. stripped .. "\n</thinking>\n"
  else
    -- Signature but no content — emit open/close tag (enables folding)
    block = prefix .. open_tag .. "\n</thinking>\n"
  end

  M._signal_content(self, block, callbacks)
  log.debug(self.metadata.name .. "._emit_thinking_block(): Emitted thinking block")
end

--- Emit a redacted thinking block to the buffer.
---@param self flemma.provider.Base
---@param data string Opaque redacted thinking data
---@param callbacks flemma.provider.Callbacks
function M._emit_redacted_thinking(self, data, callbacks)
  local prefix = self:_content_ends_with_newline() and "" or "\n"
  local block = prefix .. "<thinking redacted>\n" .. data .. "\n</thinking>\n"
  M._signal_content(self, block, callbacks)
  log.debug(self.metadata.name .. "._emit_redacted_thinking(): Emitted redacted thinking block")
end

--- Warn the user about a truncated response and signal completion.
---@param self flemma.provider.Base
---@param callbacks flemma.provider.Callbacks
function M._warn_truncated(self, callbacks)
  log.warn(self.metadata.name .. ".process_response_line(): Response truncated (max_tokens)")
  vim.schedule(function()
    vim.notify("Flemma: Response truncated \u{2013} model reached max output tokens", vim.log.levels.WARN)
  end)
  if callbacks.on_response_complete then
    callbacks.on_response_complete()
  end
end

--- Signal that the response was blocked by content policy.
---@param self flemma.provider.Base
---@param reason string The block reason (e.g., "refusal", "SAFETY")
---@param callbacks flemma.provider.Callbacks
function M._signal_blocked(self, reason, callbacks)
  local message = "Response blocked by " .. self.metadata.display_name .. " (" .. reason .. ")"
  log.error(self.metadata.name .. ".process_response_line(): " .. message)
  if callbacks.on_error then
    callbacks.on_error(message)
  end
end

--- Default error response detection. Override in providers with different error shapes.
--- Default checks for `data.error` (covers OpenAI and Vertex).
---@param self flemma.provider.Base
---@param data table The parsed JSON response data
---@return boolean is_error True if the data represents an error response
function M._is_error_response(self, data)
  return data.error ~= nil
end

--- Inject synthetic error results for orphaned tool calls.
--- Providers supply a format function returning the provider-specific block shape.
---@param self flemma.provider.Base
---@param pending flemma.pipeline.UnresolvedTool[]|nil List of orphaned tool calls
---@param format_fn fun(orphan: flemma.pipeline.UnresolvedTool): table Returns a provider-specific synthetic result block
---@return table[]|nil results Array of formatted results, or nil if no orphans
function M._inject_orphan_results(self, pending, format_fn)
  if not pending or #pending == 0 then
    return nil
  end
  local results = {}
  for _, orphan in ipairs(pending) do
    table.insert(results, format_fn(orphan))
    log.debug(
      self.metadata.name
        .. ".build_request: Injected synthetic result for orphaned "
        .. orphan.name
        .. " ("
        .. orphan.id
        .. ")"
    )
  end
  return results
end

return M
