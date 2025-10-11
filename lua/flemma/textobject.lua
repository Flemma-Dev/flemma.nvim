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

  -- Collect thinking block positions to exclude them
  local thinking_blocks = {}
  if current_msg.segments and type(current_msg.segments) == "table" then
    for _, segment in ipairs(current_msg.segments) do
      if segment.kind == "thinking" and segment.position then
        table.insert(thinking_blocks, {
          start_line = segment.position.start_line,
          end_line = segment.position.end_line,
        })
      end
    end
  end

  local start_line = current_msg.position.start_line
  local end_line = current_msg.position.end_line

  -- Helper to check if a line is within a thinking block
  local function is_in_thinking_block(line_num)
    for _, block in ipairs(thinking_blocks) do
      if line_num >= block.start_line and line_num <= block.end_line then
        return true
      end
    end
    return false
  end

  -- Trim trailing empty lines for inner selection, skipping thinking blocks
  local inner_end = end_line
  while
    inner_end > start_line and (not lines[inner_end] or lines[inner_end] == "" or is_in_thinking_block(inner_end))
  do
    inner_end = inner_end - 1
  end

  -- Get the end column of the role type (e.g., "@You:") on the start line
  local role_type_end = lines[start_line]:find(":%s*") + 1
  while lines[start_line]:sub(role_type_end, role_type_end) == " " do
    role_type_end = role_type_end + 1
  end

  -- Check if there's content on the same line as the role
  local has_content_on_first_line = role_type_end <= #lines[start_line]

  -- Trim leading empty lines after role type for inner selection, skipping thinking blocks
  local inner_start_line = start_line
  local inner_start_col = role_type_end
  if not has_content_on_first_line then
    while
      inner_start_line < inner_end
      and (
        not lines[inner_start_line + 1]
        or lines[inner_start_line + 1]:match("^%s*$")
        or is_in_thinking_block(inner_start_line + 1)
      )
    do
      inner_start_line = inner_start_line + 1
    end
    inner_start_line = inner_start_line + 1
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
    -- Start at first non-whitespace content
    vim.cmd(string.format("normal! %dG%d|v", bounds.inner_start_line, bounds.inner_start_col))
    -- Move to last non-empty line
    vim.cmd(string.format("normal! %dGg_", bounds.inner_end))
  else -- around message
    -- Start at beginning of first line
    vim.cmd(string.format("normal! %dG0v", bounds.start_line))
    -- Move to end of last line
    vim.cmd(string.format("normal! %dGg_", bounds.inner_end))
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
