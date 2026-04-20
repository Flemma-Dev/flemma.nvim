--- Preview formatting for Flemma UI
--- Shared formatters for fold text, tool indicators, and compact previews.
---@class flemma.ui.Preview
local M = {}

local query = require("flemma.ast.query")
local str = require("flemma.utilities.string")
local display = require("flemma.utilities.display")
local buffer = require("flemma.utilities.buffer")
local tools = require("flemma.tools")

---Normalise a raw format_preview return to a StructuredToolPreview.
---String returns become { detail = raw }. Table detail (string[]) is joined
---with double-space so callers always see detail as string|nil.
---Label is NEVER auto-promoted from input.label here — callers handle that separately.
---@param raw flemma.tools.ToolPreview
---@return { label?: string, detail?: string }
local function normalize_preview(raw)
  if type(raw) == "string" then
    return { detail = raw }
  end
  local result = raw --[[@as flemma.StructuredToolPreview]]
  if type(result.detail) == "table" then
    result.detail = table.concat(result.detail --[[@as string[] ]], "  ")
  end
  return result
end

-- Constants for preview text
local MAX_CONTENT_PREVIEW_LINES = 10
local DEFAULT_MAX_LENGTH = 80
local CONTENT_PREVIEW_TRUNCATION_MARKER = "…"
local LABEL_DETAIL_SEPARATOR = " — "

---Get the available text area width for a window (total width minus signcolumn, numbercolumn, foldcolumn)
---Returns DEFAULT_MAX_LENGTH when the window is invalid (e.g., buffer not displayed or test environment).
---@param winid integer Window ID (-1 if buffer not in a window)
---@return integer
function M.get_text_area_width(winid)
  if winid == -1 then
    return DEFAULT_MAX_LENGTH
  end
  local total = vim.api.nvim_win_get_width(winid)
  return total - buffer.get_gutter_width(winid)
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

  local preview = table.concat(lines, display.get_newline_char())
  preview = vim.trim(preview)
  -- Collapse runs of 2+ spaces/tabs to a single space (but preserve newline indicator sequences)
  preview = preview:gsub("[ \t][ \t]+", " ")

  return str.truncate(preview, max_length, CONTENT_PREVIEW_TRUNCATION_MARKER)
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
function M.format_tool_preview_body(input, max_length)
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
      local display_value = value:gsub("\n", display.get_newline_char()):gsub('"', '\\"')
      formatted = key .. '="' .. display_value .. '"'
    elseif type(value) == "table" then
      formatted = key .. "=" .. format_table_value(value)
    else
      formatted = key .. "=" .. tostring(value)
    end
    table.insert(parts, formatted)
  end

  local body = table.concat(parts, ", ")

  return str.truncate(body, max_length, CONTENT_PREVIEW_TRUNCATION_MARKER)
end

---Format a compact preview string for a tool call (used by virt-line display).
---This is a plain-string context: no italic chunks. When both label and detail
---are present, renders as "name: label — detail" (em dash separator).
---@param tool_name string
---@param input table<string, any>
---@param max_length? integer Maximum total preview length (defaults to DEFAULT_MAX_LENGTH)
---@return string
function M.format_tool_preview(tool_name, input, max_length)
  max_length = max_length or DEFAULT_MAX_LENGTH

  local name_prefix = tool_name .. ": "
  local available = max_length - str.strwidth(name_prefix)

  local tool_def = tools.get(tool_name)

  local structured
  if tool_def and tool_def.format_preview then
    structured = normalize_preview(tool_def.format_preview(input, available))
    if structured.detail then
      structured.detail = structured.detail:gsub("\n", display.get_newline_char())
    end
  else
    local keys = vim.tbl_keys(input)
    if #keys == 0 then
      return tool_name
    end
    structured = {
      label = type(input.label) == "string" and input.label or nil,
      detail = M.format_tool_preview_body(input, available),
    }
  end

  -- Build body: "label — detail" or just label or just detail
  local label = structured.label
  local detail = structured.detail
  local body
  if label and detail and detail ~= "" then
    body = label .. " — " .. detail
  elseif label then
    body = label
  elseif detail and detail ~= "" then
    body = detail
  else
    return tool_name
  end

  local preview = name_prefix .. body
  return str.truncate(preview, max_length, CONTENT_PREVIEW_TRUNCATION_MARKER)
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
  local available = max_length - str.strwidth(name_prefix)

  local body = M.format_content_preview(content, available)

  if body == "" then
    -- Trim trailing ": " when there's no content to show
    return tool_name .. (is_error and ": (error)" or "")
  end

  return name_prefix .. body
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
    elseif seg.kind == "code" then
      ---@cast seg flemma.ast.CodeSegment
      table.insert(text_accumulator, "{% " .. seg.code .. " %}")
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

---Get the structured preview for a tool use (label + detail).
---Returns a StructuredToolPreview. Truncation of detail is applied here;
---label truncation is the caller's responsibility.
---@param tool_name string
---@param input table<string, any>
---@param available integer Available width after "name: " prefix
---@return { label?: string, detail?: string }
function M.get_tool_use_body(tool_name, input, available)
  local tool_def = tools.get(tool_name)

  if tool_def and tool_def.format_preview then
    local structured = normalize_preview(tool_def.format_preview(input, available))
    -- Collapse newlines in detail, then truncate detail to available
    if structured.detail then
      structured.detail = structured.detail:gsub("\n", display.get_newline_char())
      structured.detail = str.truncate(structured.detail, available, CONTENT_PREVIEW_TRUNCATION_MARKER)
    end
    return structured
  end

  -- Generic fallback: auto-detect input.label; use key-value body for detail
  local keys = vim.tbl_keys(input)
  if #keys == 0 then
    return {}
  end
  local label = type(input.label) == "string" and input.label or nil
  local detail_available = label and (available - str.strwidth(label) - 1) or available
  if detail_available < 0 then
    detail_available = 0
  end
  local detail = M.format_tool_preview_body(input, detail_available)
  return { label = label, detail = detail ~= "" and detail or nil }
end

---Build a composite fold preview from a message's segments in buffer order.
---Consecutive text segments are merged; tool_use and tool_result segments produce
---per-segment highlighted chunks. Entries are joined with ' | ' separators.
---@param msg flemma.ast.MessageNode
---@param max_length integer Available width for the preview body (excluding role prefix and suffix)
---@param doc? flemma.ast.DocumentNode Document for resolving tool names from tool_result IDs
---@param content_hl? string Highlight group for text entries (default: "FlemmaFoldPreview")
---@return {[1]:string, [2]:string}[]
function M.format_message_fold_preview(msg, max_length, doc, content_hl)
  content_hl = content_hl or "FlemmaFoldPreview"
  local entries = coalesce_segments(msg.segments)

  if #entries == 0 then
    return {}
  end

  -- Build tool_use index only when there are tool_result entries and a doc is available
  ---@type table<string, flemma.ast.ToolUseInfo>|nil
  local tool_use_index
  if doc then
    for _, entry in ipairs(entries) do
      if entry.kind == "tool_result" then
        tool_use_index = query.build_tool_use_index(doc)
        break
      end
    end
  end

  ---@type {[1]:string, [2]:string}[]
  local chunks = {}
  local used = 0

  ---Append an overflow indicator and stop iteration
  ---@param remaining integer Number of remaining entries
  local function add_overflow(remaining)
    if used > 0 then
      table.insert(chunks, { SEGMENT_SEPARATOR, "FlemmaFoldMeta" })
    end
    local text = remaining == 1 and "(+1 tool)" or string.format("(+%d more)", remaining)
    table.insert(chunks, { text, "FlemmaFoldMeta" })
  end

  for i, entry in ipairs(entries) do
    local remaining_entries = #entries - i
    local separator_cost = used > 0 and #SEGMENT_SEPARATOR or 0
    local available = max_length - used - separator_cost

    if available <= 0 then
      add_overflow(#entries - i + 1)
      break
    end

    local remainder_reserve = 0
    if remaining_entries > 0 then
      remainder_reserve = #SEGMENT_SEPARATOR + #string.format("(+%d more)", remaining_entries)
    end

    ---@type {[1]:string, [2]:string}[]
    local entry_chunks = {}
    local entry_width

    if entry.kind == "tool_use" then
      local tool_seg = entry.segment --[[@as flemma.ast.ToolUseSegment]]
      local width_for_tool = available - remainder_reserve
      if width_for_tool < MIN_TOOL_PREVIEW_WIDTH then
        add_overflow(#entries - i + 1)
        break
      end
      local name_width = str.strwidth(tool_seg.name)
      local after_name = width_for_tool - name_width - #": "
      local structured = M.get_tool_use_body(tool_seg.name, tool_seg.input, after_name)

      table.insert(entry_chunks, { tool_seg.name, "FlemmaToolName" })
      entry_width = name_width

      local label = structured.label
      local detail = structured.detail

      if label or detail then
        table.insert(entry_chunks, { ": ", "FlemmaToolName" })
        entry_width = entry_width + #": "

        local remaining = after_name
        if label then
          local label_text = str.truncate(label, remaining, CONTENT_PREVIEW_TRUNCATION_MARKER)
          table.insert(entry_chunks, { label_text, "FlemmaToolLabel" })
          entry_width = entry_width + str.strwidth(label_text)
          remaining = remaining - str.strwidth(label_text)

          local separator_width = str.strwidth(LABEL_DETAIL_SEPARATOR)
          if detail and remaining > separator_width then
            local detail_text = str.truncate(detail, remaining - separator_width, CONTENT_PREVIEW_TRUNCATION_MARKER)
            if detail_text ~= "" then
              table.insert(entry_chunks, { LABEL_DETAIL_SEPARATOR .. detail_text, "FlemmaToolDetail" })
              entry_width = entry_width + separator_width + str.strwidth(detail_text)
            end
          end
        else
          -- No label: show detail only
          local detail_text = str.truncate(detail --[[@as string]], remaining, CONTENT_PREVIEW_TRUNCATION_MARKER)
          table.insert(entry_chunks, { detail_text, "FlemmaToolDetail" })
          entry_width = entry_width + str.strwidth(detail_text)
        end
      end
    elseif entry.kind == "tool_result" then
      local result_seg = entry.segment --[[@as flemma.ast.ToolResultSegment]]
      local tool_info = tool_use_index and tool_use_index[result_seg.tool_use_id]
      local tool_name = tool_info and tool_info.name or "result"
      local tool_label = tool_info and tool_info.label
      local width_for_result = available - remainder_reserve
      if width_for_result < MIN_TOOL_PREVIEW_WIDTH then
        add_overflow(#entries - i + 1)
        break
      end
      local name_result_width = str.strwidth(tool_name)
      local prefix_width = name_result_width + #": "
      if result_seg.status == "error" then
        prefix_width = prefix_width + #"(error) "
      end

      table.insert(entry_chunks, { tool_name, "FlemmaToolName" })
      entry_width = name_result_width

      table.insert(entry_chunks, { ": ", "FlemmaFoldPreview" })
      entry_width = entry_width + #": "

      if result_seg.status == "error" then
        table.insert(entry_chunks, { "(error) ", "FlemmaToolResultError" })
        entry_width = entry_width + #"(error) "
      end

      local remaining = width_for_result - prefix_width

      if tool_label then
        local label_text = str.truncate(tool_label, remaining, CONTENT_PREVIEW_TRUNCATION_MARKER)
        table.insert(entry_chunks, { label_text, "FlemmaToolLabel" })
        entry_width = entry_width + str.strwidth(label_text)
        remaining = remaining - str.strwidth(label_text)

        local separator_width = str.strwidth(LABEL_DETAIL_SEPARATOR)
        if remaining > separator_width then
          local body = M.format_content_preview(result_seg.content, remaining - separator_width)
          if body ~= "" then
            table.insert(entry_chunks, { LABEL_DETAIL_SEPARATOR .. body, "FlemmaToolDetail" })
            entry_width = entry_width + separator_width + str.strwidth(body)
          end
        end
      else
        -- No label: show content only (backward-compat highlight)
        local body = M.format_content_preview(result_seg.content, remaining)
        if body ~= "" or result_seg.status == "error" then
          if body ~= "" then
            table.insert(entry_chunks, { body, "FlemmaFoldPreview" })
            entry_width = entry_width + str.strwidth(body)
          end
        end
      end
    else
      local text_preview = M.format_content_preview(entry.value --[[@as string]], available - remainder_reserve)
      if text_preview == "" then
        goto continue
      end
      table.insert(entry_chunks, { text_preview, content_hl })
      entry_width = str.strwidth(text_preview)
    end

    if #entry_chunks == 0 then
      goto continue
    end

    if used > 0 then
      table.insert(chunks, { SEGMENT_SEPARATOR, "FlemmaFoldMeta" })
      used = used + #SEGMENT_SEPARATOR
    end
    vim.list_extend(chunks, entry_chunks)
    used = used + entry_width

    ::continue::
  end

  return chunks
end

return M
