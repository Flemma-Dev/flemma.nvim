--- Usage and pricing functionality for Flemma plugin
--- Centralizes notification display for request and session costs

---@class flemma.Usage
local M = {}

--- Item priorities (higher = more important, shown first when space is scarce)
local PRIORITY = {
  MODEL_NAME = 90,
  REQUEST_COST = 80,
  CACHE_PERCENT = 75,
  PROVIDER_NAME = 70,
  SESSION_COST = 60,
  REQUEST_INPUT_TOKENS = 50,
  REQUEST_OUTPUT_TOKENS = 50,
  SESSION_REQUEST_COUNT = 40,
  THINKING_TOKENS = 35,
  SESSION_INPUT_TOKENS = 20,
  SESSION_OUTPUT_TOKENS = 20,
}

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

--- Build structured segments from request and session data for bar rendering
---@param request? flemma.session.Request Most recent completed request
---@param session? flemma.session.Session Session instance
---@return flemma.bar.Segment[]
function M.build_segments(request, session)
  local state = require("flemma.state")
  local config = state.get_config()
  local pricing_enabled = config.pricing.enabled

  local segments = {} ---@type flemma.bar.Segment[]

  -- Identity segment (from request)
  if request then
    local identity_items = {} ---@type flemma.bar.Item[]

    table.insert(identity_items, {
      key = "model_name",
      text = request.model,
      priority = PRIORITY.MODEL_NAME,
      highlight = { group = "FlemmaNotificationsModel" },
    })

    table.insert(identity_items, {
      key = "provider_name",
      text = "(" .. request.provider .. ")",
      priority = PRIORITY.PROVIDER_NAME,
      highlight = { group = "FlemmaNotificationsProvider" },
    })

    table.insert(segments, {
      key = "identity",
      items = identity_items,
    })
  end

  -- Request segment
  if request then
    local request_items = {} ---@type flemma.bar.Item[]

    -- Cost
    if pricing_enabled then
      table.insert(request_items, {
        key = "request_cost",
        text = string.format("$%.2f", request:get_total_cost()),
        priority = PRIORITY.REQUEST_COST,
        highlight = { group = "FlemmaNotificationsCost" },
      })
    end

    -- Cache percentage
    local cache_percent = M.calculate_cache_percent(request)
    if cache_percent ~= nil then
      local cache_text = "Cache " .. tostring(cache_percent) .. "%"
      local percent_str = tostring(cache_percent) .. "%"
      local group = cache_percent > 50 and "FlemmaNotificationsCacheGood" or "FlemmaNotificationsCacheBad"
      table.insert(request_items, {
        key = "cache_percent",
        text = cache_text,
        priority = PRIORITY.CACHE_PERCENT,
        highlight = {
          group = group,
          offset = #"Cache ", -- byte offset of the percentage within the text
          length = #percent_str,
        },
      })
    end

    -- Input tokens
    table.insert(request_items, {
      key = "request_input_tokens",
      text = "\xE2\x86\x91 " .. M.format_number(request.input_tokens),
      priority = PRIORITY.REQUEST_INPUT_TOKENS,
      highlight = { group = "FlemmaNotificationsTokens" },
    })

    -- Output tokens
    local total_output_tokens = request:get_total_output_tokens()
    table.insert(request_items, {
      key = "request_output_tokens",
      text = "\xE2\x86\x93 " .. M.format_number(total_output_tokens),
      priority = PRIORITY.REQUEST_OUTPUT_TOKENS,
      highlight = { group = "FlemmaNotificationsTokens" },
    })

    -- Thinking tokens
    if request.thoughts_tokens > 0 then
      table.insert(request_items, {
        key = "thinking_tokens",
        text = "\xE2\x97\x8B " .. M.format_number(request.thoughts_tokens),
        priority = PRIORITY.THINKING_TOKENS,
        highlight = { group = "FlemmaNotificationsTokens" },
      })
    end

    if #request_items > 0 then
      table.insert(segments, {
        key = "request",
        items = request_items,
        separator_highlight = "FlemmaNotificationsSeparator",
      })
    end
  end

  -- Session segment
  if session and session:get_request_count() > 0 then
    local session_items = {} ---@type flemma.bar.Item[]

    -- Session cost
    if pricing_enabled then
      table.insert(session_items, {
        key = "session_cost",
        text = string.format("$%.2f", session:get_total_cost()),
        priority = PRIORITY.SESSION_COST,
        highlight = { group = "FlemmaNotificationsCost" },
      })
    end

    -- Request count
    table.insert(session_items, {
      key = "session_request_count",
      text = "Requests " .. tostring(session:get_request_count()),
      priority = PRIORITY.SESSION_REQUEST_COUNT,
      highlight = { group = "FlemmaNotificationsTokens" },
    })

    -- Session input tokens
    table.insert(session_items, {
      key = "session_input_tokens",
      text = "\xE2\x86\x91 " .. M.format_number(session:get_total_input_tokens()),
      priority = PRIORITY.SESSION_INPUT_TOKENS,
      highlight = { group = "FlemmaNotificationsTokens" },
    })

    -- Session output tokens
    table.insert(session_items, {
      key = "session_output_tokens",
      text = "\xE2\x86\x93 " .. M.format_number(session:get_total_output_tokens()),
      priority = PRIORITY.SESSION_OUTPUT_TOKENS,
      highlight = { group = "FlemmaNotificationsTokens" },
    })

    table.insert(segments, {
      key = "session",
      label = "Session",
      label_highlight = "FlemmaNotificationsLabel",
      separator_highlight = "FlemmaNotificationsSeparator",
      items = session_items,
    })
  end

  return segments
end

--- Format usage information for notification bar display
--- Builds segments from request/session data and renders via the bar layout engine.
---@param request? flemma.session.Request Most recent completed request
---@param session? flemma.session.Session Session instance
---@param available_width integer Window width in display characters
---@return flemma.bar.RenderResult
function M.format_notification(request, session, available_width)
  local bar = require("flemma.bar")
  local segments = M.build_segments(request, session)
  if #segments == 0 then
    return { text = "", highlights = {} }
  end
  return bar.render(segments, available_width)
end

return M
