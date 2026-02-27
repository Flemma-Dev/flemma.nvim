--- Usage and pricing functionality for Flemma plugin
--- Centralizes notification display for request and session costs

---@class flemma.Usage
local M = {}

---@class flemma.usage.FormatResult
---@field text string
---@field highlights flemma.usage.Highlight[]

---@class flemma.usage.Highlight
---@field line integer 0-indexed line number in the text
---@field col_start integer byte offset
---@field col_end integer byte offset
---@field group string highlight group name

--- Minimum number of middle-dot leaders between label and value
local MIN_LEADER_DOTS = 3
--- Spacing between columns (two spaces)
local COLUMN_GAP = "  "

--- Format a number with comma separators for thousands
---@param number number The number to format
---@return string formatted The comma-separated string (e.g. 20449 -> "20,449")
function M.format_number(number)
  local integer_part = tostring(math.floor(number))
  -- Reverse, insert commas every 3 digits, reverse back
  local reversed = integer_part:reverse()
  local with_commas = reversed:gsub("(%d%d%d)", "%1,")
  -- Remove trailing comma if present (when digit count is a multiple of 3)
  with_commas = with_commas:gsub(",$", "")
  return with_commas:reverse()
end

--- Calculate cache hit percentage for a request
--- Total input = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
--- because the Anthropic API reports input_tokens as only the non-cached portion.
---@param request flemma.session.Request The request to calculate cache percentage for
---@return integer|nil percent Cache hit percentage (0-100), or nil when total input is 0
function M.calculate_cache_percent(request)
  local total_input = request.input_tokens + request.cache_read_input_tokens + request.cache_creation_input_tokens
  if total_input == 0 then
    return nil
  end
  return math.floor(request.cache_read_input_tokens / total_input * 100)
end

--- Build a dotted-leader pair: "label ··· value" padded to target_width display characters
--- Uses U+00B7 MIDDLE DOT (2 bytes in UTF-8) as the leader character
---@param label string Left-aligned label text
---@param value string Right-aligned value text
---@param target_width integer Target display width in characters
---@return string pair The formatted leader pair
function M.build_leader_pair(label, value, target_width)
  local label_width = vim.fn.strdisplaywidth(label)
  local value_width = vim.fn.strdisplaywidth(value)
  -- 2 accounts for spaces flanking the dots: "label ··· value"
  local dot_count = target_width - label_width - value_width - 2
  if dot_count < MIN_LEADER_DOTS then
    dot_count = MIN_LEADER_DOTS
  end
  -- U+00B7 MIDDLE DOT is 2 bytes in UTF-8 (0xC2 0xB7)
  local dots = string.rep("\xC2\xB7", dot_count)
  return label .. " " .. dots .. " " .. value
end

--- Compute the minimum column width that fits a label and value with at least MIN_LEADER_DOTS dots
---@param label_width integer Display width of the label
---@param value_width integer Display width of the value
---@return integer width Minimum target_width for build_leader_pair
local function minimum_column_width(label_width, value_width)
  -- label + space + dots + space + value
  return label_width + 2 + MIN_LEADER_DOTS + value_width
end

--- Build the request detail line showing token counts
---@param request flemma.session.Request The request to format
---@param indent integer Number of leading spaces
---@return string line The formatted detail line
local function build_request_detail_line(request, indent)
  local total_output_tokens = request:get_total_output_tokens()
  local parts = {}
  table.insert(parts, "\xE2\x86\x91 " .. M.format_number(request.input_tokens))
  table.insert(parts, "\xE2\x86\x93 " .. M.format_number(total_output_tokens))
  if request.thoughts_tokens > 0 then
    table.insert(parts, "\xE2\x97\x8B " .. M.format_number(request.thoughts_tokens) .. " thinking")
  else
    -- Append "tokens" suffix when no thinking tokens are shown
    parts[#parts] = parts[#parts] .. " tokens"
  end
  return string.rep(" ", indent) .. table.concat(parts, "  ")
end

--- Build the session detail line showing aggregate token counts
---@param session flemma.session.Session The session to format
---@param indent integer Number of leading spaces
---@return string line The formatted detail line
local function build_session_detail_line(session, indent)
  local total_input = session:get_total_input_tokens()
  local total_output = session:get_total_output_tokens()
  local parts = {
    "\xE2\x86\x91 " .. M.format_number(total_input),
    "\xE2\x86\x93 " .. M.format_number(total_output),
  }
  return string.rep(" ", indent) .. table.concat(parts, "  ")
end

--- Format usage information for notification display
---@param request? flemma.session.Request Most recent completed request
---@param session? flemma.session.Session Session instance
---@return flemma.usage.FormatResult
function M.format_notification(request, session)
  local state = require("flemma.state")
  local config = state.get_config()
  local pricing_enabled = config.pricing.enabled

  local lines = {} ---@type string[]
  local highlights = {} ---@type flemma.usage.Highlight[]

  if request then
    -- Model line: ` `model` (provider) `
    table.insert(lines, " `" .. request.model .. "` (" .. request.provider .. ")")
    -- Blank separator
    table.insert(lines, "")

    local request_cost = pricing_enabled and string.format("$%.2f", request:get_total_cost()) or nil
    local cache_percent = M.calculate_cache_percent(request)

    -- Determine whether cache column is shown
    local show_cache = cache_percent ~= nil

    if pricing_enabled then
      -- With pricing: two-column primary line
      -- Column 1: "Request ··· $X.XX"
      local request_label = "Request"
      local request_value = request_cost --[[@as string]]
      local col1_min = minimum_column_width(#request_label, #request_value)

      -- Compute column 1 width: also consider session row if present
      local col1_width = col1_min
      if session and session:get_request_count() > 0 then
        local session_cost = string.format("$%.2f", session:get_total_cost())
        local session_col1_min = minimum_column_width(#"Session", #session_cost)
        if session_col1_min > col1_width then
          col1_width = session_col1_min
        end
      end

      local col1 = M.build_leader_pair(request_label, request_value, col1_width)
      local primary_line = " " .. col1

      if show_cache then
        local cache_value = tostring(cache_percent) .. "%"
        local cache_label = "Cache"
        local col2_width = minimum_column_width(#cache_label, #cache_value)
        -- Also consider session col2 width for consistency
        if session and session:get_request_count() > 0 then
          local requests_value = tostring(session:get_request_count())
          local requests_col2_min = minimum_column_width(#"Requests", #requests_value)
          if requests_col2_min > col2_width then
            col2_width = requests_col2_min
          end
        end
        local col2 = M.build_leader_pair(cache_label, cache_value, col2_width)
        primary_line = primary_line .. COLUMN_GAP .. col2

        -- Add cache highlight
        local cache_percent_str = tostring(cache_percent) .. "%"
        -- Find the byte position of the cache percentage in the primary line
        -- The cache value is at the end of col2, which is at the end of primary_line
        local line_byte_len = #primary_line
        local cache_percent_byte_len = #cache_percent_str
        local col_end = line_byte_len
        local col_start = col_end - cache_percent_byte_len

        local group = cache_percent > 50 and "FlemmaNotifyCacheGood" or "FlemmaNotifyCacheBad"
        table.insert(highlights, {
          line = #lines, -- 0-indexed: current line count = index of next line
          col_start = col_start,
          col_end = col_end,
          group = group,
        })
      end

      table.insert(lines, primary_line)

      -- Align ↑ under the cost value start in " Request ··· $X.XX"
      local detail_indent = 1 + col1_width - #request_value
      table.insert(lines, build_request_detail_line(request, detail_indent))
    else
      -- Without pricing: no cost column
      -- Primary line: "Request" then optionally "Cache ··· NN%"
      if show_cache then
        local cache_value = tostring(cache_percent) .. "%"
        local cache_label = "Cache"
        local col2_width = minimum_column_width(#cache_label, #cache_value)
        -- Consider session col2 width
        if session and session:get_request_count() > 0 then
          local requests_value = tostring(session:get_request_count())
          local requests_col2_min = minimum_column_width(#"Requests", #requests_value)
          if requests_col2_min > col2_width then
            col2_width = requests_col2_min
          end
        end
        local col2 = M.build_leader_pair(cache_label, cache_value, col2_width)
        local primary_line = " Request" .. COLUMN_GAP .. col2

        -- Add cache highlight
        local cache_percent_str = tostring(cache_percent) .. "%"
        local line_byte_len = #primary_line
        local cache_percent_byte_len = #cache_percent_str
        local col_end = line_byte_len
        local col_start = col_end - cache_percent_byte_len

        local group = cache_percent > 50 and "FlemmaNotifyCacheGood" or "FlemmaNotifyCacheBad"
        table.insert(highlights, {
          line = #lines,
          col_start = col_start,
          col_end = col_end,
          group = group,
        })

        table.insert(lines, primary_line)

        -- Detail indent: align under second column start (after "Request  ")
        local detail_indent = 1 + #"Request" + #COLUMN_GAP
        table.insert(lines, build_request_detail_line(request, detail_indent))
      else
        -- No cache, no pricing: just "Request" label with detail below
        table.insert(lines, " Request")
        local detail_indent = 1 + #"Request" + #COLUMN_GAP
        table.insert(lines, build_request_detail_line(request, detail_indent))
      end
    end
  end

  -- Session block
  if session and session:get_request_count() > 0 then
    -- Blank separator between request and session blocks
    if #lines > 0 then
      table.insert(lines, "")
    end

    local request_count_value = tostring(session:get_request_count())

    if pricing_enabled then
      local session_cost = string.format("$%.2f", session:get_total_cost())
      local session_label = "Session"

      -- Column 1 width: must be consistent with request block col1
      local col1_width = minimum_column_width(#session_label, #session_cost)
      if request then
        local request_cost_str = string.format("$%.2f", request:get_total_cost())
        local request_col1_min = minimum_column_width(#"Request", #request_cost_str)
        if request_col1_min > col1_width then
          col1_width = request_col1_min
        end
      end

      local col1 = M.build_leader_pair(session_label, session_cost, col1_width)

      -- Column 2: "Requests · NN"
      local requests_label = "Requests"
      local col2_width = minimum_column_width(#requests_label, #request_count_value)
      -- Consider request block col2 width for consistency
      if request then
        local cache_percent = M.calculate_cache_percent(request)
        if cache_percent ~= nil then
          local cache_value = tostring(cache_percent) .. "%"
          local cache_col2_min = minimum_column_width(#"Cache", #cache_value)
          if cache_col2_min > col2_width then
            col2_width = cache_col2_min
          end
        end
      end
      local col2 = M.build_leader_pair(requests_label, request_count_value, col2_width)

      table.insert(lines, " " .. col1 .. COLUMN_GAP .. col2)

      -- Detail line indent: same logic as request block
      local detail_indent = 1 + col1_width - #session_cost
      table.insert(lines, build_session_detail_line(session, detail_indent))
    else
      -- Without pricing: no cost column
      local requests_label = "Requests"
      local col2_width = minimum_column_width(#requests_label, #request_count_value)
      -- Consider request block col2 for consistency
      if request then
        local cache_percent = M.calculate_cache_percent(request)
        if cache_percent ~= nil then
          local cache_value = tostring(cache_percent) .. "%"
          local cache_col2_min = minimum_column_width(#"Cache", #cache_value)
          if cache_col2_min > col2_width then
            col2_width = cache_col2_min
          end
        end
      end
      local col2 = M.build_leader_pair(requests_label, request_count_value, col2_width)

      table.insert(lines, " Session" .. COLUMN_GAP .. col2)

      -- Detail indent: align under second column start
      local detail_indent = 1 + #"Session" + #COLUMN_GAP
      table.insert(lines, build_session_detail_line(session, detail_indent))
    end
  end

  return {
    text = table.concat(lines, "\n"),
    highlights = highlights,
  }
end

return M
