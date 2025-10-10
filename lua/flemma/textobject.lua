local M = {}

local parser = require("flemma.parser")

-- Get the bounds of the current message
local function get_message_bounds()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = parser.get_parsed_document(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

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

  -- Trim trailing empty lines for inner selection
  local inner_end = end_line
  while inner_end > start_line and (not lines[inner_end] or lines[inner_end] == "") do
    inner_end = inner_end - 1
  end

  -- Get the end column of the role type (e.g., "@You:") on the start line
  local role_type_end = lines[start_line]:find(":%s*") + 1
  while lines[start_line]:sub(role_type_end, role_type_end) == " " do
    role_type_end = role_type_end + 1
  end

  return {
    start_line = start_line,
    end_line = end_line,
    inner_end = inner_end,
    role_type_end = role_type_end - 1,
  }
end

-- Text object implementations
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
    -- Start at first character after the role type
    vim.cmd(string.format("normal! %dG%d|v", bounds.start_line, bounds.role_type_end + 1))
    -- Move to last non-empty line
    vim.cmd(string.format("normal! %dG$", bounds.inner_end))
  else -- around message
    -- Start at beginning of first line
    vim.cmd(string.format("normal! %dG0v", bounds.start_line))
    -- Move to end of last line
    vim.cmd(string.format("normal! %dG$", bounds.end_line))
  end
end

-- Setup function to create the text objects
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
