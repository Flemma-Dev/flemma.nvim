--- Notification bar layout engine
--- Takes structured segments and renders a single line with priority-based truncation
---@class flemma.Bar
local M = {}

--- Separator between segments: thin vertical bar with spaces
local SEPARATOR = " \xE2\x94\x82 " -- " │ " (U+2502, 5 bytes UTF-8)
local SEPARATOR_DISPLAY_WIDTH = 3 -- " │ " is 3 display chars

--- Prefix shown before all content: information source + space
local PREFIX = "\xE2\x84\xB9 " -- "ℹ " (U+2139, 3 bytes + 1 space)
local PREFIX_DISPLAY_WIDTH = 2 -- ℹ is 1 display col + 1 space

--- Exported constants for use by notifications module
M.PREFIX = PREFIX
M.PREFIX_DISPLAY_WIDTH = PREFIX_DISPLAY_WIDTH

---@class flemma.bar.Item
---@field key string Identifier (e.g. "model_name", "request_cost")
---@field text string Rendered text (e.g. "$0.00", "Cache 0%")
---@field priority integer Absolute priority (higher = more important)
---@field highlight? flemma.bar.ItemHighlight Optional highlight for part of this item

---@class flemma.bar.ItemHighlight
---@field group string Highlight group name
---@field offset? integer Byte offset within item text where highlight starts (default: 0, full text)
---@field length? integer Byte length of highlighted span (default: full item text length)

---@class flemma.bar.Segment
---@field key string Identifier ("identity", "request", "session")
---@field items flemma.bar.Item[] Items in display order
---@field label? string Fixed prefix shown when segment has visible items (e.g. "Session")
---@field label_highlight? string Highlight group for the label text
---@field separator_highlight? string Highlight group for the separator preceding this segment

---@class flemma.bar.RenderOpts
---@field skip_prefix? boolean When true, omit the ℹ prefix from rendered output

---@class flemma.bar.RenderResult
---@field text string Rendered line, right-padded with spaces to available_width
---@field highlights flemma.bar.RenderedHighlight[] Highlight spans with byte offsets relative to line start

---@class flemma.bar.RenderedHighlight
---@field group string Highlight group name
---@field col_start integer Byte offset from line start
---@field col_end integer Byte offset from line start (exclusive)

--- Calculate display width of an item's text
---@param text string
---@return integer
local function display_width(text)
  return vim.fn.strdisplaywidth(text)
end

--- Calculate the total display width of a rendered line from visible segments
--- Each segment's items are space-separated, segments are separated by SEPARATOR
---@param segments flemma.bar.Segment[] Segment definitions
---@param visible_keys table<string, boolean> Set of visible item keys
---@param item_widths? table<string, integer> Optional minimum display widths per item key
---@param skip_prefix? boolean When true, omit the prefix from width calculation
---@return integer width Total display width
local function calculate_line_width(segments, visible_keys, item_widths, skip_prefix)
  local total = 0
  local segment_count = 0

  for _, segment in ipairs(segments) do
    local segment_width = 0
    local item_count = 0

    -- Check if segment has visible items
    local has_visible = false
    for _, item in ipairs(segment.items) do
      if visible_keys[item.key] then
        has_visible = true
        break
      end
    end

    if not has_visible then
      goto continue_segment
    end

    if segment.label then
      segment_width = segment_width + display_width(segment.label) + 1 -- +1 for space after label
    end

    for _, item in ipairs(segment.items) do
      if visible_keys[item.key] then
        if item_count > 0 then
          segment_width = segment_width + 1 -- space between items
        end
        local w = display_width(item.text)
        if item_widths then
          w = math.max(w, item_widths[item.key] or 0)
        end
        segment_width = segment_width + w
        item_count = item_count + 1
      end
    end

    if item_count > 0 then
      if segment_count > 0 then
        total = total + SEPARATOR_DISPLAY_WIDTH
      end
      total = total + segment_width
      segment_count = segment_count + 1
    end

    ::continue_segment::
  end

  -- Account for prefix when there is any content (unless skipped)
  if segment_count > 0 and not skip_prefix then
    total = total + PREFIX_DISPLAY_WIDTH
  end

  return total
end

--- Build the rendered line text and collect highlight positions
---@param segments flemma.bar.Segment[]
---@param visible_keys table<string, boolean>
---@param available_width integer
---@param item_widths? table<string, integer> Optional minimum display widths per item key
---@param skip_prefix? boolean When true, omit the prefix from rendered output
---@return flemma.bar.RenderResult
local function build_line(segments, visible_keys, available_width, item_widths, skip_prefix)
  local parts = {} ---@type string[]
  local highlights = {} ---@type flemma.bar.RenderedHighlight[]
  local byte_offset = 0
  local segment_count = 0

  -- Check if there will be any visible content for the prefix
  local has_any_visible = false
  for _, segment in ipairs(segments) do
    for _, item in ipairs(segment.items) do
      if visible_keys[item.key] then
        has_any_visible = true
        break
      end
    end
    if has_any_visible then
      break
    end
  end

  if has_any_visible and not skip_prefix then
    table.insert(parts, PREFIX)
    byte_offset = byte_offset + #PREFIX
  end

  for _, segment in ipairs(segments) do
    local segment_parts = {} ---@type string[]
    local segment_highlights = {} ---@type { group: string, byte_start: integer, byte_end: integer }[]
    local item_count = 0

    -- Check if segment has any visible items
    local has_visible = false
    for _, item in ipairs(segment.items) do
      if visible_keys[item.key] then
        has_visible = true
        break
      end
    end

    if not has_visible then
      goto continue_segment
    end

    -- Add segment label
    if segment.label then
      table.insert(segment_parts, segment.label)
      if segment.label_highlight then
        table.insert(segment_highlights, {
          group = segment.label_highlight,
          byte_start = 0,
          byte_end = #segment.label,
        })
      end
    end

    -- Add visible items
    for _, item in ipairs(segment.items) do
      if visible_keys[item.key] then
        -- Pad item text to minimum width if item_widths specified
        local padded_text = item.text
        if item_widths then
          local min_width = item_widths[item.key] or 0
          local natural_width = display_width(item.text)
          if natural_width < min_width then
            padded_text = item.text .. string.rep(" ", min_width - natural_width)
          end
        end

        table.insert(segment_parts, padded_text)
        -- Track highlight if present
        if item.highlight then
          -- Calculate byte position: current segment parts joined by spaces
          local prefix_text = table.concat(segment_parts, " ")
          -- The highlight offset is relative to the item text, which ends at the end of prefix_text
          local item_start_in_segment = #prefix_text - #padded_text
          local hl_offset = item.highlight.offset or 0
          local hl_length = item.highlight.length or #padded_text
          table.insert(segment_highlights, {
            group = item.highlight.group,
            byte_start = item_start_in_segment + hl_offset,
            byte_end = item_start_in_segment + hl_offset + hl_length,
          })
        end
        item_count = item_count + 1
      end
    end

    if item_count > 0 or segment.label then
      -- Add separator between segments
      if segment_count > 0 then
        if segment.separator_highlight then
          table.insert(highlights, {
            group = segment.separator_highlight,
            col_start = byte_offset,
            col_end = byte_offset + #SEPARATOR,
          })
        end
        table.insert(parts, SEPARATOR)
        byte_offset = byte_offset + #SEPARATOR
      end

      local segment_text = table.concat(segment_parts, " ")
      table.insert(parts, segment_text)

      -- Adjust highlight byte offsets to be relative to line start
      for _, hl in ipairs(segment_highlights) do
        table.insert(highlights, {
          group = hl.group,
          col_start = byte_offset + hl.byte_start,
          col_end = byte_offset + hl.byte_end,
        })
      end

      byte_offset = byte_offset + #segment_text
      segment_count = segment_count + 1
    end

    ::continue_segment::
  end

  local line = table.concat(parts)

  -- Right-pad with spaces to fill available_width
  local current_display_width = display_width(line)
  if current_display_width < available_width then
    line = line .. string.rep(" ", available_width - current_display_width)
  end

  return { text = line, highlights = highlights }
end

--- Measure the natural display width of each item across all segments
---@param segments flemma.bar.Segment[]
---@return table<string, integer> widths Mapping of item key → display width
function M.measure_item_widths(segments)
  local widths = {} ---@type table<string, integer>
  for _, segment in ipairs(segments) do
    for _, item in ipairs(segment.items) do
      widths[item.key] = display_width(item.text)
    end
  end
  return widths
end

--- Render segments into a single notification bar line
--- Uses a greedy priority-fit algorithm: items are selected by priority but displayed in
--- fixed segment order. Equal-priority items are treated as a group (all or none).
---@param segments flemma.bar.Segment[] Segments in display order
---@param available_width integer Window width in display characters
---@param item_widths? table<string, integer> Optional minimum display widths per item key (for cross-notification alignment)
---@param opts? flemma.bar.RenderOpts Optional render options
---@return flemma.bar.RenderResult
function M.render(segments, available_width, item_widths, opts)
  -- Collect all items with their segment index for grouping
  ---@type { item: flemma.bar.Item, segment_index: integer }[]
  local all_items = {}
  for segment_index, segment in ipairs(segments) do
    for _, item in ipairs(segment.items) do
      table.insert(all_items, { item = item, segment_index = segment_index })
    end
  end

  -- Sort by priority descending
  table.sort(all_items, function(a, b)
    return a.item.priority > b.item.priority
  end)

  -- Group items by priority for tie-breaking
  ---@type table<integer, string[]>
  local priority_groups = {}
  for _, entry in ipairs(all_items) do
    local p = entry.item.priority
    if not priority_groups[p] then
      priority_groups[p] = {}
    end
    table.insert(priority_groups[p], entry.item.key)
  end

  -- Get unique priorities sorted descending
  local priorities = {} ---@type integer[]
  local seen_priorities = {} ---@type table<integer, boolean>
  for _, entry in ipairs(all_items) do
    if not seen_priorities[entry.item.priority] then
      table.insert(priorities, entry.item.priority)
      seen_priorities[entry.item.priority] = true
    end
  end

  -- Greedily add priority groups from highest to lowest
  local visible_keys = {} ---@type table<string, boolean>
  local skip_prefix = opts and opts.skip_prefix or false

  for _, priority in ipairs(priorities) do
    local keys = priority_groups[priority]

    -- Tentatively add all items in this priority group
    for _, key in ipairs(keys) do
      visible_keys[key] = true
    end

    -- Check if it fits
    local width = calculate_line_width(segments, visible_keys, item_widths, skip_prefix)
    if width > available_width then
      -- Remove this priority group — it doesn't fit
      for _, key in ipairs(keys) do
        visible_keys[key] = nil
      end
    end
  end

  return build_line(segments, visible_keys, available_width, item_widths, skip_prefix)
end

return M
