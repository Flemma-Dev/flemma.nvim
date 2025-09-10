--- HTTP client for Flemma
--- Handles all HTTP requests and transport mechanisms
local log = require("flemma.logging")

local M = {}

-- Registered fixtures by domain pattern (for testing)
local registered_fixtures = {}

-- Register a fixture for a specific domain pattern
function M.register_fixture(domain_pattern, fixture_path)
  log.debug(
    "client.register_fixture(): Registering fixture for domain pattern '" .. domain_pattern .. "': " .. fixture_path
  )
  registered_fixtures[domain_pattern] = fixture_path
end

-- Clear all registered fixtures
function M.clear_fixtures()
  log.debug("client.clear_fixtures(): Clearing all registered fixtures.")
  registered_fixtures = {}
end

-- Find fixture for a given endpoint
local function find_fixture_for_endpoint(endpoint)
  for pattern, fixture_path in pairs(registered_fixtures) do
    if endpoint:match(pattern) then
      log.debug(
        "client.find_fixture_for_endpoint(): Found fixture for endpoint '"
          .. endpoint
          .. "' matching pattern '"
          .. pattern
          .. "': "
          .. fixture_path
      )
      return fixture_path
    end
  end
  return nil
end

-- Create temporary file for request body (local helper function)
local function create_temp_file(request_body)
  -- Create temporary file for request body
  local tmp_file = os.tmpname()
  -- Handle both Unix and Windows paths
  local tmp_dir = tmp_file:match("^(.+)[/\\]")
  local tmp_name = tmp_file:match("[/\\]([^/\\]+)$")
  -- Use the same separator that was in the original path
  local sep = tmp_file:match("[/\\]")
  tmp_file = tmp_dir .. sep .. "flemma_" .. tmp_name

  local f = io.open(tmp_file, "w")
  if not f then
    return nil, "Failed to create temporary file"
  end

  f:write(vim.fn.json_encode(request_body))
  f:close()

  return tmp_file
end

-- Redact sensitive information from headers
local function redact_sensitive_header(header)
  -- Check if header contains sensitive information (API keys, tokens)
  if header:match("^Authorization:") or header:lower():match("%-key:") or header:lower():match("key:") then
    -- Extract the header name
    local header_name = header:match("^([^:]+):")
    if header_name then
      return header_name .. ": REDACTED"
    end
  end
  return header
end

-- Escape shell arguments properly
local function escape_shell_arg(arg)
  -- Basic shell escaping for arguments
  if arg:match("[%s'\"]") then
    -- If it contains spaces, quotes, etc., wrap in double quotes and escape internal double quotes
    return '"' .. arg:gsub('"', '\\"') .. '"'
  end
  return arg
end

-- Format curl command for logging
local function format_curl_command_for_log(cmd)
  local result = {}
  for i, arg in ipairs(cmd) do
    if i > 1 and cmd[i - 1] == "-H" then
      -- This is a header, redact sensitive information
      table.insert(result, escape_shell_arg(redact_sensitive_header(arg)))
    else
      -- Regular argument
      table.insert(result, escape_shell_arg(arg))
    end
  end
  return table.concat(result, " ")
end

-- Prepare curl command with common options
function M.prepare_curl_command(tmp_file, headers, endpoint, parameters)
  -- Retrieve timeout values from parameters, with defaults
  local connect_timeout = parameters and parameters.connect_timeout or 10
  local max_time = parameters and parameters.timeout or 120

  local cmd = {
    "curl",
    "-N", -- disable buffering
    "-s", -- silent mode
    "--connect-timeout",
    tostring(connect_timeout), -- connection timeout
    "--max-time",
    tostring(max_time), -- maximum time allowed
    "--retry",
    "0", -- disable retries
    "--http1.1", -- force HTTP/1.1 for better interrupt handling
    "-H",
    "Connection: close", -- request connection close
  }

  -- Add headers
  for _, header in ipairs(headers) do
    table.insert(cmd, "-H")
    table.insert(cmd, header)
  end

  -- Add request body
  table.insert(cmd, "-d")
  table.insert(cmd, "@" .. tmp_file)

  -- Add endpoint
  table.insert(cmd, endpoint)

  return cmd
end

--- Request options for send_request
---@class ClientRequestOptions
---@field request_body table The JSON request body to send
---@field headers string[] Array of HTTP headers
---@field endpoint string The API endpoint URL
---@field parameters table Provider parameters (for timeouts, model name, etc.)
---@field callbacks table Callback functions for handling responses
---@field process_response_line_fn? function Function to process each response line
---@field finalize_response_fn? function Function to finalize provider response processing
---@field reset_fn? function Optional function to reset provider state

-- Send request to API using curl or a test fixture
---@param opts ClientRequestOptions Request configuration
---@return number|nil job_id Job ID of the started request or nil on failure
function M.send_request(opts)
  -- Reset provider state before sending a new request
  if opts.reset_fn then
    opts.reset_fn()
  end

  -- Check for registered fixture for this endpoint
  local fixture_path = find_fixture_for_endpoint(opts.endpoint)

  -- If no fixture, we'll use the real API with headers provided by the provider
  -- The provider's get_request_headers() already handles API key validation

  -- Create temporary file for request body
  local tmp_file, err = create_temp_file(opts.request_body)
  if not tmp_file then
    if opts.callbacks.on_error then
      opts.callbacks.on_error(err or "Failed to create temporary file")
    end
    return nil
  end

  local cmd
  if fixture_path then
    -- Use 'cat' to stream the fixture file content
    cmd = { "cat", fixture_path }
    log.debug("send_request(): Using fixture for endpoint " .. opts.endpoint .. ": " .. fixture_path)
    log.debug("send_request(): ... $ " .. table.concat(cmd, " "))
  else
    -- Prepare curl command
    cmd = M.prepare_curl_command(tmp_file, opts.headers, opts.endpoint, opts.parameters)

    -- Log the API request details
    log.debug("send_request(): Sending request to endpoint: " .. opts.endpoint)
    local curl_cmd_log = format_curl_command_for_log(cmd)
    -- Replace the temporary file path with @request.json for easier reproduction
    curl_cmd_log = curl_cmd_log:gsub(vim.fn.escape(tmp_file, "%-%."), "request.json")
    log.debug("send_request(): ... $ " .. curl_cmd_log)
    log.debug("send_request(): ... @request.json <<< " .. vim.fn.json_encode(opts.request_body))
  end

  -- Start job
  local job_id = vim.fn.jobstart(cmd, {
    detach = true, -- Put process in its own group
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            -- Log the raw response line
            log.debug("send_request(): on_stdout: " .. line)

            -- Process the response line (single path)
            if opts.process_response_line_fn then
              opts.process_response_line_fn(line, opts.callbacks)
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            -- Log stderr output directly
            log.error("send_request(): stderr: " .. line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      -- Clean up temporary file
      os.remove(tmp_file)

      -- Log exit code
      log.info("send_request(): on_exit: Request completed with exit code: " .. tostring(code))

      -- Finalize provider response processing
      if opts.finalize_response_fn then
        opts.finalize_response_fn(code, opts.callbacks)
      end

      -- Handle common request completion callback
      if opts.callbacks.on_request_complete then
        opts.callbacks.on_request_complete(code)
      end
    end,
  })

  return job_id
end

-- Cancel ongoing request
function M.cancel_request(job_id)
  if not job_id then
    return false
  end

  -- Get the process ID
  local pid = vim.fn.jobpid(job_id)

  -- Send SIGINT first for clean connection termination
  if pid then
    vim.fn.system("kill -INT " .. pid)

    -- Give curl a moment to cleanup, then force kill if still running
    M.delayed_terminate(pid, job_id)
  else
    -- Fallback to jobstop if we couldn't get PID
    vim.fn.jobstop(job_id)
  end

  return true
end

-- Delayed process termination
function M.delayed_terminate(pid, job_id, delay)
  delay = delay or 500

  vim.defer_fn(function()
    if job_id then
      vim.fn.jobstop(job_id)
      if pid then
        vim.fn.system("kill -KILL " .. pid)
      end
    end
  end, delay)
end

return M
