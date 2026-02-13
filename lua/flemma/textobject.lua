---@class flemma.Textobject
local M = {}

local parser = require("flemma.parser")

---@class flemma.textobject.MessageBounds
---@field start_line integer
---@field end_line integer
---@field inner_start_line integer
---@field inner_start_col integer
---@field inner_end integer

---Get the 0-indexed column where content starts after a role prefix (@Role: )
---@param role string
---@return integer
local function content_col(role)
  return #("@" .. role .. ": ")
end

---Build a line-level content map by walking positioned segments directly.
---@param msg flemma.ast.MessageNode
---@return table<integer, boolean> line_has_content Lines with non-whitespace content
---@return table<integer, boolean> thinking_lines Lines inside thinking blocks
local function build_line_content_map(msg)
  local line_has_content = {}
  local thinking_lines = {}

  for _, seg in ipairs(msg.segments) do
    if seg.kind == "thinking" and seg.position then
      for line = seg.position.start_line, seg.position.end_line do
        thinking_lines[line] = true
      end
    elseif seg.kind == "text" and seg.position then
      if vim.trim(seg.value) ~= "" then
        line_has_content[seg.position.start_line] = true
      end
    elseif seg.position and seg.position.end_line then
      -- tool_use, tool_result, expression — mark all lines as having content
      for line = seg.position.start_line, seg.position.end_line do
        line_has_content[line] = true
      end
    end
  end

  return line_has_content, thinking_lines
end

---Get the bounds of the current message
---@return flemma.textobject.MessageBounds|nil
local function get_message_bounds()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = parser.get_parsed_document(bufnr)

  -- Find the message containing the current line
  local current_msg = nil
  for _, msg in ipairs(doc.messages) do
    if msg.position.start_line <= cur_line and msg.position.end_line >= cur_line then
      current_msg = msg
      break
    end
  end

  if not current_msg then
    return nil
  end

  local start_line = current_msg.position.start_line
  local end_line = current_msg.position.end_line
  local line_has_content, thinking_lines = build_line_content_map(current_msg)

  -- Find inner_end: last line with content, not in a thinking block
  local inner_end = end_line
  while inner_end > start_line and (not line_has_content[inner_end] or thinking_lines[inner_end]) do
    inner_end = inner_end - 1
  end

  -- Find inner_start
  local role_col = content_col(current_msg.role)
  local has_content_on_first_line = line_has_content[start_line] or false

  local inner_start_line = start_line
  local inner_start_col = role_col + 1 -- 1-indexed for cursor positioning
  if not has_content_on_first_line then
    inner_start_line = start_line + 1
    while
      inner_start_line <= inner_end
      and (not line_has_content[inner_start_line] or thinking_lines[inner_start_line])
    do
      inner_start_line = inner_start_line + 1
    end
    inner_start_col = 1
  end

  return {
    start_line = start_line,
    end_line = end_line,
    inner_start_line = inner_start_line,
    inner_start_col = inner_start_col,
    inner_end = inner_end,
  }
end

---Text object implementation for messages
---@param type "i"|"a" Inner or around
function M.message_textobj(type)
  local bounds = get_message_bounds()
  if not bounds then
    return
  end

  local mode = vim.api.nvim_get_mode().mode
  local is_visual = mode:match("[vV]")

  -- Exit visual mode if we're in it
  if is_visual then
    vim.cmd("normal! v")
  end

  if type == "i" then -- inner message
    -- Start at first non-whitespace content
    vim.cmd(string.format("normal! %dG%d|v", bounds.inner_start_line, bounds.inner_start_col))
    -- Move to last non-empty line
    vim.cmd(string.format("normal! %dGg_", bounds.inner_end))
  else -- around message
    -- Select entire message linewise (including thinking blocks and trailing empty lines)
    vim.cmd(string.format("normal! %dGV%dG", bounds.start_line, bounds.end_line))
  end
end

---Setup function to create the text objects
---@param opts? { text_object?: string|false }
function M.setup(opts)
  opts = opts or {}
  -- Return early if text objects are disabled
  if opts.text_object == false then
    return
  end

  local key = opts.text_object or "m"

  -- Create text objects for inner message (i{key}) and around message (a{key})
  vim.keymap.set(
    { "o", "x" },
    "i" .. key,
    ':<C-u>lua require("flemma.textobject").message_textobj("i")<CR>',
    { silent = true, buffer = true }
  )
  vim.keymap.set(
    { "o", "x" },
    "a" .. key,
    ':<C-u>lua require("flemma.textobject").message_textobj("a")<CR>',
    { silent = true, buffer = true }
  )
end

return M
