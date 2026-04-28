--- Navigation functions for Flemma chat interface
--- Provides cursor movement and file path resolution within chat buffers
---@class flemma.Navigation
local M = {}

local ast = require("flemma.ast")
local ctxutil = require("flemma.context")
local cursor = require("flemma.cursor")
local diagnostic_format = require("flemma.utilities.diagnostic")
local eval = require("flemma.templating.eval")
local path_util = require("flemma.utilities.path")
local templating = require("flemma.templating")
local log = require("flemma.logging")
local notify = require("flemma.notify")
local parser = require("flemma.parser")
local processor = require("flemma.processor")
local symbols = require("flemma.symbols")

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

---Resolve the file path for an include expression at a given position.
---Evaluates the expression with a path-only include() that resolves the
---target path without reading or compiling the file content. This avoids
---failures on non-template files that contain literal {{ }} documentation.
---When lnum/col are omitted, reads the current cursor position.
---@param bufnr integer Buffer number
---@param lnum? integer 1-indexed line number (defaults to cursor line)
---@param col? integer 1-indexed column number (defaults to cursor column)
---@return string|nil resolved_path Absolute file path, or nil if position is not on an include expression
function M.resolve_include_path(bufnr, lnum, col)
  if not lnum or not col then
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    lnum = lnum or cursor_pos[1] -- 1-indexed
    col = col or (cursor_pos[2] + 1) -- 0-indexed -> 1-indexed
  end
  log.trace("navigation: resolve_include_path at line=" .. lnum .. " col=" .. col .. " buf=" .. bufnr)

  local doc = parser.get_parsed_document(bufnr)
  local seg = ast.find_segment_at_position(doc, lnum, col)

  if not seg then
    log.trace("navigation: no segment at cursor position")
    return nil
  end

  if seg.kind ~= "expression" then
    log.trace("navigation: segment is " .. seg.kind .. ", not expression — skipping")
    return nil
  end

  log.debug("navigation: found expression segment, code=" .. seg.code)

  -- Build eval environment with frontmatter variables
  local context = ctxutil.from_buffer(bufnr)
  local fm = processor.evaluate_frontmatter(doc, context, bufnr)

  -- Report execution errors but skip validation failures — those are
  -- post-execution schema checks (e.g. "unknown tool 'calculator_async'"),
  -- not broken frontmatter code. User variables are already captured.
  for _, diag in ipairs(fm.diagnostics) do
    if diag.severity == "error" and not diag.validation then
      log.debug("navigation: frontmatter error: " .. (diag.error or "unknown"))
      local lines = { " " .. diagnostic_format.format_message(diag) }
      local loc = diagnostic_format.format_location(diag)
      if loc then
        table.insert(lines, "   " .. loc)
      end
      notify.warn(table.concat(lines, "\n"))
      break
    end
  end

  local env = templating.from_context(fm.context, bufnr)

  -- Override include() with a path-only version: resolve the target file path
  -- without reading, compiling, or executing the file content. Navigation only
  -- needs the path — not the rendered output. The real include() would fail on
  -- non-template files (e.g. README.md that documents {{ }} syntax literally).
  env.include = function(relative_path)
    if type(relative_path) ~= "string" then
      return nil
    end
    -- URN includes (e.g. urn:flemma:personality:*) are virtual — they resolve
    -- to rendered content, not a file on disk. The real include() handles URNs
    -- before path resolution; our path-only override must skip them too.
    if relative_path:sub(1, #eval.URN_PREFIX) == eval.URN_PREFIX then
      return nil
    end
    return { [symbols.SOURCE_PATH] = path_util.resolve(relative_path, env.__dirname) }
  end

  -- Evaluate the expression — our path-only include() returns a table tagged
  -- with SOURCE_PATH without touching the file content.
  local ok, result = pcall(eval.eval_expression, seg.code, env)
  if not ok then
    ---@type flemma.ast.Diagnostic
    local diag = type(result) == "table" and result.type and result
      or { type = "expression", severity = "error", error = tostring(result), expression = seg.code }
    diag.expression = diag.expression or seg.code
    diag.position = diag.position or seg.position
    log.debug("navigation: expression eval failed: " .. (diag.error or "unknown"))
    local lines = { " " .. diagnostic_format.format_message(diag) }
    local loc = diagnostic_format.format_location(diag)
    if loc then
      table.insert(lines, "   " .. loc)
    end
    notify.warn(table.concat(lines, "\n"))
    return nil
  end

  if type(result) == "table" and result[symbols.SOURCE_PATH] then
    log.debug("navigation: resolved include path=" .. result[symbols.SOURCE_PATH])
    return result[symbols.SOURCE_PATH]
  end

  log.trace("navigation: expression did not resolve to an include path")
  return nil
end

---includeexpr wrapper: returns resolved path or falls back to v:fname.
---Called via v:lua from the includeexpr buffer option.
---@return string
function M.resolve_include_path_expr()
  local bufnr = vim.api.nvim_get_current_buf()
  local resolved = M.resolve_include_path(bufnr)
  if not resolved then
    log.trace("navigation: includeexpr falling back to v:fname=" .. vim.v.fname)
  end
  return resolved or vim.v.fname
end

return M
