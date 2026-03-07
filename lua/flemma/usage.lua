--- Usage and pricing functionality for Flemma plugin
--- Centralizes notification display for request and session costs

---@class flemma.Usage
local M = {}

--- Item priorities (higher = more important, shown first when space is scarce)
local PRIORITY = {
  MODEL_NAME = 110,
  SESSION_COST = 100,
  REQUEST_INPUT_TOKENS = 90,
  CACHE_PERCENT = 80,
  REQUEST_COST = 70,
  REQUEST_OUTPUT_TOKENS = 60,
  THINKING_TOKENS = 50,
  SESSION_INPUT_TOKENS = 35,
  SESSION_OUTPUT_TOKENS = 35,
  SESSION_REQUEST_COUNT = 20,
  PROVIDER_NAME = 10,
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
      highlight = { group = "FlemmaNotificationsBar" },
    })

    table.insert(identity_items, {
      key = "provider_name",
      text = "(" .. request.provider .. ")",
      priority = PRIORITY.PROVIDER_NAME,
      highlight = { group = "FlemmaNotificationsMuted" },
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
        highlight = { group = "FlemmaNotificationsBar" },
      })
    end

    -- Cache percentage
    local cache_percent = M.calculate_cache_percent(request)
    if cache_percent ~= nil then
      -- Suppress cache indicator when 0% is expected (below minimum cacheable tokens)
      local below_threshold = false
      if cache_percent == 0 then
        local registry = require("flemma.provider.registry")
        local model_info = registry.get_model_info(request.provider, request.model)
        if model_info and model_info.min_cache_tokens then
          local total_input = request.input_tokens + request.cache_read_input_tokens + request.cache_creation_input_tokens
          below_threshold = total_input < model_info.min_cache_tokens
        end
      end

      if not below_threshold then
        local cache_text = tostring(cache_percent) .. "%"
        local group = cache_percent > 50 and "FlemmaNotificationsCacheGood" or "FlemmaNotificationsCacheBad"
        table.insert(request_items, {
          key = "cache_percent",
          text = cache_text,
          priority = PRIORITY.CACHE_PERCENT,
          highlight = {
            group = group,
          },
        })
      end
    end

    -- Input tokens
    table.insert(request_items, {
      key = "request_input_tokens",
      text = M.format_number(request.input_tokens) .. "\xE2\x86\x91", -- ↑
      priority = PRIORITY.REQUEST_INPUT_TOKENS,
      highlight = { group = "FlemmaNotificationsSecondary" },
    })

    -- Output tokens
    local total_output_tokens = request:get_total_output_tokens()
    table.insert(request_items, {
      key = "request_output_tokens",
      text = M.format_number(total_output_tokens) .. "\xE2\x86\x93", -- ↓
      priority = PRIORITY.REQUEST_OUTPUT_TOKENS,
      highlight = { group = "FlemmaNotificationsSecondary" },
    })

    -- Thinking tokens
    if request.thoughts_tokens > 0 then
      table.insert(request_items, {
        key = "thinking_tokens",
        text = "\xE2\x97\x8B " .. M.format_number(request.thoughts_tokens), -- ○
        priority = PRIORITY.THINKING_TOKENS,
        highlight = { group = "FlemmaNotificationsSecondary" },
      })
    end

    if #request_items > 0 then
      table.insert(segments, {
        key = "request",
        items = request_items,
        separator_highlight = "FlemmaNotificationsMuted",
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
        highlight = { group = "FlemmaNotificationsBar" },
      })
    end

    -- Session input tokens
    table.insert(session_items, {
      key = "session_input_tokens",
      text = M.format_number(session:get_total_input_tokens()) .. "\xE2\x86\x91", -- ↑
      priority = PRIORITY.SESSION_INPUT_TOKENS,
      highlight = { group = "FlemmaNotificationsSecondary" },
    })

    -- Session output tokens
    table.insert(session_items, {
      key = "session_output_tokens",
      text = M.format_number(session:get_total_output_tokens()) .. "\xE2\x86\x93", -- ↓
      priority = PRIORITY.SESSION_OUTPUT_TOKENS,
      highlight = { group = "FlemmaNotificationsSecondary" },
    })

    table.insert(segments, {
      key = "session",
      label = "Σ" .. tostring(session:get_request_count()),
      label_highlight = "FlemmaNotificationsMuted",
      separator_highlight = "FlemmaNotificationsMuted",
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
