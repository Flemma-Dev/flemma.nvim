--- Reusable notification/progress bar as a floating window.
--- Handle-based API: callers hold a handle and call methods on it.
--- See docs/superpowers/specs/2026-04-18-bar-utility-design.md for the
--- design rationale.
---@class flemma.ui.bar
local M = {}

---@alias flemma.ui.bar.Position
---| "top"
---| "bottom"
---| "top left"
---| "top right"
---| "bottom left"
---| "bottom right"

---@class flemma.ui.bar.Opts
---@field bufnr integer
---@field position flemma.ui.bar.Position
---@field segments flemma.ui.bar.layout.Segment[]
---@field icon? string
---@field highlight? string|string[]
---@field on_shown? fun()
---@field on_dismiss? fun()

---@class flemma.ui.bar.UpdatePartial
---@field icon? string
---@field segments? flemma.ui.bar.layout.Segment[]
---@field highlight? string|string[]

---@type table<flemma.ui.bar.Position, flemma.ui.bar.Position[]>
local CONFLICTS = {
  ["top"] = { "top", "top left", "top right" },
  ["top left"] = { "top", "top left" },
  ["top right"] = { "top", "top right" },
  ["bottom"] = { "bottom", "bottom left", "bottom right" },
  ["bottom left"] = { "bottom", "bottom left" },
  ["bottom right"] = { "bottom", "bottom right" },
}

---@class flemma.ui.bar.Bar
---@field id integer
---@field bufnr integer
---@field position flemma.ui.bar.Position
---@field dismissed boolean
---@field segments flemma.ui.bar.layout.Segment[]
---@field icon string|nil
---@field highlight string|string[]|nil
---@field on_shown fun()|nil
---@field on_dismiss fun()|nil
---@field _shown boolean
---@field _float_winid integer|nil
---@field _float_bufnr integer|nil
---@field _gutter_winid integer|nil
---@field _gutter_bufnr integer|nil
---@field _autocmd_group integer|nil
---@field _extmark_ids integer[]
---@field _last_gutter_width integer|nil
local Bar = {}
Bar.__index = Bar

---@type table<integer, table<flemma.ui.bar.Position, flemma.ui.bar.Bar>>
local bars = {}

---@type integer
local next_id = 0

---Create a pre-dismissed handle (used when bufnr is invalid).
---@return flemma.ui.bar.Bar
local function dismissed_handle()
  next_id = next_id + 1
  ---@type flemma.ui.bar.Bar
  local handle = setmetatable({
    id = next_id,
    bufnr = 0,
    position = "top",
    dismissed = true,
    segments = {},
    icon = nil,
    highlight = nil,
    on_shown = nil,
    on_dismiss = nil,
    _shown = false,
    _float_winid = nil,
    _float_bufnr = nil,
    _gutter_winid = nil,
    _gutter_bufnr = nil,
    _autocmd_group = nil,
    _extmark_ids = {},
    _last_gutter_width = nil,
  }, Bar)
  return handle
end

---Create a new Bar.
---@param opts flemma.ui.bar.Opts
---@return flemma.ui.bar.Bar
function M.new(opts)
  if not vim.api.nvim_buf_is_valid(opts.bufnr) then
    return dismissed_handle()
  end

  -- Reject positions that are not one of the six valid values. Prevents
  -- `bars[bufnr][nil] = ...` (table-index-is-nil error) and silent
  -- mis-rendering for typos like "mid-left". Config schema already
  -- restricts the enum at the user-facing layer; this guard covers
  -- direct callers (tests, future features).
  if CONFLICTS[opts.position] == nil then
    return dismissed_handle()
  end

  -- Displace conflicting bars on the same buffer.
  if bars[opts.bufnr] then
    for _, conflict in ipairs(CONFLICTS[opts.position]) do
      local existing = bars[opts.bufnr][conflict]
      if existing then
        existing:dismiss()
      end
    end
  end

  next_id = next_id + 1
  ---@type flemma.ui.bar.Bar
  local self = setmetatable({
    id = next_id,
    bufnr = opts.bufnr,
    position = opts.position,
    dismissed = false,
    segments = opts.segments or {},
    icon = opts.icon,
    highlight = opts.highlight,
    on_shown = opts.on_shown,
    on_dismiss = opts.on_dismiss,
    _shown = false,
    _float_winid = nil,
    _float_bufnr = nil,
    _gutter_winid = nil,
    _gutter_bufnr = nil,
    _autocmd_group = nil,
    _extmark_ids = {},
    _last_gutter_width = nil,
  }, Bar)

  bars[opts.bufnr] = bars[opts.bufnr] or {}
  bars[opts.bufnr][opts.position] = self

  -- TODO(Task 10): register autocmds, call self:_render()

  return self
end

---Return whether this handle has been dismissed.
---@return boolean
function Bar:is_dismissed()
  return self.dismissed
end

---Dismiss this Bar. Idempotent: subsequent calls are no-ops.
---@return flemma.ui.bar.Bar
function Bar:dismiss()
  if self.dismissed then
    return self
  end
  self.dismissed = true

  -- TODO(Task 10): clear extmarks, close floats, delete augroup

  if bars[self.bufnr] and bars[self.bufnr][self.position] == self then
    bars[self.bufnr][self.position] = nil
    if next(bars[self.bufnr]) == nil then
      bars[self.bufnr] = nil
    end
  end

  if self.on_dismiss then
    pcall(self.on_dismiss)
  end
  return self
end

-- Method stubs so dismissed-handle no-op semantics work before the full
-- implementation lands in later tasks. Each method is a no-op when
-- dismissed; full behaviour is added in Task 11.

---Update the icon shown before the bar content.
---@param icon string|nil
---@return flemma.ui.bar.Bar
function Bar:set_icon(icon)
  if self.dismissed then
    return self
  end
  self.icon = icon
  return self
end

---Replace the bar's segments.
---@param segments flemma.ui.bar.layout.Segment[]|nil
---@return flemma.ui.bar.Bar
function Bar:set_segments(segments)
  if self.dismissed then
    return self
  end
  self.segments = segments or {}
  return self
end

---Update the bar's highlight group(s).
---@param hl string|string[]|nil
---@return flemma.ui.bar.Bar
function Bar:set_highlight(hl)
  if self.dismissed then
    return self
  end
  self.highlight = hl
  return self
end

---Partial update of icon/segments/highlight in one call.
---@param partial flemma.ui.bar.UpdatePartial
---@return flemma.ui.bar.Bar
function Bar:update(partial)
  if self.dismissed then
    return self
  end
  if partial.icon ~= nil then
    self.icon = partial.icon
  end
  if partial.segments ~= nil then
    self.segments = partial.segments
  end
  if partial.highlight ~= nil then
    self.highlight = partial.highlight
  end
  return self
end

return M
