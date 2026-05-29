--- Preview formatting for Flemma UI
--- Shared formatters for fold text, tool indicators, and compact previews.
---@class flemma.ui.Preview
local M = {}

local query = require("flemma.ast.query")
local json = require("flemma.utilities.json")
local str = require("flemma.utilities.string")
local display = require("flemma.utilities.display")
local buffer = require("flemma.utilities.buffer")
local tools = require("flemma.tools")

---Normalise a raw format_preview return to a StructuredToolPreview.
---String returns become { detail = raw }. Table detail (string[]) is joined
---with double-space so callers always see detail as string|nil.
---Label is NEVER auto-promoted from input.label here — callers handle that separately.
---@param raw flemma.tools.ToolPreview
---@return flemma.StructuredToolPreview
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
local DEFAULT_MULTILINE_HEAD = 6
local DEFAULT_MULTILINE_TAIL = 6
local BASE_HL_GROUP = "FlemmaToolPreview"
local GENERIC_PREVIEW_INLINE_THRESHOLD = 120

---@class flemma.ui.HighlightContext
---@field text string The raw multi-line detail text (before prefix/indent/truncation)
---@field lang string The treesitter language name
---@field name_prefix string The tool name prefix (e.g., "bash: ") for line 1
---@field indent string The continuation indent (whitespace matching prefix width) for lines 2+

---Truncate a chunk array to fit within a display-width budget.
---Walks chunks until cumulative width exceeds max_width, splits the current
---chunk at the byte boundary, and appends the truncation marker.
---@param chunks {[1]: string, [2]: string}[] Array of {text, hl_group} tuples
---@param max_width integer Maximum display width for the result (including marker)
---@param marker? string Truncation marker (default: CONTENT_PREVIEW_TRUNCATION_MARKER)
---@return {[1]: string, [2]: string}[]
function M.truncate_chunks(chunks, max_width, marker)
  if max_width <= 0 then
    return {}
  end
  marker = marker or CONTENT_PREVIEW_TRUNCATION_MARKER
  local marker_width = str.strwidth(marker)

  local total_width = 0
  for _, chunk in ipairs(chunks) do
    total_width = total_width + str.strwidth(chunk[1])
  end
  if total_width <= max_width then
    return chunks
  end

  local target = max_width - marker_width
  if target <= 0 then
    return { { marker, chunks[1] and chunks[1][2] or BASE_HL_GROUP } }
  end

  local result = {}
  local used = 0

  for _, chunk in ipairs(chunks) do
    local chunk_width = str.strwidth(chunk[1])
    if used + chunk_width <= target then
      result[#result + 1] = chunk
      used = used + chunk_width
    else
      local remaining = target - used
      if remaining > 0 then
        local truncated = str.truncate(chunk[1], remaining, "")
        if truncated ~= "" then
          result[#result + 1] = { truncated, chunk[2] }
        end
      end
      result[#result + 1] = { marker, chunk[2] }
      return result
    end
  end

  return result
end

---Trim chunk arrays by logical-line budget (head + tail).
---When the line count exceeds head + tail, keeps the first `head` lines
---and the last `tail` lines with a truncation indicator in between.
---@param lines_chunks {[1]: string, [2]: string|string[]}[][] Array of per-line chunk arrays
---@param head integer Head line count
---@param tail integer Tail line count
---@return {[1]: string, [2]: string|string[]}[][] Trimmed chunk arrays
function M.trim_chunks(lines_chunks, head, tail)
  local line_count = #lines_chunks
  if line_count <= head + tail then
    return lines_chunks
  end

  local result = {}
  for i = 1, head do
    result[#result + 1] = lines_chunks[i]
  end

  local omitted = line_count - head - tail
  local indicator_text
  if omitted == 1 then
    indicator_text = "… 1 more line …"
  else
    indicator_text = "… " .. omitted .. " more lines …"
  end
  result[#result + 1] = { { indicator_text, BASE_HL_GROUP } }

  for i = line_count - tail + 1, line_count do
    result[#result + 1] = lines_chunks[i]
  end

  return result
end

---@type table<string, {text: string, text_hl: string}>
M.STATUS_DISPLAY = {
  error = { text = "(error) ", text_hl = "FlemmaToolResultError" },
  rejected = { text = "(rejected) ", text_hl = "FlemmaToolResultRejected" },
  denied = { text = "(denied) ", text_hl = "FlemmaToolResultDenied" },
  aborted = { text = "(aborted) ", text_hl = "FlemmaToolResultAborted" },
}

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

---Extract the label for a tool call without computing the full multiline preview.
---@param tool_name string
---@param input table<string, any>
---@return string|nil label
function M.format_tool_label(tool_name, input)
  local tool_def = tools.get(tool_name)
  if tool_def and tool_def.format_preview then
    local structured = normalize_preview(tool_def.format_preview(input, DEFAULT_MAX_LENGTH))
    return structured.label
  end
  return type(input.label) == "string" and input.label or nil
end

---Build a YAML-ish preview for a generic tool input (no custom format_preview).
---Each value is JSON-encoded (valid YAML since YAML is a JSON superset).
---When the inline flow mapping ({key: value, ...}) fits within available_width,
---returns single-line detail. Otherwise returns multi-line block mapping with
---highlight = { lang = "yaml" }.
---@param input table<string, any>
---@param available_width integer Width budget for the content (after tool name prefix)
---@return flemma.StructuredToolPreview
local function format_generic_preview(input, available_width)
  local keys = vim.tbl_keys(input)
  if #keys == 0 then
    return { detail = "{}" }
  end

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

  local ordered_keys = {}
  vim.list_extend(ordered_keys, scalar_keys)
  vim.list_extend(ordered_keys, table_keys)

  local entries = {}
  for _, key in ipairs(ordered_keys) do
    entries[#entries + 1] = key .. ": " .. json.encode(input[key])
  end

  local inline = "{" .. table.concat(entries, ", ") .. "}"
  if str.strwidth(inline) <= available_width then
    return { detail = inline, highlight = { lang = "yaml" } }
  end

  return {
    detail = table.concat(entries, "\n"),
    highlight = { lang = "yaml" },
  }
end

---Format a multi-line preview for a tool call (used by virt_line display).
---Returns an array of plain strings (one per display line) and the label separately.
---The tool name prefix appears on the first line only. Lines exceeding the cap
---are truncated to head + indicator + tail.
---@param tool_name string
---@param input table<string, any>
---@param max_length integer Maximum width per line
---@param opts? { head?: integer, tail?: integer }
---@return string[] lines
---@return string|nil label
---@return flemma.ui.HighlightContext|nil context
function M.format_tool_preview_multiline(tool_name, input, max_length, opts)
  local head = (opts and opts.head) or DEFAULT_MULTILINE_HEAD
  local tail = (opts and opts.tail) or DEFAULT_MULTILINE_TAIL
  local max_lines = head + 1 + tail

  local name_prefix = tool_name .. ": "

  local tool_def = tools.get(tool_name)
  local structured

  if tool_def and tool_def.format_preview then
    structured = normalize_preview(tool_def.format_preview(input, max_length))
  else
    local keys = vim.tbl_keys(input)
    if #keys == 0 then
      return { tool_name }, nil, nil
    end
    local available = math.min(max_length, GENERIC_PREVIEW_INLINE_THRESHOLD) - str.strwidth(name_prefix)
    structured = format_generic_preview(input, math.max(0, available))
    structured.label = type(input.label) == "string" and input.label or nil
  end

  local label = structured.label
  local detail = structured.detail --[[@as string|nil]]

  ---@type flemma.ui.HighlightContext|nil
  local highlight_context = nil
  if structured.highlight and structured.highlight.lang and detail and detail ~= "" then
    highlight_context = {
      text = detail,
      lang = structured.highlight.lang,
      name_prefix = name_prefix,
      indent = string.rep(" ", str.strwidth(name_prefix)),
    }
  end

  if not detail or detail == "" then
    if label then
      return { name_prefix .. label }, nil, nil
    end
    return { tool_name }, nil, nil
  end

  local raw_lines = vim.split(detail, "\n", { plain = true })

  if #raw_lines == 1 then
    local line = name_prefix .. raw_lines[1]
    return { str.truncate(line, max_length, CONTENT_PREVIEW_TRUNCATION_MARKER) }, label, highlight_context
  end

  local indent = string.rep(" ", str.strwidth(name_prefix))
  local continuation_width = max_length - str.strwidth(indent)

  local result = {}
  result[1] = str.truncate(name_prefix .. raw_lines[1], max_length, CONTENT_PREVIEW_TRUNCATION_MARKER)

  if #raw_lines <= max_lines then
    for i = 2, #raw_lines do
      result[i] = indent .. str.truncate(raw_lines[i], continuation_width, CONTENT_PREVIEW_TRUNCATION_MARKER)
    end
  else
    for i = 2, head do
      result[#result + 1] = indent .. str.truncate(raw_lines[i], continuation_width, CONTENT_PREVIEW_TRUNCATION_MARKER)
    end
    local omitted = #raw_lines - head - tail
    result[#result + 1] = indent .. "… " .. omitted .. " more lines …"
    for i = #raw_lines - tail + 1, #raw_lines do
      result[#result + 1] = indent .. str.truncate(raw_lines[i], continuation_width, CONTENT_PREVIEW_TRUNCATION_MARKER)
    end
  end

  return result, label, highlight_context
end

local SEGMENT_SEPARATOR = " | "

-- Minimum width (in characters) for a tool preview to be meaningful.
-- Below this, we show an overflow indicator instead of a truncated preview.
local MIN_TOOL_PREVIEW_WIDTH = 12

---@alias flemma.ui.preview.CoalescedEntry {kind: "text"|"tool_use"|"tool_result"|"job_result", value: string|nil, segment: flemma.ast.ToolUseSegment|flemma.ast.ToolResultSegment|flemma.ast.JobResultSegment|nil}

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
    elseif seg.kind == "job_result" then
      flush_text()
      table.insert(entries, {
        kind = "job_result",
        segment = seg --[[@as flemma.ast.JobResultSegment]],
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
---@return flemma.StructuredToolPreview
function M.get_tool_use_body(tool_name, input, available)
  local tool_def = tools.get(tool_name)

  if tool_def and tool_def.format_preview then
    local structured = normalize_preview(tool_def.format_preview(input, available))
    -- Collapse newlines in detail, then truncate detail to available
    if structured.detail then
      local detail = structured.detail --[[@as string]]
      detail = detail:gsub("\n", display.get_newline_char())
      structured.detail = str.truncate(detail, available, CONTENT_PREVIEW_TRUNCATION_MARKER)
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

---Resolve a tool_result's display data: the tool name (or "result" when the
---paired tool_use is missing), the paired tool_use's label, the status-marker
---display info, and the effective status. Shared by the message fold preview
---and the per-block fold text so this name/label/status resolution lives in one
---place; each caller does its own width-budgeted chunk assembly afterwards.
---@param result_seg flemma.ast.ToolResultSegment
---@param doc? flemma.ast.DocumentNode Resolves the paired tool_use and job-linked status
---@param tool_use_index? table<string, flemma.ast.ToolUseInfo> Prebuilt index; built from doc when omitted
---@return string name
---@return string|nil label
---@return {text: string, text_hl: string}|nil status_info
---@return flemma.ast.ToolStatus|nil effective_status
function M.resolve_tool_result_display(result_seg, doc, tool_use_index)
  tool_use_index = tool_use_index or (doc and query.build_tool_use_index(doc)) or {}
  local tool_info = tool_use_index[result_seg.tool_use_id]
  local effective_status = doc and query.effective_tool_result_status(result_seg, doc) or result_seg.status
  local status_info = effective_status and M.STATUS_DISPLAY[effective_status] or nil
  return tool_info and tool_info.name or "result", tool_info and tool_info.label, status_info, effective_status
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
        if detail then
          local detail_text = str.truncate(detail --[[@as string]], remaining, CONTENT_PREVIEW_TRUNCATION_MARKER)
          table.insert(entry_chunks, { detail_text, "FlemmaToolDetail" })
          entry_width = entry_width + str.strwidth(detail_text)
          remaining = remaining - str.strwidth(detail_text)

          local separator_width = str.strwidth(LABEL_DETAIL_SEPARATOR)
          if label and remaining > separator_width then
            local label_text =
              str.truncate(label --[[@as string]], remaining - separator_width, CONTENT_PREVIEW_TRUNCATION_MARKER)
            if label_text ~= "" then
              table.insert(entry_chunks, { LABEL_DETAIL_SEPARATOR .. label_text, "FlemmaToolLabel" })
              entry_width = entry_width + separator_width + str.strwidth(label_text)
            end
          end
        else
          local label_text = str.truncate(label --[[@as string]], remaining, CONTENT_PREVIEW_TRUNCATION_MARKER)
          table.insert(entry_chunks, { label_text, "FlemmaToolLabel" })
          entry_width = entry_width + str.strwidth(label_text)
        end
      end
    elseif entry.kind == "tool_result" then
      local result_seg = entry.segment --[[@as flemma.ast.ToolResultSegment]]
      local tool_name, tool_label, result_status_info = M.resolve_tool_result_display(result_seg, doc, tool_use_index)
      local width_for_result = available - remainder_reserve
      if width_for_result < MIN_TOOL_PREVIEW_WIDTH then
        add_overflow(#entries - i + 1)
        break
      end
      local name_result_width = str.strwidth(tool_name)
      local prefix_width = name_result_width + #": "
      if result_status_info then
        prefix_width = prefix_width + #result_status_info.text
      end

      table.insert(entry_chunks, { tool_name, "FlemmaToolName" })
      entry_width = name_result_width

      table.insert(entry_chunks, { ": ", "FlemmaFoldPreview" })
      entry_width = entry_width + #": "

      if result_status_info then
        table.insert(entry_chunks, { result_status_info.text, result_status_info.text_hl })
        entry_width = entry_width + #result_status_info.text
      end

      local remaining = width_for_result - prefix_width

      local body = M.format_content_preview(result_seg.content, remaining)
      if tool_label then
        if body ~= "" then
          local body_text = str.truncate(body, remaining, CONTENT_PREVIEW_TRUNCATION_MARKER)
          table.insert(entry_chunks, { body_text, "FlemmaFoldPreview" })
          entry_width = entry_width + str.strwidth(body_text)
          remaining = remaining - str.strwidth(body_text)

          local separator_width = str.strwidth(LABEL_DETAIL_SEPARATOR)
          if remaining > separator_width then
            local label_text = str.truncate(tool_label, remaining - separator_width, CONTENT_PREVIEW_TRUNCATION_MARKER)
            if label_text ~= "" then
              table.insert(entry_chunks, { LABEL_DETAIL_SEPARATOR .. label_text, "FlemmaToolLabel" })
              entry_width = entry_width + separator_width + str.strwidth(label_text)
            end
          end
        else
          local label_text = str.truncate(tool_label, remaining, CONTENT_PREVIEW_TRUNCATION_MARKER)
          table.insert(entry_chunks, { label_text, "FlemmaToolLabel" })
          entry_width = entry_width + str.strwidth(label_text)
        end
      else
        if body ~= "" or result_status_info then
          if body ~= "" then
            table.insert(entry_chunks, { body, "FlemmaFoldPreview" })
            entry_width = entry_width + str.strwidth(body)
          end
        end
      end
    elseif entry.kind == "job_result" then
      local job_seg = entry.segment --[[@as flemma.ast.JobResultSegment]]
      local job_status_info = job_seg.status and M.STATUS_DISPLAY[job_seg.status]
      local width_for_result = available - remainder_reserve
      if width_for_result < MIN_TOOL_PREVIEW_WIDTH then
        add_overflow(#entries - i + 1)
        break
      end
      local job_id_width = str.strwidth(job_seg.job_id)
      local prefix_width = job_id_width + #": "
      if job_status_info then
        prefix_width = prefix_width + #job_status_info.text
      end

      table.insert(entry_chunks, { job_seg.job_id, "FlemmaToolName" })
      entry_width = job_id_width

      table.insert(entry_chunks, { ": ", "FlemmaFoldPreview" })
      entry_width = entry_width + #": "

      if job_status_info then
        table.insert(entry_chunks, { job_status_info.text, job_status_info.text_hl })
        entry_width = entry_width + #job_status_info.text
      end

      local remaining = width_for_result - prefix_width
      local body = M.format_content_preview(job_seg.content, remaining)
      if body ~= "" then
        table.insert(entry_chunks, { body, "FlemmaFoldPreview" })
        entry_width = entry_width + str.strwidth(body)
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
