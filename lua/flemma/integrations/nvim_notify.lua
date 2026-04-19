--- Optional rcarriga/nvim-notify integration — adapter that satisfies the
--- flemma.notify.Impl contract by routing dispatch through nvim-notify's
--- callable module, with a pcall guard for runtime edge cases (e.g. a replace
--- handle whose underlying record came from a tabpage that has since closed).
---
--- Lazy-loaded by flemma.notify on first dispatch when require("notify") succeeds.
---@class flemma.integrations.NvimNotify
local M = {}

local nvim_notify = require("notify")

---@type flemma.notify.Impl
function M.impl(notification)
  local opts = {
    title = notification.opts.title,
    icon = notification.opts.icon,
    timeout = notification.opts.timeout,
    replace = notification.opts.replace and notification.opts.replace._native or nil,
  }
  local ok, native = pcall(nvim_notify, notification.message, notification.level, opts)
  if ok and native then
    return vim.tbl_extend("force", notification, { _native = native })
  end
  return notification
end

return M
