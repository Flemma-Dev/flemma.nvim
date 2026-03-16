--- Shared truncation utilities for tool outputs
--- Ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
---
--- Truncation is based on two independent limits — whichever is hit first wins:
--- - Line limit (default: 2000 lines)
--- - Byte limit (default: 50KB)
---
--- Never returns partial lines (except bash tail truncation edge case).
---@class flemma.utilities.Truncate
local M = {}

local str = require("flemma.utilities.string")

M.MAX_LINES = 2000
M.MAX_BYTES = 50 * 1024 -- 50KB
M.MAX_LINE_CHARS = 500

---Find the last byte position that ends a complete UTF-8 character at or before `pos`.
---Returns 0 when no complete character fits (pos < 1 or first char is wider than pos).
---@param text string
---@param pos integer Byte position (1-based)
---@return integer byte_pos Last safe byte position (0 means nothing fits)
local function utf8_floor(text, pos)
  if pos <= 0 then
    return 0
  end
  if pos >= #text then
    return #text
  end
  -- Walk backward from pos until we land on a UTF-8 character boundary.
  -- A continuation byte has the bit pattern 10xxxxxx (0x80..0xBF).
  local p = pos
  while p > 0 and text:byte(p) >= 0x80 and text:byte(p) <= 0xBF do
    p = p - 1
  end
  -- p now points at a lead byte (or we walked past the start).
  -- Determine the expected length of the character starting at p.
  if p < 1 then
    return 0
  end
  local lead = text:byte(p)
  local char_len
  if lead < 0x80 then
    char_len = 1
  elseif lead < 0xE0 then
    char_len = 2
  elseif lead < 0xF0 then
    char_len = 3
  else
    char_len = 4
  end
  -- If the full character fits within pos, keep it; otherwise back up before it.
  if p + char_len - 1 <= pos then
    return p + char_len - 1
  end
  return p - 1
end

---Find the first byte position that starts a complete UTF-8 character at or after `pos`.
---Returns #text + 1 when no complete character starts at or after pos.
---@param text string
---@param pos integer Byte position (1-based)
---@return integer byte_pos First safe byte position
local function utf8_ceil(text, pos)
  if pos <= 1 then
    return 1
  end
  if pos > #text then
    return #text + 1
  end
  -- Skip continuation bytes (10xxxxxx) to find the next lead byte.
  local p = pos
  while p <= #text and text:byte(p) >= 0x80 and text:byte(p) <= 0xBF do
    p = p + 1
  end
  return p
end

---@class flemma.utilities.TruncationOptions
---@field max_lines? integer Maximum number of lines (default: 2000)
---@field max_bytes? integer Maximum number of bytes (default: 50KB)

---@class flemma.utilities.TruncationResult
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
  return str.format_size(bytes)
end

---Truncate content from the head (keep first N lines/bytes).
---Suitable for file reads where you want to see the beginning.
---@param content string
---@param opts? flemma.utilities.TruncationOptions
---@return flemma.utilities.TruncationResult
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

---@class flemma.utilities.TruncateLineResult
---@field text string The (possibly truncated) line text
---@field truncated boolean Whether truncation occurred

---Truncate a single line to a maximum byte count.
---Uses character-aware slicing to avoid splitting multi-byte UTF-8 sequences.
---@param line string The line to truncate
---@param max_chars? integer Maximum bytes (default: MAX_LINE_CHARS)
---@return flemma.utilities.TruncateLineResult
function M.truncate_line(line, max_chars)
  max_chars = max_chars or M.MAX_LINE_CHARS
  if #line <= max_chars then
    return { text = line, truncated = false }
  end
  local suffix = "... [truncated]"
  local budget = max_chars - #suffix
  if budget < 1 then
    budget = 1
  end
  -- Find the last complete UTF-8 character that fits within the byte budget
  local byte_pos = utf8_floor(line, budget)
  return { text = line:sub(1, byte_pos) .. suffix, truncated = true }
end

---Truncate content from the tail (keep last N lines/bytes).
---Suitable for bash output where you want to see the end (errors, final results).
---@param content string
---@param opts? flemma.utilities.TruncationOptions
---@return flemma.utilities.TruncationResult
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
      -- take the end of the line (partial), aligned to a UTF-8 boundary
      if #output == 0 then
        local raw_start = #line - max_bytes + 1
        local safe_start = utf8_ceil(line, raw_start)
        local truncated_line = line:sub(safe_start)
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
