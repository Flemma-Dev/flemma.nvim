--- Preview formatting for Flemma UI
--- Shared formatters for fold text, tool indicators, and compact previews.
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
  -- Collapse runs of 2+ spaces/tabs to a single space (but preserve ⤶ sequences)
  preview = preview:gsub("[ \t][ \t]+", " ")

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

local SEGMENT_SEPARATOR = " | "

-- Minimum width (in characters) for a tool preview to be meaningful.
-- Below this, we show an overflow indicator instead of a truncated preview.
local MIN_TOOL_PREVIEW_WIDTH = 12

---Format a compact preview string for a tool result.
---Shows the tool name with a content preview: `tool_name: content_preview`
---For errors: `tool_name: (error) content_preview`
---@param tool_name string
---@param content string
---@param is_error boolean
---@param max_length? integer Maximum total preview length (defaults to DEFAULT_MAX_LENGTH)
---@return string
function M.format_tool_result_preview(tool_name, content, is_error, max_length)
  max_length = max_length or DEFAULT_MAX_LENGTH

  local name_prefix = tool_name .. ": "
  if is_error then
    name_prefix = name_prefix .. "(error) "
  end
  local available = max_length - #name_prefix

  local body = M.format_content_preview(content, available)

  if body == "" then
    -- Trim trailing ": " when there's no content to show
    return tool_name .. (is_error and ": (error)" or "")
  end

  return name_prefix .. body
end

---Build a tool_use_id → tool_name lookup from all Assistant messages in a document.
---@param doc flemma.ast.DocumentNode
---@return table<string, string>
local function build_tool_name_map(doc)
  local map = {}
  for _, msg in ipairs(doc.messages) do
    if msg.role == "Assistant" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_use" then
          local tool_seg = seg --[[@as flemma.ast.ToolUseSegment]]
          map[tool_seg.id] = tool_seg.name
        end
      end
    end
  end
  return map
end

---@alias flemma.ui.preview.CoalescedEntry {kind: "text"|"tool_use"|"tool_result", value: string|nil, segment: flemma.ast.ToolUseSegment|flemma.ast.ToolResultSegment|nil}

---Coalesce raw AST segments into logical preview entries.
---The parser emits each line as a separate text segment; this merges consecutive
---text segments into a single entry so the fold preview treats them as one block.
---@param segments flemma.ast.Segment[]
---@return flemma.ui.preview.CoalescedEntry[]
local function coalesce_segments(segments)
  local entries = {}
  local text_accumulator = {}

  local function flush_text()
    if #text_accumulator > 0 then
      local merged = table.concat(text_accumulator)
      if merged:find("%S") then
        table.insert(entries, { kind = "text", value = merged })
      end
      text_accumulator = {}
    end
  end

  for _, seg in ipairs(segments) do
    if seg.kind == "text" then
      ---@cast seg flemma.ast.TextSegment
      table.insert(text_accumulator, seg.value)
    elseif seg.kind == "expression" then
      ---@cast seg flemma.ast.ExpressionSegment
      table.insert(text_accumulator, "{{ " .. seg.code .. " }}")
    elseif seg.kind == "tool_use" then
      flush_text()
      table.insert(entries, {
        kind = "tool_use",
        segment = seg --[[@as flemma.ast.ToolUseSegment]],
      })
    elseif seg.kind == "tool_result" then
      flush_text()
      table.insert(entries, {
        kind = "tool_result",
        segment = seg --[[@as flemma.ast.ToolResultSegment]],
      })
    end
    -- Skip thinking segments (they have their own level-2 fold)
  end

  flush_text()
  return entries
end

---Build a composite fold preview from a message's segments in buffer order.
---Consecutive text segments are merged; tool_use and tool_result segments produce
---tool previews. Entries are joined with ' | ' and truncated to fit max_length.
---@param msg flemma.ast.MessageNode
---@param max_length integer Available width for the preview body (excluding role prefix and suffix)
---@param doc? flemma.ast.DocumentNode Document for resolving tool names from tool_result IDs
---@return string
function M.format_message_fold_preview(msg, max_length, doc)
  local entries = coalesce_segments(msg.segments)

  if #entries == 0 then
    return ""
  end

  -- Build tool name lookup only when there are tool_result entries and a doc is available
  ---@type table<string, string>|nil
  local tool_name_map
  if doc then
    for _, entry in ipairs(entries) do
      if entry.kind == "tool_result" then
        tool_name_map = build_tool_name_map(doc)
        break
      end
    end
  end

  local parts = {}
  local used = 0

  for i, entry in ipairs(entries) do
    local remaining_entries = #entries - i
    local separator_cost = used > 0 and #SEGMENT_SEPARATOR or 0
    local available = max_length - used - separator_cost

    if available <= 0 then
      local overflow = #entries - i + 1
      if overflow == 1 then
        table.insert(parts, "(+1 tool)")
      else
        table.insert(parts, string.format("(+%d more)", overflow))
      end
      break
    end

    local remainder_reserve = 0
    if remaining_entries > 0 then
      remainder_reserve = #SEGMENT_SEPARATOR + #string.format("(+%d more)", remaining_entries)
    end

    local preview
    if entry.kind == "tool_use" then
      local tool_seg = entry.segment --[[@as flemma.ast.ToolUseSegment]]
      local width_for_tool = available - remainder_reserve
      if width_for_tool < MIN_TOOL_PREVIEW_WIDTH then
        local overflow = #entries - i + 1
        if overflow == 1 then
          table.insert(parts, "(+1 tool)")
        else
          table.insert(parts, string.format("(+%d more)", overflow))
        end
        break
      end
      preview = M.format_tool_preview(tool_seg.name, tool_seg.input, width_for_tool)
    elseif entry.kind == "tool_result" then
      local result_seg = entry.segment --[[@as flemma.ast.ToolResultSegment]]
      local tool_name = (tool_name_map and tool_name_map[result_seg.tool_use_id]) or "result"
      local width_for_result = available - remainder_reserve
      if width_for_result < MIN_TOOL_PREVIEW_WIDTH then
        local overflow = #entries - i + 1
        if overflow == 1 then
          table.insert(parts, "(+1 tool)")
        else
          table.insert(parts, string.format("(+%d more)", overflow))
        end
        break
      end
      preview = M.format_tool_result_preview(tool_name, result_seg.content, result_seg.is_error, width_for_result)
    else
      preview = M.format_content_preview(entry.value --[[@as string]], available - remainder_reserve)
    end

    if preview == "" then
      goto continue
    end

    if used > 0 then
      used = used + #SEGMENT_SEPARATOR
    end
    used = used + #preview
    table.insert(parts, preview)

    ::continue::
  end

  return table.concat(parts, SEGMENT_SEPARATOR)
end

return M
