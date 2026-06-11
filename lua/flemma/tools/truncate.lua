--- Tool-aware truncation with overflow handling.
---
--- Re-exports all primitives from `flemma.utilities.truncate` and adds
--- `truncate_with_overflow` — truncate, delegate overflow writes to the
--- store module, and return content with model-facing instructions.
---@class flemma.tools.Truncate : flemma.utilities.Truncate
local M = {}

local base = require("flemma.utilities.truncate")
local notify = require("flemma.notify")
local store = require("flemma.tools.store")

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
---@field source? string Defaults to "tool" via the bound wrapper on `ctx.truncate`
---@field id? string Filled in by the bound wrapper on `ctx.truncate`
---@field bufnr? integer Filled in by the bound wrapper on `ctx.truncate`
---@field filename? string
---@field max_lines? integer
---@field max_bytes? integer
---@field store_opts? { __filename?: string, __dirname?: string, name?: string, path_format?: string, unnamed_path_format?: string, backup?: string|false }

---@class flemma.tools.TruncateOverflowResult
---@field content string
---@field overflow_path string|nil
---@field truncated boolean

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
---When truncation occurs, delegates full-output write to the store module
---and appends model-facing instructions to the truncated content.
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

  local overflow_path ---@type string|nil
  if opts.store_opts then
    local store_path, store_err = store.materialize({
      __filename = opts.store_opts.__filename,
      __dirname = opts.store_opts.__dirname,
      source = opts.source or "tool",
      name = opts.store_opts.name,
      id = opts.id or "",
      path_format = opts.store_opts.path_format,
      unnamed_path_format = opts.store_opts.unnamed_path_format,
      bufnr = opts.bufnr,
      content = text,
      materialize_enabled = true,
      truncated = true,
      backup = opts.store_opts.backup,
    })
    if store_err then
      notify.warn("Could not save full tool output: " .. store_err)
    end
    overflow_path = store_path
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
