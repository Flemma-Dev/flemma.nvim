--- Reusable notification/progress bar as a floating window.
--- Handle-based API: callers hold a handle and call methods on it.
--- See docs/superpowers/specs/2026-04-18-bar-utility-design.md for the
--- design rationale.
---@class flemma.ui.bar
local M = {}

local layout = require("flemma.ui.bar.layout")
local buffer = require("flemma.utilities.buffer")
local highlight = require("flemma.highlight")
local str = require("flemma.utilities.string")

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

local ZINDEX = 50
local NS = vim.api.nvim_create_namespace("flemma_ui_bar")

local ICON_TRAILING_SPACE = " "

---Normalise an icon string: trim any trailing space, re-append exactly one.
---@param icon string
---@return string
local function normalize_icon(icon)
  local trimmed = icon:gsub("%s+$", "")
  return trimmed .. ICON_TRAILING_SPACE
end

---@type table<flemma.ui.bar.Position, string>
local DEFAULT_CHAIN = {
  ["top"] = "TabLine,StatusLine",
  ["top left"] = "TabLine,StatusLine",
  ["top right"] = "TabLine,StatusLine",
  ["bottom"] = "StatusLine",
  ["bottom left"] = "StatusLine",
  ["bottom right"] = "StatusLine",
}

---Resolve the winhighlight group name for a Bar, falling back by position.
---@param bar flemma.ui.bar.Bar
---@return string group
local function resolve_winhighlight(bar)
  local caller_hit = bar.highlight and highlight.resolve_first_complete(bar.highlight) or nil
  return caller_hit or highlight.resolve_first_complete(DEFAULT_CHAIN[bar.position]) or "StatusLine"
end

---@class flemma.ui.bar.Geometry
---@field row integer
---@field main_col integer
---@field main_width integer
---@field gutter_col? integer
---@field gutter_width? integer
---@field pad_text boolean
---@field lead_pad_for_right? boolean Prepend a leading space so right-anchored bars get breathing room against buffer text on the LEFT (the float's right edge sits against the window border, so the trailing breathing in `width` would otherwise be wasted)

---Compute geometry for the bar given window dimensions and text width.
---Returns a table with row, main_col, main_width, gutter (nil or { col, width }).
---@param position flemma.ui.bar.Position
---@param W integer Window width
---@param H integer Window height
---@param G integer Gutter width
---@param T integer Rendered text display width (from layout.render)
---@param icon_width integer Icon display width (0 if no icon)
---@param icon_in_gutter boolean Whether the icon rides in a separate gutter float
---@return flemma.ui.bar.Geometry
local function compute_geometry(position, W, H, G, T, icon_width, icon_in_gutter)
  local is_bottom = position:find("^bottom") ~= nil
  local is_right = position:find("right$") ~= nil
  local row = is_bottom and (H - 1) or 0

  if is_right then
    -- Width = leading-pad(1) + icon_width + body(T). Mirrors the trailing
    -- breathing of left-anchored bars: instead of wasting the +1 against
    -- the window's right border, we put it on the left so the icon does
    -- not sit flush against buffer text at col W-width-1.
    local width = math.min(T + icon_width + 1, W)
    return {
      row = row,
      main_col = W - width,
      main_width = width,
      pad_text = false,
      lead_pad_for_right = true,
    }
  end

  if icon_in_gutter then
    local is_full = position == "top" or position == "bottom"
    local main_width = is_full and (W - G) or math.min(T + 1, W - G)
    return {
      row = row,
      main_col = G,
      main_width = main_width,
      gutter_col = 0,
      gutter_width = G,
      pad_text = false,
    }
  end

  -- Narrow-gutter fallback: main float at col 0. The displayed line is
  --   <G leading spaces> + <inline-prepended icon> + <body text>
  -- so the float must be wide enough to fit all three plus one column of
  -- breathing room. The icon_width term is critical — without it, a
  -- 2-column icon clips the trailing character of the body.
  local is_full = position == "top" or position == "bottom"
  local main_width = is_full and W or math.min(T + G + icon_width + 1, W)
  return {
    row = row,
    main_col = 0,
    main_width = main_width,
    pad_text = true,
  }
end

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

  -- Displace conflicting bars on the same buffer. existing:dismiss() may
  -- clear bars[opts.bufnr] entirely (when the last position drops out),
  -- so re-check on each iteration — otherwise the next iteration indexes
  -- nil and crashes Bar.new. This bites usage.show in particular: it is
  -- called repeatedly with the same position, and the displacement loop
  -- visits siblings of that position even after the registry collapses.
  if bars[opts.bufnr] then
    for _, conflict in ipairs(CONFLICTS[opts.position]) do
      local existing = bars[opts.bufnr] and bars[opts.bufnr][conflict]
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

  self:_install_autocmds()
  self:_render()

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

  if self._autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, self._autocmd_group)
    self._autocmd_group = nil
  end

  if self._float_bufnr and vim.api.nvim_buf_is_valid(self._float_bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, self._float_bufnr, NS, 0, -1)
  end
  self:_close_floats()

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

---Update the icon shown before the bar content.
---@param icon string|nil
---@return flemma.ui.bar.Bar
function Bar:set_icon(icon)
  if self.dismissed then
    return self
  end
  self.icon = icon
  self:_render()
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
  self:_render()
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
  self:_render()
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
  self:_render()
  return self
end

---Render the bar to its floating window(s). Creates or reconfigures floats,
---applies highlight extmarks, and manages the optional gutter-icon float.
---No-ops when dismissed or when the host buffer is not visible in any window.
function Bar:_render()
  if self.dismissed then
    return
  end

  local winid = vim.fn.bufwinid(self.bufnr)
  if winid == -1 then
    -- Buffer not visible; close floats but preserve state.
    self:_close_floats()
    return
  end

  local W = vim.api.nvim_win_get_width(winid)
  local H = vim.api.nvim_win_get_height(winid)
  local G = buffer.get_gutter_width(winid)

  local icon_normalized = self.icon and normalize_icon(self.icon) or nil
  local icon_width = icon_normalized and str.strwidth(icon_normalized) or 0

  -- Determine whether the icon fits in the gutter, then choose the layout
  -- engine's available-width upper bound accordingly. Left/full positions
  -- reserve the gutter; right-anchored positions use the full window.
  local is_right = self.position:find("right$") ~= nil
  local icon_in_gutter = icon_width > 0 and G >= (icon_width + 1) and not is_right
  local text_area_width = (icon_in_gutter and (W - G)) or W

  -- Render segments with layout engine; Bar always skips the built-in prefix.
  -- layout.render right-pads its output to `available_width` so full-width
  -- positions (top / bottom) get a bar that spans the whole line. Corner
  -- positions (top|bottom {left|right}) must be sized to the natural content
  -- instead — trim the trailing pad before measuring so the float hugs the
  -- text rather than stretching across the window. Highlight byte offsets sit
  -- inside the content, so trimming does not invalidate them.
  local rendered = layout.render(self.segments, text_area_width, nil, { skip_prefix = true })
  local natural_text = (rendered.text:gsub("%s+$", ""))
  local T = str.strwidth(natural_text)

  local geom = compute_geometry(self.position, W, H, G, T, icon_width, icon_in_gutter)

  -- Order matters: icon FIRST (next to the body), then G_pad in front of
  -- both. The pre-refactor narrow-gutter code rendered
  --   <G spaces> + <spinner> + " " + <body>
  -- so the icon glyph landed at col G (right at the gutter/buffer boundary).
  -- Prepending the icon AFTER the G_pad would put it at col 0 instead — a
  -- visible regression for users with line-numbers narrow enough to fall
  -- through to this branch (G in (0, icon_width+1)).
  local text = natural_text
  if icon_normalized and not geom.gutter_col then
    text = icon_normalized .. text
  end
  if geom.pad_text then
    text = string.rep(" ", G) .. text
  end
  if geom.lead_pad_for_right then
    text = " " .. text
  end

  -- Ensure main float buffer.
  if not self._float_bufnr or not vim.api.nvim_buf_is_valid(self._float_bufnr) then
    self._float_bufnr = buffer.create_scratch_buffer()
  end
  vim.bo[self._float_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self._float_bufnr, 0, -1, false, { text })
  vim.bo[self._float_bufnr].modifiable = false

  local winhl = resolve_winhighlight(self)
  local winhl_str = ("Normal:%s,NormalFloat:%s"):format(winhl, winhl)

  -- Open or reconfigure the main float.
  if self._float_winid and vim.api.nvim_win_is_valid(self._float_winid) then
    pcall(vim.api.nvim_win_set_config, self._float_winid, {
      relative = "win",
      win = winid,
      row = geom.row,
      col = geom.main_col,
      width = geom.main_width,
      height = 1,
    })
  else
    local ok, new_winid = pcall(vim.api.nvim_open_win, self._float_bufnr, false, {
      relative = "win",
      win = winid,
      row = geom.row,
      col = geom.main_col,
      width = geom.main_width,
      height = 1,
      focusable = false,
      style = "minimal",
      noautocmd = true,
      zindex = ZINDEX,
    })
    if ok then
      self._float_winid = new_winid
      vim.api.nvim_set_option_value("winhighlight", winhl_str, { win = new_winid })
    else
      return
    end
  end

  -- Always re-apply winhighlight (in case the group resolved differently).
  pcall(vim.api.nvim_set_option_value, "winhighlight", winhl_str, { win = self._float_winid })

  -- Apply per-item extmarks via layout's helper.
  -- Rendered highlights assume the text starts at col 0; when we padded or
  -- prefixed the icon inline, shift offsets by that prefix length.
  local leading = 0
  if geom.pad_text then
    leading = leading + #string.rep(" ", G)
  end
  if icon_normalized and not geom.gutter_col then
    leading = leading + #icon_normalized
  end
  if geom.lead_pad_for_right then
    leading = leading + 1
  end
  ---@type flemma.ui.bar.layout.RenderedHighlight[]
  local shifted = {}
  for _, hl in ipairs(rendered.highlights) do
    table.insert(shifted, {
      group = hl.group,
      col_start = hl.col_start + leading,
      col_end = hl.col_end + leading,
    })
  end
  layout.apply_rendered_highlights(self._float_bufnr, NS, shifted)

  -- Gutter-icon float management.
  if geom.gutter_col and geom.gutter_width and icon_normalized then
    self:_render_gutter(winid, geom.row, geom.gutter_width, icon_normalized, winhl_str)
  else
    self:_close_gutter()
  end

  self._last_gutter_width = G

  -- Fire on_shown the first time floats actually open.
  if not self._shown then
    self._shown = true
    if self.on_shown then
      pcall(self.on_shown)
    end
  end
end

---Render (create or reconfigure) the separate gutter-icon float.
---@param parent_winid integer Parent window the float is anchored to
---@param row integer Zero-based row in parent window
---@param width integer Gutter width in columns
---@param icon_normalized string Normalised icon text (with trailing space)
---@param winhl_str string Fully-qualified winhighlight option value
function Bar:_render_gutter(parent_winid, row, width, icon_normalized, winhl_str)
  if not self._gutter_bufnr or not vim.api.nvim_buf_is_valid(self._gutter_bufnr) then
    self._gutter_bufnr = buffer.create_scratch_buffer()
  end
  local icon_display = str.strwidth(icon_normalized)
  local pad = math.max(0, width - icon_display)
  local text = string.rep(" ", pad) .. icon_normalized
  vim.bo[self._gutter_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self._gutter_bufnr, 0, -1, false, { text })
  vim.bo[self._gutter_bufnr].modifiable = false

  if self._gutter_winid and vim.api.nvim_win_is_valid(self._gutter_winid) then
    pcall(vim.api.nvim_win_set_config, self._gutter_winid, {
      relative = "win",
      win = parent_winid,
      row = row,
      col = 0,
      width = width,
      height = 1,
    })
  else
    local ok, new_winid = pcall(vim.api.nvim_open_win, self._gutter_bufnr, false, {
      relative = "win",
      win = parent_winid,
      row = row,
      col = 0,
      width = width,
      height = 1,
      focusable = false,
      style = "minimal",
      noautocmd = true,
      zindex = ZINDEX,
    })
    if ok then
      self._gutter_winid = new_winid
    end
  end
  if self._gutter_winid then
    pcall(vim.api.nvim_set_option_value, "winhighlight", winhl_str, { win = self._gutter_winid })
  end
end

---Close the gutter-icon float if it exists, leaving the buffer handle intact for reuse.
function Bar:_close_gutter()
  if self._gutter_winid and vim.api.nvim_win_is_valid(self._gutter_winid) then
    pcall(vim.api.nvim_win_close, self._gutter_winid, true)
  end
  self._gutter_winid = nil
end

---Close both main and gutter floats if open. Buffers are preserved for reuse.
function Bar:_close_floats()
  if self._float_winid and vim.api.nvim_win_is_valid(self._float_winid) then
    pcall(vim.api.nvim_win_close, self._float_winid, true)
  end
  self._float_winid = nil
  self:_close_gutter()
end

---Install per-bar autocmd group for lifecycle events.
function Bar:_install_autocmds()
  local group = vim.api.nvim_create_augroup(string.format("FlemmaBar_%d", self.id), { clear = true })
  self._autocmd_group = group
  local bar = self -- upvalue captured by the callbacks below

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = group,
    buffer = self.bufnr,
    callback = function()
      bar:dismiss()
    end,
  })

  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = group,
    callback = function()
      if not bar.dismissed then
        bar:_render()
      end
    end,
  })

  -- BufWinEnter can be scoped to a buffer; WinEnter cannot (it is a
  -- window-level event and silently no-ops when `buffer` is passed).
  -- Register them separately so buffer-visibility changes re-render.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = self.bufnr,
    callback = function()
      if not bar.dismissed then
        bar:_render()
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      if bar.dismissed then
        return
      end
      if vim.fn.bufwinid(bar.bufnr) ~= -1 then
        bar:_render()
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = self.bufnr,
    callback = function()
      if not bar.dismissed then
        bar:_close_floats()
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      if bar.dismissed then
        return
      end
      local closed = tonumber(ev.match)
      if closed == bar._float_winid or closed == bar._gutter_winid then
        bar._float_winid = nil
        bar._gutter_winid = nil
        vim.schedule(function()
          if not bar.dismissed then
            bar:_render()
          end
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    buffer = self.bufnr,
    callback = function()
      if bar.dismissed then
        return
      end
      vim.defer_fn(function()
        if bar.dismissed then
          return
        end
        local winid = vim.fn.bufwinid(bar.bufnr)
        if winid == -1 then
          return
        end
        local g = buffer.get_gutter_width(winid)
        if bar._last_gutter_width ~= g then
          bar:_render()
        end
      end, 50)
    end,
  })
end

return M
