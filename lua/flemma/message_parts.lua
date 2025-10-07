---@class GenericPart
---@field kind "text"|"image"|"pdf"|"text_file"|"unsupported_file"
---@field text string|nil For text parts
---@field mime_type string|nil MIME type for files
---@field data string|nil Base64-encoded data for binary files
---@field data_url string|nil Data URL with base64 encoding
---@field filename string|nil Original filename for file parts
---@field raw_filename string|nil Raw @file reference for unsupported files

local content_parser = require("flemma.content_parser")

local M = {}

---Parse message content into provider-agnostic parts
---
---This extracts text chunks, images, PDFs, and text files from a message string
---and returns them as generic parts that can be easily mapped to provider-specific
---wire formats. It also collects warnings about unreadable files.
---
---@param content string The message content to parse (may contain @file references)
---@param context table Context object for resolving file paths
---@return GenericPart[] parts The parsed content parts
---@return table[] warnings List of warnings about unprocessable files
function M.parse(content, context)
  local parts = {}
  local warnings = {}

  local content_parser_coro = content_parser.parse(content, context)
  while true do
    local status, chunk = coroutine.resume(content_parser_coro)
    if not status or not chunk then
      break
    end

    if chunk.type == "warnings" then
      -- Collect warnings for later notification
      for _, warning in ipairs(chunk.warnings) do
        table.insert(warnings, warning)
      end
    elseif chunk.type == "text" then
      if chunk.value and #chunk.value > 0 then
        table.insert(parts, {
          kind = "text",
          text = chunk.value,
        })
      end
    elseif chunk.type == "file" then
      if chunk.readable and chunk.content and chunk.mime_type then
        -- Categorize files by MIME type
        if
          chunk.mime_type == "image/jpeg"
          or chunk.mime_type == "image/png"
          or chunk.mime_type == "image/webp"
          or chunk.mime_type == "image/gif"
        then
          local encoded_data = vim.base64.encode(chunk.content)
          table.insert(parts, {
            kind = "image",
            mime_type = chunk.mime_type,
            data = encoded_data,
            data_url = "data:" .. chunk.mime_type .. ";base64," .. encoded_data,
            filename = chunk.filename,
          })
        elseif chunk.mime_type == "application/pdf" then
          local encoded_data = vim.base64.encode(chunk.content)
          table.insert(parts, {
            kind = "pdf",
            mime_type = chunk.mime_type,
            data = encoded_data,
            data_url = "data:application/pdf;base64," .. encoded_data,
            filename = chunk.filename,
          })
        elseif chunk.mime_type:sub(1, 5) == "text/" then
          table.insert(parts, {
            kind = "text_file",
            mime_type = chunk.mime_type,
            text = chunk.content,
            filename = chunk.filename,
          })
        else
          -- Unsupported MIME type - fallback to raw reference
          table.insert(parts, {
            kind = "unsupported_file",
            raw_filename = chunk.raw_filename or chunk.filename,
          })
        end
      else
        -- File not readable or missing data - fallback to raw reference
        table.insert(parts, {
          kind = "unsupported_file",
          raw_filename = chunk.raw_filename,
        })
      end
    end
  end

  return parts, warnings
end

---Notify user about file warnings
---
---@param provider_name string Name of the provider (e.g., "OpenAI", "Claude")
---@param warnings table[] List of warnings about unprocessable files
function M.notify_warnings(provider_name, warnings)
  if #warnings == 0 then
    return
  end

  local warning_messages = {}
  for _, warning in ipairs(warnings) do
    table.insert(warning_messages, warning.raw_filename .. ": " .. warning.error)
  end

  vim.notify(
    "Flemma ("
      .. provider_name
      .. "): Some @file references could not be processed:\n• "
      .. table.concat(warning_messages, "\n• "),
    vim.log.levels.WARN,
    { title = "Flemma File Warnings" }
  )
end

return M
