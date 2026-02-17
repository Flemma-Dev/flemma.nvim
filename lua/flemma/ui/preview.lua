--- Preview and fold text generation for Flemma UI
--- Houses all formatting, preview generation, and fold text/level computation.
---@class flemma.ui.Preview
local M = {}

-- Constants for preview text
local MAX_CONTENT_PREVIEW_LINES = 10
local DEFAULT_MAX_LENGTH = 80
local CONTENT_PREVIEW_NEWLINE_CHAR = "⤶"
local CONTENT_PREVIEW_TRUNCATION_MARKER = "…"

---Get the available text area width for a window (total width minus signcolumn, numbercolumn, foldcolumn)
---Returns DEFAULT_MAX_LENGTH when the window is invalid (e.g., buffer not displayed or test environment).
---@param winid integer Window ID (-1 if buffer not in a window)
---@return integer
function M.get_text_area_width(winid)
  if winid == -1 then
    return DEFAULT_MAX_LENGTH
  end
  local total = vim.api.nvim_win_get_width(winid)
  local info = vim.fn.getwininfo(winid)
  if info and #info > 0 then
    return total - (info[1].textoff or 0)
  end
  return total
end

---Generate a truncated preview string from content
---@param content string
---@param max_length? integer Maximum preview length (defaults to DEFAULT_MAX_LENGTH)
---@return string
function M.format_content_preview(content, max_length)
  max_length = max_length or DEFAULT_MAX_LENGTH

  local trimmed = vim.trim(content)
  if #trimmed == 0 then
    return ""
  end

  -- Take up to MAX_CONTENT_PREVIEW_LINES lines, join with newline indicator
  local lines = {}
  local count = 0
  for line in (trimmed .. "\n"):gmatch("([^\n]*)\n") do
    count = count + 1
    if count > MAX_CONTENT_PREVIEW_LINES then
      break
    end
    table.insert(lines, vim.trim(line))
  end

  local preview = table.concat(lines, CONTENT_PREVIEW_NEWLINE_CHAR)
  preview = vim.trim(preview)

  if #preview > max_length then
    local truncated_length = max_length - #CONTENT_PREVIEW_TRUNCATION_MARKER
    if truncated_length < 0 then
      truncated_length = 0
    end
    preview = preview:sub(1, truncated_length) .. CONTENT_PREVIEW_TRUNCATION_MARKER
  end

  return preview
end

---Format a compact table value preview
---Arrays: [N items] or [1 item]; Objects: {key1, key2} or {key1, key2, +N more}
---@param value table
---@return string
local function format_table_value(value)
  if vim.tbl_isempty(value) then
    return "{}"
  end

  if vim.islist(value) then
    local count = #value
    return count == 1 and "[1 item]" or string.format("[%d items]", count)
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)
  local count = #keys

  if count == 0 then
    return "{}"
  elseif count <= 2 then
    return "{" .. table.concat(keys, ", ") .. "}"
  else
    return "{" .. keys[1] .. ", " .. keys[2] .. ", +" .. (count - 2) .. " more}"
  end
end

---Format the generic key-value preview body for a tool call (no name prefix)
---Produces: 'key1="val1", key2="val2"' (scalar keys first, sorted, truncated)
---@param input table<string, any>
---@param max_length? integer Maximum body length (defaults to DEFAULT_MAX_LENGTH)
---@return string
local function format_tool_preview_body(input, max_length)
  max_length = max_length or DEFAULT_MAX_LENGTH

  local keys = vim.tbl_keys(input)
  if #keys == 0 then
    return ""
  end

  -- Separate keys into scalar and table groups, sort each alphabetically
  local scalar_keys = {}
  local table_keys = {}
  for _, key in ipairs(keys) do
    if type(input[key]) == "table" then
      table.insert(table_keys, key)
    else
      table.insert(scalar_keys, key)
    end
  end
  table.sort(scalar_keys)
  table.sort(table_keys)

  -- Scalar keys first, then table keys
  local ordered_keys = {}
  vim.list_extend(ordered_keys, scalar_keys)
  vim.list_extend(ordered_keys, table_keys)

  local parts = {}
  for _, key in ipairs(ordered_keys) do
    local value = input[key]
    local formatted
    if type(value) == "string" then
      local display_value = value:gsub("\n", CONTENT_PREVIEW_NEWLINE_CHAR):gsub('"', '\\"')
      formatted = key .. '="' .. display_value .. '"'
    elseif type(value) == "table" then
      formatted = key .. "=" .. format_table_value(value)
    else
      formatted = key .. "=" .. tostring(value)
    end
    table.insert(parts, formatted)
  end

  local body = table.concat(parts, ", ")

  if #body > max_length then
    local truncated_length = max_length - #CONTENT_PREVIEW_TRUNCATION_MARKER
    if truncated_length < 0 then
      truncated_length = 0
    end
    body = body:sub(1, truncated_length) .. CONTENT_PREVIEW_TRUNCATION_MARKER
  end

  return body
end

---Format a compact preview string for a tool call
---Checks the tool registry for a custom format_preview function; falls back
---to the generic key-value body. Handles name prefix, newline collapsing,
---and truncation uniformly.
---@param tool_name string
---@param input table<string, any>
---@param max_length? integer Maximum total preview length (defaults to DEFAULT_MAX_LENGTH)
---@return string
function M.format_tool_preview(tool_name, input, max_length)
  max_length = max_length or DEFAULT_MAX_LENGTH

  local name_prefix = tool_name .. ": "
  local available = max_length - #name_prefix

  local registry = require("flemma.tools.registry")
  local tool_def = registry.get(tool_name)

  local body
  if tool_def and tool_def.format_preview then
    body = tool_def.format_preview(input, available)
    -- Collapse newlines for single-line display
    body = body:gsub("\n", CONTENT_PREVIEW_NEWLINE_CHAR)
  else
    local keys = vim.tbl_keys(input)
    if #keys == 0 then
      return tool_name
    end
    body = format_tool_preview_body(input, available)
  end

  local preview = name_prefix .. body

  if #preview > max_length then
    local truncated_length = max_length - #CONTENT_PREVIEW_TRUNCATION_MARKER
    if truncated_length < 0 then
      truncated_length = 0
    end
    preview = preview:sub(1, truncated_length) .. CONTENT_PREVIEW_TRUNCATION_MARKER
  end

  return preview
end

---Get the cached AST document for the current buffer
---@return flemma.ast.DocumentNode
local function get_document()
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = require("flemma.parser")
  return parser.get_parsed_document(bufnr)
end

---Find a thinking segment whose start or end line matches the given line number
---@param doc flemma.ast.DocumentNode
---@param lnum integer 1-indexed line number
---@return flemma.ast.ThinkingSegment|nil segment
---@return "start"|"end"|nil boundary Whether lnum is the start or end of the segment
local function find_thinking_at_line(doc, lnum)
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "thinking" and seg.position then
        ---@cast seg flemma.ast.ThinkingSegment
        if seg.position.start_line == lnum then
          return seg, "start"
        elseif seg.position.end_line == lnum then
          return seg, "end"
        end
      end
    end
  end
  return nil, nil
end

---Find a message whose start or end line matches the given line number
---@param doc flemma.ast.DocumentNode
---@param lnum integer 1-indexed line number
---@return flemma.ast.MessageNode|nil message
---@return "start"|"end"|nil boundary
local function find_message_at_line(doc, lnum)
  for _, msg in ipairs(doc.messages) do
    if msg.position.start_line == lnum then
      return msg, "start"
    elseif msg.position.end_line == lnum then
      return msg, "end"
    end
  end
  return nil, nil
end

---Get fold level for a line number
---@param lnum integer
---@return string
function M.get_fold_level(lnum)
  local doc = get_document()

  -- Level 2 folds: frontmatter (same level as thinking; they never overlap in position)
  local fm = doc.frontmatter
  if fm then
    if fm.position.start_line == lnum then
      return ">2"
    elseif fm.position.end_line == lnum then
      return "<2"
    end
  end

  -- Level 2 folds: <thinking>...</thinking>
  local _, thinking_boundary = find_thinking_at_line(doc, lnum)
  if thinking_boundary == "start" then
    return ">2"
  elseif thinking_boundary == "end" then
    return "<2"
  end

  -- Level 1 folds: messages
  -- Neovim's ">1" implicitly closes a previous level-1 fold, so single-line
  -- messages (start_line == end_line) and adjacent messages work correctly
  -- without explicit "<1" for every end_line.
  for _, msg in ipairs(doc.messages) do
    if msg.position.start_line == lnum then
      return ">1"
    elseif msg.position.end_line == lnum then
      return "<1"
    end
  end

  return "="
end

---Get fold text for display
---@return string
function M.get_fold_text()
  local foldstart_lnum = vim.v.foldstart
  local foldend_lnum = vim.v.foldend
  local total_fold_lines = foldend_lnum - foldstart_lnum + 1
  local doc = get_document()
  local text_width = M.get_text_area_width(vim.api.nvim_get_current_win())

  -- Check for frontmatter fold (level 2)
  local fm = doc.frontmatter
  if fm and fm.position.start_line == foldstart_lnum then
    -- Account for surrounding chrome: "```lang  ``` (N lines)"
    local suffix = string.format(" ``` (%d lines)", total_fold_lines)
    local prefix = "```" .. fm.language .. " "
    local preview = M.format_content_preview(fm.code, text_width - #prefix - #suffix)
    if preview ~= "" then
      return prefix .. preview .. suffix
    else
      return string.format("```%s (%d lines)", fm.language, total_fold_lines)
    end
  end

  -- Check if this is a thinking fold (level 2)
  local thinking_seg = find_thinking_at_line(doc, foldstart_lnum)
  if thinking_seg then
    if thinking_seg.redacted then
      return string.format("<thinking redacted> (%d lines)", total_fold_lines)
    end
    local provider = thinking_seg.signature and thinking_seg.signature.provider
    -- Account for surrounding chrome: "<thinking [provider]>  </thinking> (N lines)"
    local tag = provider and string.format("<thinking %s>", provider) or "<thinking>"
    local suffix = string.format(" </thinking> (%d lines)", total_fold_lines)
    local preview = M.format_content_preview(thinking_seg.content, text_width - #tag - #suffix - 1)
    if preview ~= "" then
      return tag .. " " .. preview .. suffix
    else
      local empty_tag = provider and string.format("<thinking %s/>", provider) or "<thinking/>"
      return string.format("%s (%d lines)", empty_tag, total_fold_lines)
    end
  end

  -- Message folds (level 1)
  local msg = find_message_at_line(doc, foldstart_lnum)
  if msg then
    local role_prefix = "@" .. msg.role .. ":"
    -- Account for surrounding chrome: "@Role:  (N lines)"
    local suffix = string.format(" (%d lines)", total_fold_lines)
    -- Get preview from the first text segment
    local content = ""
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "text" then
        content = seg.value
        break
      end
    end
    local preview = M.format_content_preview(content, text_width - #role_prefix - #suffix - 1)
    return role_prefix .. " " .. preview .. suffix
  end

  return vim.fn.getline(foldstart_lnum)
end

return M
