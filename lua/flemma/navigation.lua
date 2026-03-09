--- Navigation functions for Flemma chat interface
--- Provides cursor movement and file path resolution within chat buffers
---@class flemma.Navigation
local M = {}

local ast = require("flemma.ast")
local ctxutil = require("flemma.context")
local cursor = require("flemma.cursor")
local eval = require("flemma.eval")

local parser = require("flemma.parser")
local processor = require("flemma.processor")

---Find the next message marker in the buffer and move cursor there
---@return boolean found True if a next message was found and cursor moved
function M.find_next_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = parser.get_parsed_document(bufnr)

  for _, msg in ipairs(doc.messages) do
    if msg.position.start_line > cur_line then
      cursor.request_move(bufnr, { line = msg.position.start_line + 1, force = true, reason = "nav/next-message" })
      return true
    end
  end
  return false
end

---Find the previous message marker in the buffer and move cursor there
---@return boolean found True if a previous message was found and cursor moved
function M.find_prev_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = parser.get_parsed_document(bufnr)

  -- Iterate in reverse to find the previous message
  for i = #doc.messages, 1, -1 do
    local msg = doc.messages[i]
    local content_line = msg.position.start_line + 1
    if content_line < cur_line then
      cursor.request_move(bufnr, { line = content_line, force = true, reason = "nav/prev-message" })
      return true
    end
  end
  return false
end

---Resolve the file path for an include expression under the cursor.
---Evaluates the expression with a capturing include() stub that records
---the resolved path without performing I/O.
---@param bufnr integer Buffer number
---@return string|nil resolved_path Absolute file path, or nil if cursor is not on an include expression
function M.resolve_include_path(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1] -- 1-indexed
  local col = cursor[2] + 1 -- 0-indexed -> 1-indexed

  local doc = parser.get_parsed_document(bufnr)
  local seg = ast.find_segment_at_position(doc, lnum, col)

  if not seg or seg.kind ~= "expression" then
    return nil
  end

  -- Build eval environment with frontmatter variables
  local context = ctxutil.from_buffer(bufnr)
  local fm = processor.evaluate_frontmatter(doc, context)
  local env = ctxutil.to_eval_env(fm.context, bufnr)

  -- Install a capturing include() stub
  local captured_path = nil

  env.include = function(relative_path, _opts)
    if captured_path then
      -- Already captured — ignore subsequent calls
      return { emit = function() end }
    end

    local dirname = env.__dirname

    local target_path
    if dirname then
      target_path = vim.fs.normalize(dirname .. "/" .. relative_path)
    else
      target_path = relative_path
    end

    captured_path = target_path
    return { emit = function() end }
  end

  -- Evaluate the expression — pcall to handle errors gracefully
  pcall(eval.eval_expression, seg.code, env)

  return captured_path
end

---includeexpr wrapper: returns resolved path or falls back to v:fname.
---Called via v:lua from the includeexpr buffer option.
---@return string
function M.resolve_include_path_expr()
  local bufnr = vim.api.nvim_get_current_buf()
  local resolved = M.resolve_include_path(bufnr)
  return resolved or vim.v.fname
end

return M
