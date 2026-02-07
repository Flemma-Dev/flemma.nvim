--- Shared truncation utilities for tool outputs
--- Ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
---
--- Truncation is based on two independent limits — whichever is hit first wins:
--- - Line limit (default: 2000 lines)
--- - Byte limit (default: 50KB)
---
--- Never returns partial lines (except bash tail truncation edge case).
---@class flemma.tools.Truncate
local M = {}

M.MAX_LINES = 2000
M.MAX_BYTES = 50 * 1024 -- 50KB

---@class flemma.tools.TruncationOptions
---@field max_lines? integer Maximum number of lines (default: 2000)
---@field max_bytes? integer Maximum number of bytes (default: 50KB)

---@class flemma.tools.TruncationResult
---@field content string The truncated content
---@field truncated boolean Whether truncation occurred
---@field truncated_by "lines"|"bytes"|nil Which limit was hit
---@field total_lines integer Total number of lines in the original content
---@field total_bytes integer Total number of bytes in the original content
---@field output_lines integer Number of complete lines in the truncated output
---@field output_bytes integer Number of bytes in the truncated output
---@field last_line_partial boolean Whether the last line was partially truncated (tail only)
---@field first_line_exceeds_limit boolean Whether the first line exceeded the byte limit (head only)

---Format bytes as human-readable size
---@param bytes integer
---@return string
function M.format_size(bytes)
  if bytes < 1024 then
    return string.format("%dB", bytes)
  elseif bytes < 1024 * 1024 then
    return string.format("%.1fKB", bytes / 1024)
  else
    return string.format("%.1fMB", bytes / (1024 * 1024))
  end
end

---Truncate content from the head (keep first N lines/bytes).
---Suitable for file reads where you want to see the beginning.
---@param content string
---@param opts? flemma.tools.TruncationOptions
---@return flemma.tools.TruncationResult
function M.truncate_head(content, opts)
  opts = opts or {}
  local max_lines = opts.max_lines or M.MAX_LINES
  local max_bytes = opts.max_bytes or M.MAX_BYTES

  local total_bytes = #content
  local lines = vim.split(content, "\n", { plain = true })
  local total_lines = #lines

  -- Check if no truncation needed
  if total_lines <= max_lines and total_bytes <= max_bytes then
    return {
      content = content,
      truncated = false,
      truncated_by = nil,
      total_lines = total_lines,
      total_bytes = total_bytes,
      output_lines = total_lines,
      output_bytes = total_bytes,
      last_line_partial = false,
      first_line_exceeds_limit = false,
    }
  end

  -- Check if first line alone exceeds byte limit
  local first_line_bytes = #lines[1]
  if first_line_bytes > max_bytes then
    return {
      content = "",
      truncated = true,
      truncated_by = "bytes",
      total_lines = total_lines,
      total_bytes = total_bytes,
      output_lines = 0,
      output_bytes = 0,
      last_line_partial = false,
      first_line_exceeds_limit = true,
    }
  end

  -- Collect complete lines that fit
  local output = {}
  local output_bytes_count = 0
  local truncated_by = "lines"

  for i = 1, math.min(#lines, max_lines) do
    local line = lines[i]
    local line_bytes = #line + (i > 1 and 1 or 0) -- +1 for newline separator

    if output_bytes_count + line_bytes > max_bytes then
      truncated_by = "bytes"
      break
    end

    table.insert(output, line)
    output_bytes_count = output_bytes_count + line_bytes
  end

  -- If we exited due to line limit
  if #output >= max_lines and output_bytes_count <= max_bytes then
    truncated_by = "lines"
  end

  local output_content = table.concat(output, "\n")
  local final_output_bytes = #output_content

  return {
    content = output_content,
    truncated = true,
    truncated_by = truncated_by,
    total_lines = total_lines,
    total_bytes = total_bytes,
    output_lines = #output,
    output_bytes = final_output_bytes,
    last_line_partial = false,
    first_line_exceeds_limit = false,
  }
end

---Truncate content from the tail (keep last N lines/bytes).
---Suitable for bash output where you want to see the end (errors, final results).
---@param content string
---@param opts? flemma.tools.TruncationOptions
---@return flemma.tools.TruncationResult
function M.truncate_tail(content, opts)
  opts = opts or {}
  local max_lines = opts.max_lines or M.MAX_LINES
  local max_bytes = opts.max_bytes or M.MAX_BYTES

  local total_bytes = #content
  local lines = vim.split(content, "\n", { plain = true })
  local total_lines = #lines

  -- Check if no truncation needed
  if total_lines <= max_lines and total_bytes <= max_bytes then
    return {
      content = content,
      truncated = false,
      truncated_by = nil,
      total_lines = total_lines,
      total_bytes = total_bytes,
      output_lines = total_lines,
      output_bytes = total_bytes,
      last_line_partial = false,
      first_line_exceeds_limit = false,
    }
  end

  -- Work backwards from the end
  local output = {}
  local output_bytes_count = 0
  local truncated_by = "lines"
  local last_line_partial = false

  local i = #lines
  while i >= 1 and #output < max_lines do
    local line = lines[i]
    local line_bytes = #line + (#output > 0 and 1 or 0) -- +1 for newline separator

    if output_bytes_count + line_bytes > max_bytes then
      truncated_by = "bytes"
      -- Edge case: if we haven't added ANY lines yet and this line exceeds max_bytes,
      -- take the end of the line (partial)
      if #output == 0 then
        local truncated_line = line:sub(-max_bytes)
        table.insert(output, 1, truncated_line)
        output_bytes_count = #truncated_line
        last_line_partial = true
      end
      break
    end

    table.insert(output, 1, line)
    output_bytes_count = output_bytes_count + line_bytes
    i = i - 1
  end

  -- If we exited due to line limit
  if #output >= max_lines and output_bytes_count <= max_bytes then
    truncated_by = "lines"
  end

  local output_content = table.concat(output, "\n")
  local final_output_bytes = #output_content

  return {
    content = output_content,
    truncated = true,
    truncated_by = truncated_by,
    total_lines = total_lines,
    total_bytes = total_bytes,
    output_lines = #output,
    output_bytes = final_output_bytes,
    last_line_partial = last_line_partial,
    first_line_exceeds_limit = false,
  }
end

return M
