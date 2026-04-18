--- Shared buffer manipulation utilities
--- Provides common patterns for modifiable-guarded writes and single-line reads.
---@class flemma.utilities.Buffer
local M = {}

---Execute a function with the buffer temporarily set to modifiable.
---Saves the current `vim.bo[bufnr].modifiable` state, sets it to `true`,
---calls `fn()`, and restores the original state — even if `fn` errors.
---@generic T
---@param bufnr integer Buffer handle
---@param fn fun(): T Function to execute while modifiable is true
---@return T
---@overload fun(bufnr: integer, fn: fun())
function M.with_modifiable(bufnr, fn)
  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  local ok, result = pcall(fn)
  vim.bo[bufnr].modifiable = was_modifiable
  if not ok then
    error(result, 2)
  end
  return result
end

---Get a single line from the buffer by 1-based line number.
---@param bufnr integer Buffer handle
---@param lnum integer 1-based line number
---@return string
function M.get_line(bufnr, lnum)
  return vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
end

---Get the last line content and the total line count.
---Returns `("", 0)` for empty buffers.
---@param bufnr integer Buffer handle
---@return string content Last line content
---@return integer line_count Total number of lines (usable as 0-based append index)
function M.get_last_line(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return "", 0
  end
  local content = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]
  return content, line_count
end

---Get the gutter width (line number, sign column, fold column) for a window.
---Returns 0 when the window id is invalid.
---@param winid integer Window handle
---@return integer
function M.get_gutter_width(winid)
  local info = vim.fn.getwininfo(winid)
  if info and info[1] then
    return info[1].textoff
  end
  return 0
end

---@class flemma.utilities.buffer.ScratchOpts
---@field bufhidden? "wipe"|"hide" Default "wipe"
---@field modifiable? boolean Default true
---@field undolevels? integer Default -1 (disable undo)

---Create a scratch buffer with Flemma's standard options for floating-window content.
---@param opts? flemma.utilities.buffer.ScratchOpts
---@return integer bufnr
function M.create_scratch_buffer(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = opts.bufhidden or "wipe"
  vim.bo[bufnr].undolevels = opts.undolevels or -1
  if opts.modifiable == false then
    vim.bo[bufnr].modifiable = false
  end
  return bufnr
end

return M
