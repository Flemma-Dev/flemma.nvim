--- Optional bufferline.nvim integration — shows a busy icon on .chat tabs
--- while a request is in-flight.
---
--- Usage (one line in bufferline config):
---   get_element_icon = require("flemma.integrations.bufferline").get_element_icon
---
--- Or with a custom icon:
---   get_element_icon = require("flemma.integrations.bufferline").get_element_icon({ icon = "+" })
---@class flemma.integrations.Bufferline
local M = {}

local DEFAULT_ICON = "󰔟"
local HIGHLIGHT = "FlemmaBusy"

---@type table<integer, true>
local busy_buffers = {}

-- Register early fallback highlight so FlemmaBusy exists before any .chat buffer opens.
-- apply_syntax() will re-register it from config, but this ensures the group is always defined.
vim.api.nvim_set_hl(0, HIGHLIGHT, { link = "DiagnosticWarn", default = true })

local augroup = vim.api.nvim_create_augroup("FlemmaBufferlineIntegration", { clear = true })

vim.api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "FlemmaRequestSending",
  callback = function(ev)
    if not ev.data or not ev.data.bufnr then
      return
    end
    busy_buffers[ev.data.bufnr] = true
    vim.schedule(vim.cmd.redrawtabline)
  end,
})

vim.api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "FlemmaRequestFinished",
  callback = function(ev)
    if not ev.data or not ev.data.bufnr then
      return
    end
    busy_buffers[ev.data.bufnr] = nil
    vim.schedule(vim.cmd.redrawtabline)
  end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
  group = augroup,
  callback = function(ev)
    busy_buffers[ev.buf] = nil
  end,
})

---Check whether opts represent a bufferline callback invocation (has path or filetype)
---versus a Flemma factory invocation (has icon or is empty).
---@param opts table
---@return boolean
local function is_bufferline_call(opts)
  return opts.path ~= nil or opts.filetype ~= nil
end

---Check whether the buffer described by opts is a .chat buffer.
---@param opts {filetype?: string, path?: string}
---@return boolean
local function is_chat_buffer(opts)
  if opts.filetype == "chat" then
    return true
  end
  if opts.filetype ~= nil then
    return false
  end
  -- filetype is nil — fall back to extension check
  return opts.path ~= nil and opts.path:match("%.chat$") ~= nil
end

---Build a dual-mode get_element_icon handler with the given busy icon.
---
---In callback mode (called by bufferline with {path, filetype, ...}):
---returns icon + highlight for busy .chat buffers, nil otherwise.
---
---In factory mode (called with {icon} or no args):
---returns a new dual-mode handler with the custom icon.
---@alias flemma.integrations.bufferline.ElementIcon fun(opts?: table): string|nil, string|nil

---@param icon string
---@return flemma.integrations.bufferline.ElementIcon
local function factory(icon)
  ---@overload fun(opts: {path: string, filetype?: string, extension?: string, directory?: boolean}): string|nil, string|nil
  ---@overload fun(opts?: {icon?: string}): flemma.integrations.bufferline.ElementIcon
  ---@param opts? table
  ---@return string|nil|flemma.integrations.bufferline.ElementIcon icon_or_handler, string|nil highlight_group
  local function element_icon(opts)
    opts = opts or {}
    if is_bufferline_call(opts) then
      if not is_chat_buffer(opts) then
        return
      end
      local bufnr = vim.fn.bufnr(opts.path)
      if busy_buffers[bufnr] then
        return icon, HIGHLIGHT
      end
      return
    end
    return factory(opts.icon or icon)
  end
  return element_icon
end

M.get_element_icon = factory(DEFAULT_ICON)

---Exposed for testing only. Do not use in production code.
---@return table<integer, true>
function M._get_busy_buffers()
  return busy_buffers
end

return M
