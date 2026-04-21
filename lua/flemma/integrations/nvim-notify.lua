--- Optional rcarriga/nvim-notify integration — adapter that satisfies the
--- flemma.notify.Impl contract by routing dispatch through nvim-notify's
--- callable module, with a pcall guard for runtime edge cases (e.g. a replace
--- handle whose underlying record came from a tabpage that has since closed).
---
--- Lazy-loaded by flemma.notify on first dispatch. When nvim-notify is not
--- installed, this module still loads cleanly but omits M.impl — flemma.notify
--- then falls back to vim.notify. Loading in isolation without the optional
--- dep is required by external require-checkers (e.g. nixpkgs'
--- nvimRequireCheck) that validate every lua/flemma/**/*.lua at build time.
---@class flemma.integrations.NvimNotify
local M = {}

local loaded, nvim_notify = pcall(require, "notify")
if not loaded then
  return M
end

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
