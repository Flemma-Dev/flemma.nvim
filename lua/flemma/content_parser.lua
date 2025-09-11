--- Content parser for Flemma
--- Provides utilities for parsing message content including @file references
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
-- @param content_string string The string content to parse.
-- @return coroutine A coroutine that yields parsed chunks.
function M.parse(content_string)
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

        -- Clean the matched filename (remove trailing punctuation) and capture the stripped punctuation
        local filename_no_punctuation = raw_file_match:gsub("[%p]+$", "")
        local stripped_punctuation = raw_file_match:sub(#filename_no_punctuation + 1)
        -- URL-decode the filename
        local cleaned_filename = url_decode(filename_no_punctuation)

        -- Construct the full raw match for logging (includes type override if present)
        -- For raw_filename, we want the clean filename without trailing punctuation
        local full_raw_match = filename_no_punctuation
        if type_part then
          full_raw_match = filename_no_punctuation .. type_part
        end

        log.debug(
          'content_parser.parse: Found @file reference (raw: "'
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
          log.debug('content_parser.parse: File exists and is readable: "' .. cleaned_filename .. '"')
          local mime_type, mime_err

          if mime_type_override then
            -- Use the overridden MIME type
            mime_type = mime_type_override
            log.debug('content_parser.parse: Using overridden MIME type: "' .. mime_type .. '"')
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
                log.error('content_parser.parse: Failed to read content from file: "' .. cleaned_filename .. '"')
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
                'content_parser.parse: Failed to open file for reading: "'
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
              'content_parser.parse: Failed to get MIME type for file: "'
                .. cleaned_filename
                .. '" Error: '
                .. (mime_err or "unknown")
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
          local error_msg = "File not found or not readable"
          log.warn(
            'content_parser.parse: @file reference not found or not readable: "'
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
        -- Update current_pos to the start of any stripped punctuation
        -- If there was no punctuation stripped, this will be end_pos + 1 as before
        -- If there was punctuation stripped, this will point to the punctuation
        current_pos = start_pos + 1 + #filename_no_punctuation + (type_part and #type_part or 0)
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
      log.debug("content_parser.parse: Emitting warnings chunk with " .. #warnings .. " warnings")
      coroutine.yield({
        type = "warnings",
        warnings = warnings,
      })
    end
  end
  return coroutine.create(chunkify)
end

return M
