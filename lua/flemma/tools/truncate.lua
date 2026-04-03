--- Tool-aware truncation with overflow handling.
---
--- Re-exports all primitives from `flemma.utilities.truncate` and adds
--- `truncate_with_overflow` — truncate, save full output to a configurable
--- path, and return content with model-facing instructions.
---@class flemma.tools.Truncate : flemma.utilities.Truncate
local M = {}

local base = require("flemma.utilities.truncate")
local config_facade = require("flemma.config")
local format = require("flemma.utilities.format")
local variables = require("flemma.utilities.variables")

-- Re-export all primitives from the base module
M.truncate_head = base.truncate_head
M.truncate_tail = base.truncate_tail
M.truncate_line = base.truncate_line
M.format_size = base.format_size
M.MAX_LINES = base.MAX_LINES
M.MAX_BYTES = base.MAX_BYTES
M.MAX_LINE_CHARS = base.MAX_LINE_CHARS

---@class flemma.tools.TruncateOverflowOpts
---@field direction "head"|"tail"
---@field source string
---@field id? string Filled in by the bound wrapper on `ctx.truncate`
---@field bufnr? integer Filled in by the bound wrapper on `ctx.truncate`
---@field filename? string
---@field max_lines? integer
---@field max_bytes? integer
---@field output_path_format? string Override config (for testing)

---@class flemma.tools.TruncateOverflowResult
---@field content string
---@field overflow_path string|nil
---@field truncated boolean

---Normalize an absolute path into a flat filename-safe string.
---Strips the leading separator, then replaces all remaining separators with `-`.
---@param path string Absolute path
---@return string
local function normalize_path(path)
  local normalized = vim.fs.normalize(path)
  if normalized:sub(1, 1) == "/" then
    normalized = normalized:sub(2)
  end
  local result = normalized:gsub("/", "-")
  return result
end

---Resolve the output path format string into a concrete file path.
---@param format_str string The format string from config
---@param opts flemma.tools.TruncateOverflowOpts
---@return string
local function resolve_output_path(format_str, opts)
  local vars = {
    source = opts.source or "",
    id = opts.id or "",
    path = opts.filename and normalize_path(opts.filename) or "",
  }

  local expanded = format.expand(format_str, vars)
  expanded = variables.expand_inline(expanded)

  return expanded
end

---Write content to a file, creating parent directories as needed.
---@param path string
---@param content string
---@return boolean success
local function write_overflow_file(path, content)
  local dir = vim.fs.dirname(path)
  if dir and vim.fn.isdirectory(dir) == 0 then
    local ok = pcall(vim.fn.mkdir, dir, "p")
    if not ok then
      return false
    end
  end
  local f = io.open(path, "w")
  if not f then
    return false
  end
  f:write(content)
  f:close()
  return true
end

---Build the instruction notice appended to truncated content.
---@param trunc_result flemma.utilities.TruncationResult
---@param direction "head"|"tail"
---@param overflow_path string|nil
---@return string
local function build_notice(trunc_result, direction, overflow_path)
  local full_output_note = overflow_path and (". Full output: " .. overflow_path) or ""

  if trunc_result.first_line_exceeds_limit then
    return string.format(
      "[Output too large: %s in a single line, exceeds %s limit%s]",
      M.format_size(trunc_result.total_bytes),
      M.format_size(M.MAX_BYTES),
      full_output_note
    )
  end

  local start_line, end_line
  if direction == "tail" then
    start_line = trunc_result.total_lines - trunc_result.output_lines + 1
    end_line = trunc_result.total_lines
  else
    start_line = 1
    end_line = trunc_result.output_lines
  end

  -- last_line_partial only occurs with truncate_tail (never truncate_head)
  if trunc_result.last_line_partial then
    return string.format(
      "[Showing last %s of line %d%s]",
      M.format_size(trunc_result.output_bytes),
      end_line,
      full_output_note
    )
  end

  if trunc_result.truncated_by == "lines" then
    return string.format(
      "[Showing lines %d-%d of %d%s]",
      start_line,
      end_line,
      trunc_result.total_lines,
      full_output_note
    )
  end

  return string.format(
    "[Showing lines %d-%d of %d (%s limit)%s]",
    start_line,
    end_line,
    trunc_result.total_lines,
    M.format_size(M.MAX_BYTES),
    full_output_note
  )
end

---Truncate tool output with overflow handling.
---
---When truncation occurs, saves the full output to a file at a configurable
---path and appends model-facing instructions to the truncated content.
---@param text string Raw tool output
---@param opts flemma.tools.TruncateOverflowOpts
---@return flemma.tools.TruncateOverflowResult
function M.truncate_with_overflow(text, opts)
  local truncate_fn = opts.direction == "tail" and base.truncate_tail or base.truncate_head
  local trunc_opts = {} ---@type flemma.utilities.TruncationOptions
  if opts.max_lines then
    trunc_opts.max_lines = opts.max_lines
  end
  if opts.max_bytes then
    trunc_opts.max_bytes = opts.max_bytes
  end

  local result = truncate_fn(text, trunc_opts)

  if not result.truncated then
    return {
      content = result.content,
      overflow_path = nil,
      truncated = false,
    }
  end

  -- Resolve overflow file path
  local format_str = opts.output_path_format
  if not format_str then
    local config = config_facade.materialize(opts.bufnr)
    format_str = config.tools
      and config.tools.truncate
      and config.tools.truncate.output_path_format
      or "${TMPDIR:-/tmp}/flemma_#{source}_#{id}.txt"
  end

  local output_path = resolve_output_path(format_str, opts)

  -- Write full output to overflow file
  local overflow_path = nil ---@type string|nil
  if write_overflow_file(output_path, text) then
    overflow_path = output_path
  end

  local notice = build_notice(result, opts.direction, overflow_path)
  local content = result.first_line_exceeds_limit and notice or (result.content .. "\n\n" .. notice)

  return {
    content = content,
    overflow_path = overflow_path,
    truncated = true,
  }
end

return M
