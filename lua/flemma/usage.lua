--- Usage and pricing functionality for Flemma plugin
--- Centralizes notification display for request and session costs

---@class flemma.Usage
local M = {}

local layout = require("flemma.ui.bar.layout")
local config_facade = require("flemma.config")
local provider_registry = require("flemma.provider.registry")
local str = require("flemma.utilities.string")
local Bar = require("flemma.ui.bar")
local state = require("flemma.state")

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
  return str.format_number(number)
end

--- Calculate cache hit percentage for a request
--- Total input = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
--- because the Anthropic API reports input_tokens as only the non-cached portion.
---@param request flemma.session.Request The request to calculate cache percentage for
---@return integer|nil percent Cache hit percentage (0-100), or nil when total input is 0
function M.calculate_cache_percent(request)
  local total_input = request:get_total_input_tokens()
  if total_input == 0 then
    return nil
  end
  return math.floor(request.cache_read_input_tokens / total_input * 100)
end

--- Build structured segments from request and session data for bar rendering
---@param request? flemma.session.Request Most recent completed request
---@param session? flemma.session.Session Session instance
---@return flemma.ui.bar.layout.Segment[]
function M.build_segments(request, session)
  local config = config_facade.get()
  local pricing_enabled = config.pricing.enabled

  local segments = {} ---@type flemma.ui.bar.layout.Segment[]

  -- Identity segment (from request)
  if request then
    local identity_items = {} ---@type flemma.ui.bar.layout.Item[]

    table.insert(identity_items, {
      key = "model_name",
      text = request.model,
      priority = PRIORITY.MODEL_NAME,
      highlight = { group = "FlemmaUsageBar" },
    })

    table.insert(identity_items, {
      key = "provider_name",
      text = "(" .. request.provider .. ")",
      priority = PRIORITY.PROVIDER_NAME,
      highlight = { group = "FlemmaUsageBarMuted" },
    })

    table.insert(segments, {
      key = "identity",
      items = identity_items,
    })
  end

  -- Request segment
  if request then
    local request_items = {} ---@type flemma.ui.bar.layout.Item[]

    -- Cost
    if pricing_enabled then
      table.insert(request_items, {
        key = "request_cost",
        text = str.format_money(request:get_total_cost()),
        priority = PRIORITY.REQUEST_COST,
        highlight = { group = "FlemmaUsageBar" },
      })
    end

    -- Cache percentage
    local cache_percent = M.calculate_cache_percent(request)
    if cache_percent ~= nil then
      -- Suppress cache indicator when 0% is expected (below minimum cacheable tokens)
      local below_threshold = false
      if cache_percent == 0 then
        local model_info = provider_registry.get_model_info(request.provider, request.model)
        if model_info and model_info.min_cache_tokens then
          below_threshold = request:get_total_input_tokens() < model_info.min_cache_tokens
        end
      end

      if not below_threshold then
        local cache_text = str.format_percent(cache_percent)
        local group = cache_percent > 50 and "FlemmaUsageBarCacheGood" or "FlemmaUsageBarCacheBad"
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

    -- Input tokens (total including cached)
    table.insert(request_items, {
      key = "request_input_tokens",
      text = M.format_number(request:get_total_input_tokens()) .. "\xE2\x86\x91", -- ↑
      priority = PRIORITY.REQUEST_INPUT_TOKENS,
      highlight = { group = "FlemmaUsageBarSecondary" },
    })

    -- Output tokens
    local total_output_tokens = request:get_total_output_tokens()
    table.insert(request_items, {
      key = "request_output_tokens",
      text = M.format_number(total_output_tokens) .. "\xE2\x86\x93", -- ↓
      priority = PRIORITY.REQUEST_OUTPUT_TOKENS,
      highlight = { group = "FlemmaUsageBarSecondary" },
    })

    -- Thinking tokens
    if request.thoughts_tokens > 0 then
      table.insert(request_items, {
        key = "thinking_tokens",
        text = M.format_number(request.thoughts_tokens) .. "\xE2\x81\x82", -- ⁂
        priority = PRIORITY.THINKING_TOKENS,
        highlight = { group = "FlemmaUsageBarSecondary" },
      })
    end

    if #request_items > 0 then
      table.insert(segments, {
        key = "request",
        items = request_items,
        separator_highlight = "FlemmaUsageBarMuted",
      })
    end
  end

  -- Session segment
  if session and session:get_request_count() > 0 then
    local session_items = {} ---@type flemma.ui.bar.layout.Item[]

    -- Session cost
    if pricing_enabled then
      table.insert(session_items, {
        key = "session_cost",
        text = str.format_money(session:get_total_cost()),
        priority = PRIORITY.SESSION_COST,
        highlight = { group = "FlemmaUsageBar" },
      })
    end

    -- Session input tokens
    table.insert(session_items, {
      key = "session_input_tokens",
      text = M.format_number(session:get_total_input_tokens()) .. "\xE2\x86\x91", -- ↑
      priority = PRIORITY.SESSION_INPUT_TOKENS,
      highlight = { group = "FlemmaUsageBarSecondary" },
    })

    -- Session output tokens
    table.insert(session_items, {
      key = "session_output_tokens",
      text = M.format_number(session:get_total_output_tokens()) .. "\xE2\x86\x93", -- ↓
      priority = PRIORITY.SESSION_OUTPUT_TOKENS,
      highlight = { group = "FlemmaUsageBarSecondary" },
    })

    table.insert(segments, {
      key = "session",
      label = "Σ" .. tostring(session:get_request_count()),
      label_highlight = "FlemmaUsageBarMuted",
      separator_highlight = "FlemmaUsageBarMuted",
      items = session_items,
    })
  end

  return segments
end

---Start the auto-dismiss timer for the bar on a given buffer.
---Reads cfg.timeout; 0 = persistent (no timer).
---@param bufnr integer
local function start_timeout_timer(bufnr)
  local cfg = config_facade.get(bufnr).ui.usage
  if cfg.timeout <= 0 then
    return
  end
  local bs = state.get_buffer_state(bufnr)
  bs.usage_timer = vim.fn.timer_start(cfg.timeout, function()
    local inner = state.get_buffer_state(bufnr)
    if inner.usage_bar then
      inner.usage_bar:dismiss()
    end
    inner.usage_timer = nil
  end)
end

---Public entrypoint used by core.lua after a successful request.
---The enabled gate runs synchronously; everything else defers via
---vim.schedule to let the triggering callback finish first.
---@param bufnr integer
---@param request flemma.session.Request|nil
function M.show(bufnr, request)
  local cfg = config_facade.get(bufnr).ui.usage
  if not cfg.enabled then
    return
  end

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local bs = state.get_buffer_state(bufnr)
    if bs.usage_timer then
      vim.fn.timer_stop(bs.usage_timer)
      bs.usage_timer = nil
    end

    local segments = M.build_segments(request, state.get_session())
    if #segments == 0 then
      return
    end

    bs.usage_bar = Bar.new({
      bufnr = bufnr,
      position = cfg.position,
      segments = segments,
      icon = layout.PREFIX,
      -- Paint with the pre-computed FlemmaUsageBar group so attributes
      -- (italic/bold/underline) on the user's resolved chain group do
      -- NOT leak through. highlight.lua already derived FlemmaUsageBar's
      -- bg+fg from cfg.highlight; cfg.highlight is kept as a fallback
      -- tail in case FlemmaUsageBar is somehow undefined.
      highlight = "FlemmaUsageBar," .. cfg.highlight,
      on_shown = function()
        start_timeout_timer(bufnr)
      end,
      on_dismiss = function()
        local inner = state.get_buffer_state(bufnr)
        inner.usage_bar = nil
      end,
    })
  end)
end

---Recall the most recent request for the current buffer's filepath and
---re-display the usage bar. Takes no argument: resolves the current
---buffer internally. Three failure paths each emit a single
---vim.notify(WARN): no filepath, no latest request, empty segments.
function M.recall_last()
  local bufnr = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local bs = state.get_buffer_state(bufnr)
  if bs.usage_bar and not bs.usage_bar:is_dismissed() then
    return
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    vim.notify("Flemma: No notification for this buffer.", vim.log.levels.WARN)
    return
  end

  local session = state.get_session()
  local latest = session:get_latest_request_for_filepath(filepath)
  if not latest then
    vim.notify("Flemma: No notification for this buffer.", vim.log.levels.WARN)
    return
  end

  local segments = M.build_segments(latest, session)
  if #segments == 0 then
    vim.notify("Flemma: No notification for this buffer.", vim.log.levels.WARN)
    return
  end

  M.show(bufnr, latest)
end

---Per-buffer cleanup; called via state.register_cleanup.
---@param bufnr integer
function M.cleanup_buffer(bufnr)
  local bs = state.get_buffer_state(bufnr)
  if bs.usage_timer then
    vim.fn.timer_stop(bs.usage_timer)
    bs.usage_timer = nil
  end
  if bs.usage_bar then
    bs.usage_bar:dismiss()
    bs.usage_bar = nil
  end
end

state.register_cleanup("usage", function(bufnr)
  M.cleanup_buffer(bufnr)
end)

return M
