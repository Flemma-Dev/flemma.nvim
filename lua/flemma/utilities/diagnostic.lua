--- Shared diagnostic formatting for vim.notify and status view.
---@class flemma.utilities.Diagnostic
local M = {}

local ICON_ERROR = "⊘"
local ICON_WARN = "⚠"

---Return the icon for a diagnostic severity.
---@param severity "error"|"warning"
---@return string
function M.icon(severity)
  return severity == "error" and ICON_ERROR or ICON_WARN
end

---Return the highlight group for a diagnostic severity.
---@param severity "error"|"warning"
---@return string
function M.highlight(severity)
  return severity == "error" and "DiagnosticError" or "DiagnosticWarn"
end

---Format a source file path for display (relative to cwd).
---@param path string|nil
---@return string Empty string if path is nil or "N/A"
function M.format_path(path)
  if not path or path == "N/A" then
    return ""
  end
  return vim.fn.fnamemodify(path, ":.")
end

---Format a position as `:line` or `:line:col`.
---@param pos flemma.ast.Position|nil
---@return string Empty string if position is nil
function M.format_position(pos)
  if not pos then
    return ""
  end
  if pos.start_line then
    if pos.start_col then
      return string.format(":%d:%d", pos.start_line, pos.start_col)
    end
    return string.format(":%d", pos.start_line)
  end
  return ""
end

---Build the primary message line for a diagnostic (icon + type + message).
---@param d flemma.ast.Diagnostic
---@return string
function M.format_message(d)
  local message = d.error or "unknown error"

  -- File diagnostics: the filename IS the context, no type prefix needed
  if d.type == "file" then
    local ref = d.raw or d.filename
    if ref then
      message = ref .. ": " .. message
    end
  elseif d.type and d.type:sub(1, 7) == "custom:" then
    -- Custom diagnostic types use the label field for display
    local display_type = d.label or d.type:sub(8)
    message = display_type .. ": " .. message
  elseif d.type then
    message = d.type .. ": " .. message
  end

  return string.format("%s %s", M.icon(d.severity), message)
end

---Build the location detail line for a diagnostic.
---Returns nil if there's nothing meaningful to show.
---@param d flemma.ast.Diagnostic
---@return string|nil
function M.format_location(d)
  local parts = {}

  local path = M.format_path(d.source_file)
  if path ~= "" then
    table.insert(parts, path .. M.format_position(d.position))
  end

  if d.message_role then
    table.insert(parts, "in @" .. d.message_role)
  end

  if d.rewriter_name then
    table.insert(parts, "[" .. d.rewriter_name .. "]")
  end

  if d.expression then
    table.insert(parts, "{{ " .. vim.trim(d.expression) .. " }}")
  end

  if #parts == 0 then
    return nil
  end
  return table.concat(parts, " · ")
end

---Build include stack lines for file diagnostics.
---Returns an empty table if there's no include stack.
---@param d flemma.ast.Diagnostic
---@return string[]
function M.format_include_stack(d)
  if not d.include_stack or #d.include_stack == 0 then
    return {}
  end
  local lines = {}
  for _, stack_path in ipairs(d.include_stack) do
    table.insert(lines, "↓ " .. M.format_path(stack_path))
  end
  table.insert(lines, "→ " .. (d.raw or d.filename or ""))
  return lines
end

---Convert a ValidationFailure into a Diagnostic.
---Marks the result with `validation = true` so passive evaluation
---(evaluate_frontmatter_if_changed) can distinguish post-execution schema
---failures from code-execution errors when deciding whether to rollback.
---@param failure flemma.config.ValidationFailure
---@param defaults? { position?: flemma.ast.Position, source_file?: string }
---@return flemma.ast.Diagnostic
function M.from_validation_failure(failure, defaults)
  local message = failure.message
  if failure.path then
    message = failure.path .. ": " .. message
  end
  ---@type flemma.ast.Diagnostic
  local d = { type = "config", severity = "error", error = message, validation = true }
  if defaults then
    d.position = defaults.position
    d.source_file = defaults.source_file
  end
  return d
end

---Sort diagnostics: errors first, then warnings.
---Returns a new table (does not mutate the input).
---@param diagnostics flemma.ast.Diagnostic[]
---@return flemma.ast.Diagnostic[]
function M.sort(diagnostics)
  local sorted = {}
  for _, d in ipairs(diagnostics) do
    table.insert(sorted, d)
  end
  table.sort(sorted, function(a, b)
    if a.severity == b.severity then
      return false
    end
    return a.severity == "error"
  end)
  return sorted
end

return M
