--- Base provider for Flemma
--- Defines the interface that all providers must implement
local log = require("flemma.logging")
local mime_util = require("flemma.mime")

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

-- Initialize the provider
function M.init(self)
  -- To be implemented by specific providers
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

-- Format messages for API (to be implemented by specific providers)
function M.format_messages(self, messages)
  -- To be implemented by specific providers
end

-- Create request body (to be implemented by specific providers)
function M.create_request_body(self, formatted_messages, system_message)
  -- To be implemented by specific providers
end

-- Get request headers (to be implemented by specific providers)
function M.get_request_headers(self)
  -- To be implemented by specific providers
end

-- Get API endpoint (to be implemented by specific providers)
function M.get_endpoint(self)
  -- To be implemented by specific providers
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

-- Reset provider state before a new request
-- This can be overridden by specific providers to reset their state
function M.reset(self)
  -- Base implementation does nothing by default
  -- Providers can override this to reset their specific state
end

--- Finalize response processing and handle provider-specific cleanup
--- This method is called when the HTTP request process completes, allowing providers
--- to perform cleanup tasks like processing any remaining buffered data.
---@param self table The provider instance
---@param exit_code number The HTTP request exit code (0 for success, non-zero for failure)
---@param callbacks ProviderCallbacks Table of callback functions for any remaining data processing
function M.finalize_response(self, exit_code, callbacks)
  if self.check_unprocessed_json then
    self:check_unprocessed_json(callbacks)
  end
end

-- Try to import from buffer lines (to be implemented by specific providers)
function M.try_import_from_buffer(self, lines)
  -- To be implemented by specific providers
  return nil
end

return M
