---@class flemma.notify
local M = {}

---@class flemma.notify.Opts
---@field title? string
---@field icon? string
---@field timeout? integer|false
---@field replace? flemma.notify.Notification
---@field once? boolean

---@class flemma.notify.Notification
---@field level integer
---@field message string
---@field opts flemma.notify.Opts
---@field _native? any

---@alias flemma.notify.Impl fun(notification: flemma.notify.Notification): flemma.notify.Notification

---@type flemma.notify.Impl
local function default_impl(notification)
  vim.notify(notification.opts.title .. ": " .. notification.message, notification.level)
  return notification
end

local current_impl ---@type flemma.notify.Impl|nil
local detected_default ---@type flemma.notify.Impl|nil
local seen = {} ---@type table<integer, table<string, flemma.notify.Notification>>

local function ensure_impl()
  if current_impl then
    return
  end
  local ok, integration = pcall(require, "flemma.integrations.nvim-notify")
  if ok and integration and integration.impl then
    detected_default = integration.impl
  else
    detected_default = default_impl
  end
  current_impl = detected_default
end

---Override the dispatch implementation. For test isolation only.
---@param fn flemma.notify.Impl
function M._set_impl(fn)
  current_impl = fn
end

---Restore the auto-detected default implementation.
function M._reset_impl()
  -- ensure_impl populates detected_default if no dispatch has happened yet.
  if not detected_default then
    ensure_impl()
  end
  current_impl = detected_default
end

---@param level integer
---@param message string
---@param opts? flemma.notify.Opts
---@return flemma.notify.Notification
local function dispatch(level, message, opts)
  local normalized_opts = vim.tbl_extend("force", { title = "Flemma" }, opts or {})

  if normalized_opts.once then
    seen[level] = seen[level] or {}
    if seen[level][message] then
      return seen[level][message]
    end
  end

  ---@type flemma.notify.Notification
  local notification = { level = level, message = message, opts = normalized_opts }

  if normalized_opts.once then
    seen[level][message] = notification
  end

  vim.schedule(function()
    ensure_impl()
    local result = (current_impl --[[@as flemma.notify.Impl]])(notification)
    if result and result._native then
      notification._native = result._native
    end
  end)

  return notification
end

---@param message string
---@param opts? flemma.notify.Opts
---@return flemma.notify.Notification
function M.error(message, opts)
  return dispatch(vim.log.levels.ERROR, message, opts)
end

---@param message string
---@param opts? flemma.notify.Opts
---@return flemma.notify.Notification
function M.warn(message, opts)
  return dispatch(vim.log.levels.WARN, message, opts)
end

---@param message string
---@param opts? flemma.notify.Opts
---@return flemma.notify.Notification
function M.info(message, opts)
  return dispatch(vim.log.levels.INFO, message, opts)
end

---@param message string
---@param opts? flemma.notify.Opts
---@return flemma.notify.Notification
function M.debug(message, opts)
  return dispatch(vim.log.levels.DEBUG, message, opts)
end

---@param message string
---@param opts? flemma.notify.Opts
---@return flemma.notify.Notification
function M.trace(message, opts)
  return dispatch(vim.log.levels.TRACE, message, opts)
end

---Mirror of vim.notify(msg, level, opts) signature.
---@param message string
---@param level integer
---@param opts? flemma.notify.Opts
---@return flemma.notify.Notification
function M.notify(message, level, opts)
  return dispatch(level, message, opts)
end

return M
