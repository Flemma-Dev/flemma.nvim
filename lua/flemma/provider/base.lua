--- Base provider for Flemma
--- Defines the interface that all providers must implement
local log = require("flemma.logging")
local mime_util = require("flemma.mime")

-- Helper function to URL-decode a string
local function url_decode(str)
  if not str then
    return nil
  end
  str = string.gsub(str, "+", " ")
  str = string.gsub(str, "%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  return str
end

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

-- Process response line (to be implemented by specific providers)
function M.process_response_line(self, line, callbacks)
  -- To be implemented by specific providers
end

-- Reset provider state before a new request
-- This can be overridden by specific providers to reset their state
function M.reset(self)
  -- Base implementation does nothing by default
  -- Providers can override this to reset their specific state
end

-- Parse message content into chunks of text or file references using a coroutine.
-- This function returns a coroutine that, when resumed, yields chunks of the input string.
-- Chunks can be of type "text", "file", or "warnings".
--
-- "text" chunks have a `value` field containing the text segment.
-- "file" chunks represent `@./path/to/file.ext` references and include:
--   - `filename`: The cleaned path to the file.
--   - `raw_filename`: The originally matched filename string (e.g., "./path/to/file.ext").
--   - `content`: The binary content of the file if readable.
--   - `mime_type`: The detected MIME type of the file if readable.
--   - `readable`: A boolean indicating if the file was found and readable.
--   - `error`: An error message if the file was not readable or an error occurred.
-- "warnings" chunks contain a `warnings` array with objects containing:
--   - `filename`: The cleaned filename that caused the warning.
--   - `raw_filename`: The original filename reference.
--   - `error`: The error message describing the issue.
--
-- @param self The provider instance (not directly used in this static-like method but kept for consistency).
-- @param content_string string The string content to parse.
-- @return coroutine A coroutine that yields parsed chunks.
function M.parse_message_content_chunks(self, content_string)
  -- Inner function that implements the parsing logic for the coroutine.
  -- It iterates through the content_string, identifying text segments and
  -- file references, yielding them one by one.
  local function chunkify()
    if not content_string or content_string == "" then
      return
    end

    local current_pos = 1
    local warnings = {} -- Collect warnings to emit at the end
    -- Pattern matches "@" followed by "./" or "../", then any combination of "." or "/",
    -- and finally one or more non-whitespace characters, with optional ";type=mime/type".
    local file_pattern = "@(%.%.?%/[%.%/]*%S+)"

    while current_pos <= #content_string do
      local start_pos, end_pos, full_match = string.find(content_string, file_pattern, current_pos)

      if start_pos then
        -- Check if the match contains a MIME type override
        local raw_file_match, mime_type_override = string.match(full_match, "^([^;]+);type=(.+)$")
        if not raw_file_match then
          -- No MIME type override, use the full match as filename
          raw_file_match = full_match
          mime_type_override = nil
        else
          -- Remove trailing punctuation from MIME type override
          mime_type_override = mime_type_override:gsub("[%p]+$", "")
        end

        local type_part = mime_type_override and (";type=" .. mime_type_override) or nil

        -- Add preceding text if any
        local preceding_text = string.sub(content_string, current_pos, start_pos - 1)
        if #preceding_text > 0 then
          coroutine.yield({ type = "text", value = preceding_text })
        end

        -- Clean the matched filename (remove trailing punctuation)
        local filename_no_punctuation = raw_file_match:gsub("[%p]+$", "")
        -- URL-decode the filename
        local cleaned_filename = url_decode(filename_no_punctuation)

        -- Construct the full raw match for logging (includes type override if present)
        local full_raw_match = raw_file_match
        if type_part then
          full_raw_match = raw_file_match .. type_part
        end

        log.debug(
          'base.parse_message_content_chunks: Found @file reference (raw: "'
            .. full_raw_match
            .. '", no_punct: "'
            .. filename_no_punctuation
            .. '", cleaned: "'
            .. cleaned_filename
            .. '", mime_override: "'
            .. (mime_type_override or "none")
            .. '").'
        )

        if vim.fn.filereadable(cleaned_filename) == 1 then
          log.debug('base.parse_message_content_chunks: File exists and is readable: "' .. cleaned_filename .. '"')
          local mime_type, mime_err

          if mime_type_override then
            -- Use the overridden MIME type
            mime_type = mime_type_override
            log.debug('base.parse_message_content_chunks: Using overridden MIME type: "' .. mime_type .. '"')
          else
            -- Auto-detect MIME type
            mime_type, mime_err = mime_util.get_mime_type(cleaned_filename)
          end

          if mime_type then
            local file_handle, read_err = io.open(cleaned_filename, "rb")
            if file_handle then
              local file_content_binary = file_handle:read("*a")
              file_handle:close()

              if file_content_binary then
                coroutine.yield({
                  type = "file",
                  filename = cleaned_filename,
                  raw_filename = full_raw_match,
                  content = file_content_binary,
                  mime_type = mime_type,
                  readable = true,
                })
              else
                local error_msg = "Failed to read content"
                log.error(
                  'base.parse_message_content_chunks: Failed to read content from file: "' .. cleaned_filename .. '"'
                )
                -- Collect warning for later emission
                table.insert(warnings, {
                  filename = cleaned_filename,
                  raw_filename = full_raw_match,
                  error = error_msg,
                })
                coroutine.yield({
                  type = "file",
                  filename = cleaned_filename,
                  raw_filename = full_raw_match,
                  readable = false,
                  error = error_msg,
                })
              end
            else
              local error_msg = "Failed to open file: " .. (read_err or "unknown")
              log.error(
                'base.parse_message_content_chunks: Failed to open file for reading: "'
                  .. cleaned_filename
                  .. '" Error: '
                  .. (read_err or "unknown")
              )
              -- Collect warning for later emission
              table.insert(warnings, {
                filename = cleaned_filename,
                raw_filename = full_raw_match,
                error = error_msg,
              })
              coroutine.yield({
                type = "file",
                filename = cleaned_filename,
                raw_filename = full_raw_match,
                readable = false,
                error = error_msg,
              })
            end
          else
            local error_msg = "Failed to get MIME type: " .. (mime_err or "unknown")
            log.error(
              'base.parse_message_content_chunks: Failed to get MIME type for file: "'
                .. cleaned_filename
                .. '" Error: '
                .. (mime_err or "unknown")
            )
            -- Collect warning for later emission
            table.insert(warnings, {
              filename = cleaned_filename,
              raw_filename = raw_file_match,
              error = error_msg,
            })
            coroutine.yield({
              type = "file",
              filename = cleaned_filename,
              raw_filename = raw_file_match,
              readable = false,
              error = error_msg,
            })
          end
        else
          local error_msg = "File not found or not readable"
          log.warn(
            'base.parse_message_content_chunks: @file reference not found or not readable: "'
              .. cleaned_filename
              .. '". Collecting warning.'
          )
          -- Collect warning for later emission
          table.insert(warnings, {
            filename = cleaned_filename,
            raw_filename = full_raw_match,
            error = error_msg,
          })
          coroutine.yield({
            type = "file",
            filename = cleaned_filename,
            raw_filename = full_raw_match,
            readable = false,
            error = error_msg,
          })
        end
        current_pos = end_pos + 1
      else
        -- No more @file references found, add remaining text
        local remaining_text = string.sub(content_string, current_pos)
        if #remaining_text > 0 then
          coroutine.yield({ type = "text", value = remaining_text })
        end
        break -- Exit loop
      end
    end

    -- Emit warnings chunk at the end if we have any warnings
    if #warnings > 0 then
      log.debug("base.parse_message_content_chunks: Emitting warnings chunk with " .. #warnings .. " warnings")
      coroutine.yield({
        type = "warnings",
        warnings = warnings,
      })
    end
  end
  return coroutine.create(chunkify)
end

-- Try to import from buffer lines (to be implemented by specific providers)
function M.try_import_from_buffer(self, lines)
  -- To be implemented by specific providers
  return nil
end

return M
