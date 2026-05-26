--- Debounced per-buffer input-token estimate prefetch.
---
--- USER-ACTIVATED MODULE — loaded by lua/lualine/components/flemma.lua, not
--- by Flemma's init. Hook registrations at module scope are intentional: they
--- fire on require(), which only happens when the user's lualine config
--- references the Flemma component. No traffic fires unless the
--- #{buffer.tokens.input} variable is in the statusline format.
---
--- Activation is resolver-driven: the lualine resolver for
--- `buffer.tokens.input` calls `start_tracking(bufnr)` idempotently on
--- first access. That installs per-buffer TextChanged autocmds and registers
--- a buffer:destroyed hook. Subsequent fetches (added in later commits) are
--- debounced 2.5s after the user stops editing.
---
--- This module is the only consumer of provider try_estimate_usage hooks that
--- isn't the :Flemma usage:estimate command.
---@class flemma.usage.Prefetch
local M = {}

local config = require("flemma.config")
local hooks = require("flemma.hooks")
local loader = require("flemma.loader")
local log = require("flemma.logging")
local provider_registry = require("flemma.provider.registry")
local readiness = require("flemma.readiness")

---@type integer Debounce window in milliseconds. Exposed for tests.
M._DEBOUNCE_MS = 2500

---@class flemma.usage.prefetch.Entry
---@field timer uv.uv_timer_t|nil
---@field augroup_id integer
---@field cached_tokens integer|nil
---@field cached_key string|nil
---@field in_flight boolean
---@field request_active boolean True between request:sending and request:finished — suppresses debounced fetches so we don't waste count_tokens calls during streaming/tool-call loops.

---@type table<integer, flemma.usage.prefetch.Entry>
local entries = {}

---@type flemma.hooks.Subscription|nil
local config_listener_subscription = nil

---@type flemma.hooks.Subscription[]
local request_listener_subscriptions = {}

---Tear down all state. Test-only.
function M._reset_for_tests()
  for bufnr in pairs(entries) do
    M.untrack(bufnr)
  end
  if config_listener_subscription then
    config_listener_subscription:off()
    config_listener_subscription = nil
  end
  for _, handle in ipairs(request_listener_subscriptions) do
    handle:off()
  end
  request_listener_subscriptions = {}
end

---Introspection for tests.
---@param bufnr integer
---@return boolean
function M._is_tracked(bufnr)
  return entries[bufnr] ~= nil
end

---@return integer
function M._tracked_count()
  local n = 0
  for _ in pairs(entries) do
    n = n + 1
  end
  return n
end

---@param bufnr integer
---@return integer|nil
function M._get_augroup(bufnr)
  local e = entries[bufnr]
  return e and e.augroup_id or nil
end

---@param bufnr integer
---@return boolean
function M._is_request_active(bufnr)
  local e = entries[bufnr]
  return e ~= nil and e.request_active
end

---@param bufnr integer
local function emit_hook(bufnr)
  hooks.dispatch("usage:estimated", { bufnr = bufnr })
end

---@param bufnr integer
local function clear_cache(bufnr)
  local entry = entries[bufnr]
  if not entry then
    return
  end
  local changed = entry.cached_tokens ~= nil or entry.cached_key ~= nil
  entry.cached_tokens = nil
  entry.cached_key = nil
  if changed then
    log.debug("prefetch: cache cleared for bufnr=" .. bufnr)
    emit_hook(bufnr)
  end
end

---@param bufnr integer
---@param response flemma.usage.EstimateResponse
local function write_cache(bufnr, response)
  local entry = entries[bufnr]
  if not entry then
    return
  end
  -- Dedup: same (tokens, cache_key) → no hook.
  if entry.cached_tokens == response.tokens and entry.cached_key == response.cache_key then
    return
  end
  log.debug(
    "prefetch: cache write bufnr=" .. bufnr .. " tokens=" .. response.tokens .. " cache_key=" .. response.cache_key
  )
  entry.cached_tokens = response.tokens
  entry.cached_key = response.cache_key
  emit_hook(bufnr)
end

---@param bufnr integer
local function fire_fetch(bufnr)
  local entry = entries[bufnr]
  if not entry or entry.in_flight or entry.request_active then
    return
  end

  local cfg = config.get(bufnr)
  if not cfg.provider or cfg.provider == "" then
    log.debug("prefetch: fire_fetch skipped (no provider configured) bufnr=" .. bufnr)
    clear_cache(bufnr)
    return
  end

  local provider_module_path = provider_registry.get(cfg.provider)
  if not provider_module_path then
    log.debug("prefetch: fire_fetch skipped (unknown provider '" .. cfg.provider .. "') bufnr=" .. bufnr)
    clear_cache(bufnr)
    return
  end

  local provider_module = loader.load(provider_module_path)
  if not provider_module or not provider_module.try_estimate_usage then
    log.debug(
      "prefetch: fire_fetch skipped (provider '" .. cfg.provider .. "' lacks try_estimate_usage) bufnr=" .. bufnr
    )
    clear_cache(bufnr)
    return
  end

  log.debug("prefetch: fire_fetch dispatching bufnr=" .. bufnr .. " provider=" .. cfg.provider)
  entry.in_flight = true

  local function attempt()
    local ok, err = pcall(provider_module.try_estimate_usage, bufnr, function(result)
      local e = entries[bufnr]
      if not e then
        return
      end
      e.in_flight = false
      if result.err then
        log.debug("prefetch: fetch returned err for bufnr=" .. bufnr .. ": " .. tostring(result.err))
        clear_cache(bufnr)
        return
      end
      if result.response then
        write_cache(bufnr, result.response)
      end
    end)
    if ok then
      return
    end
    if not readiness.is_suspense(err) then
      entry.in_flight = false
      clear_cache(bufnr)
      log.debug("prefetch: non-suspense error " .. tostring(err))
      return
    end
    ---@cast err flemma.readiness.Suspense
    err.boundary:subscribe(function(result)
      if not entries[bufnr] then
        return
      end
      if not result or result.ok == false then
        entries[bufnr].in_flight = false
        clear_cache(bufnr)
        return
      end
      attempt()
    end)
  end
  attempt()
end

---@param bufnr integer
local function schedule_fetch(bufnr)
  local entry = entries[bufnr]
  if not entry or entry.request_active then
    -- While a request is in flight, TextChanged fires constantly as the
    -- response streams in — suppress the debounced estimate. Real usage
    -- will arrive via request:finished.
    return
  end
  if entry.timer then
    pcall(entry.timer.stop, entry.timer)
    pcall(entry.timer.close, entry.timer)
  end
  local timer = vim.uv.new_timer()
  if not timer then
    return
  end
  entry.timer = timer
  timer:start(M._DEBOUNCE_MS, 0, function()
    vim.schedule(function()
      fire_fetch(bufnr)
    end)
  end)
end

---Installed once on first start_tracking. Wipes all tracked caches and
---reschedules fetches so `:Flemma switch` and similar config changes clear
---stale numbers immediately.
local function install_config_listener()
  if config_listener_subscription then
    return
  end
  config_listener_subscription = hooks.on("config:updated", function()
    local count = 0
    for bufnr_key in pairs(entries) do
      clear_cache(bufnr_key)
      schedule_fetch(bufnr_key)
      count = count + 1
    end
    log.debug("prefetch: config:updated → invalidated " .. count .. " tracked buffer(s)")
  end)
end

---Installed once on first start_tracking. Suppresses debounced fetches while
---a buffer has a request in flight, and seeds the cache from the actual
---request.input_tokens when a request completes — avoiding a redundant
---count_tokens round-trip during tool-call loops.
local function install_request_listener()
  if #request_listener_subscriptions > 0 then
    return
  end

  request_listener_subscriptions[#request_listener_subscriptions + 1] = hooks.on("request:sending", function(data)
    local entry = entries[data.bufnr]
    if not entry then
      return
    end
    log.debug("prefetch: request:sending → suppress fetches bufnr=" .. data.bufnr)
    if entry.timer then
      pcall(entry.timer.stop, entry.timer)
      pcall(entry.timer.close, entry.timer)
      entry.timer = nil
    end
    entry.request_active = true
  end)

  request_listener_subscriptions[#request_listener_subscriptions + 1] = hooks.on("request:finished", function(data)
    local entry = entries[data.bufnr]
    if not entry then
      return
    end
    entry.request_active = false
    if data.request then
      local cache_read = data.request.cache_read_input_tokens or 0
      local cache_creation = data.request.cache_creation_input_tokens or 0
      local total_input = data.request.input_tokens + cache_read + cache_creation
      log.debug(
        "prefetch: request:finished → seed cache from actual request bufnr="
          .. data.bufnr
          .. " tokens="
          .. total_input
          .. " (input="
          .. data.request.input_tokens
          .. " cache_read="
          .. cache_read
          .. " cache_creation="
          .. cache_creation
          .. ") model="
          .. data.request.model
      )
      write_cache(data.bufnr, {
        tokens = total_input,
        cache_key = data.request.provider .. ":" .. data.request.model,
        model = data.request.model,
      })
    else
      log.debug(
        "prefetch: request:finished → cleared request_active (no request payload, status="
          .. tostring(data.status)
          .. ") bufnr="
          .. data.bufnr
      )
    end
  end)
end

---Idempotent. First call per buffer creates state + augroup.
---@param bufnr integer
function M.start_tracking(bufnr)
  if entries[bufnr] then
    return
  end

  log.debug("prefetch: start_tracking bufnr=" .. bufnr)
  local augroup_id = vim.api.nvim_create_augroup("FlemmaUsagePrefetch_" .. bufnr, { clear = true })

  entries[bufnr] = {
    timer = nil,
    augroup_id = augroup_id,
    cached_tokens = nil,
    cached_key = nil,
    in_flight = false,
    request_active = false,
  }

  install_config_listener()
  install_request_listener()

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup_id,
    buffer = bufnr,
    callback = function()
      schedule_fetch(bufnr)
    end,
  })

  -- Immediate initial fetch so the first render has data to show.
  vim.defer_fn(function()
    if entries[bufnr] then
      fire_fetch(bufnr)
    end
  end, 0)
end

---@param bufnr integer
---@return integer|nil
function M.get_tokens(bufnr)
  local entry = entries[bufnr]
  return entry and entry.cached_tokens or nil
end

---Tear down state, stop timer, delete augroup.
---@param bufnr integer
function M.untrack(bufnr)
  local entry = entries[bufnr]
  if not entry then
    return
  end
  log.debug("prefetch: untrack bufnr=" .. bufnr)
  if entry.timer then
    pcall(entry.timer.stop, entry.timer)
    pcall(entry.timer.close, entry.timer)
  end
  pcall(vim.api.nvim_del_augroup_by_id, entry.augroup_id)
  entries[bufnr] = nil
end

hooks.on("buffer:destroyed", function(data)
  M.untrack(data.bufnr)
end)

return M
