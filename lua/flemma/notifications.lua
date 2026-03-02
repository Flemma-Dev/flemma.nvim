--- Flemma notification bar — full-width status lines pinned to the top of chat windows
---@class flemma.Notifications
local M = {}

local ns_id = vim.api.nvim_create_namespace("flemma_notifications_bar")
local border_ns_id = vim.api.nvim_create_namespace("flemma_notifications_border")

---@class flemma.notifications.Notification
---@field win_id integer Floating window ID
---@field bufnr integer Scratch buffer ID
---@field target_bufnr integer Chat buffer this notification belongs to
---@field timer integer|nil Timer ID for auto-dismiss (nil when persistent)
---@field dismissed boolean Whether the notification has been dismissed
---@field render_result flemma.bar.RenderResult Stored for recall and resize re-rendering
---@field segments flemma.bar.Segment[] Source segments for re-rendering on resize
---@field gutter_icon_win? integer Floating window for the gutter icon
---@field gutter_icon_bufnr? integer Scratch buffer for the gutter icon

---@class flemma.notifications.BufferState
---@field notifications flemma.notifications.Notification[] Active notifications (most recent first)
---@field last? { segments: flemma.bar.Segment[] }
---@field gutter_border_win? integer Floating window extending the underline into the gutter
---@field gutter_border_bufnr? integer Scratch buffer for the gutter underline window

--- Per-buffer notification state
---@type table<integer, flemma.notifications.BufferState>
local buffer_state = {}

--- Pending notifications for buffers not currently visible
---@type table<integer, { segments: flemma.bar.Segment[] }[]>
local pending_notifications = {}

--- Merge multiple item width maps, taking the maximum width per key
---@param widths_list table<string, integer>[]
---@return table<string, integer>
local function merge_item_widths(widths_list)
  local merged = {} ---@type table<string, integer>
  for _, widths in ipairs(widths_list) do
    for key, width in pairs(widths) do
      merged[key] = math.max(merged[key] or 0, width)
    end
  end
  return merged
end

--- Compute aligned item widths across all active notifications for a buffer
--- Optionally includes new segments that are about to be added.
---@param target_bufnr integer
---@param new_segments? flemma.bar.Segment[] Segments being added (not yet in buffer_state)
---@return table<string, integer>
local function compute_aligned_widths(target_bufnr, new_segments)
  local bar = require("flemma.bar")
  local widths_list = {} ---@type table<string, integer>[]

  local buf = buffer_state[target_bufnr]
  if buf then
    for _, notif in ipairs(buf.notifications) do
      if not notif.dismissed then
        table.insert(widths_list, bar.measure_item_widths(notif.segments))
      end
    end
  end

  if new_segments then
    table.insert(widths_list, bar.measure_item_widths(new_segments))
  end

  return merge_item_widths(widths_list)
end

--- Get the window ID for a buffer, or nil if not displayed
---@param bufnr integer
---@return integer|nil
local function get_window_for_buffer(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return nil
  end
  return winid
end

--- Get the gutter width (line number, sign, fold columns) for a window
---@param winid integer
---@return integer
local function get_gutter_width(winid)
  local info = vim.fn.getwininfo(winid)
  if info and info[1] then
    return info[1].textoff
  end
  return 0
end

--- Get notification config from state
---@return flemma.Config.Notifications
local function get_config()
  local state = require("flemma.state")
  return state.get_config().notifications
end

--- Check whether the gutter is wide enough to hold the prefix icon
---@param gutter_width integer
---@return boolean
local function gutter_fits_icon(gutter_width)
  local bar = require("flemma.bar")
  return gutter_width >= bar.PREFIX_DISPLAY_WIDTH
end

--- Close the gutter icon window for a notification
---@param notif flemma.notifications.Notification
local function close_gutter_icon(notif)
  if notif.gutter_icon_win and vim.api.nvim_win_is_valid(notif.gutter_icon_win) then
    vim.api.nvim_win_close(notif.gutter_icon_win, true)
  end
  notif.gutter_icon_win = nil
  notif.gutter_icon_bufnr = nil
end

--- Create or reposition the gutter icon floating window for a notification
---@param notif flemma.notifications.Notification
---@param winid integer Parent window ID
---@param gutter_width integer Gutter width in columns
---@param row integer Row offset from window top
local function update_gutter_icon(notif, winid, gutter_width, row)
  local bar = require("flemma.bar")
  local config = get_config()

  -- Build icon text: emoji right-aligned in the gutter with a trailing space
  local icon_text = string.rep(" ", math.max(0, gutter_width - bar.PREFIX_DISPLAY_WIDTH)) .. bar.PREFIX

  if not notif.gutter_icon_bufnr or not vim.api.nvim_buf_is_valid(notif.gutter_icon_bufnr) then
    notif.gutter_icon_bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[notif.gutter_icon_bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(notif.gutter_icon_bufnr, 0, -1, false, { icon_text })
    vim.bo[notif.gutter_icon_bufnr].modifiable = false
    vim.bo[notif.gutter_icon_bufnr].buftype = "nofile"
    vim.bo[notif.gutter_icon_bufnr].bufhidden = "wipe"
    vim.bo[notif.gutter_icon_bufnr].undolevels = -1
  else
    vim.bo[notif.gutter_icon_bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(notif.gutter_icon_bufnr, 0, -1, false, { icon_text })
    vim.bo[notif.gutter_icon_bufnr].modifiable = false
  end

  if notif.gutter_icon_win and vim.api.nvim_win_is_valid(notif.gutter_icon_win) then
    vim.api.nvim_win_set_config(notif.gutter_icon_win, {
      relative = "win",
      win = winid,
      row = row,
      col = 0,
      width = gutter_width,
      height = 1,
    })
  else
    notif.gutter_icon_win = vim.api.nvim_open_win(notif.gutter_icon_bufnr, false, {
      relative = "win",
      win = winid,
      row = row,
      col = 0,
      width = gutter_width,
      height = 1,
      focusable = false,
      style = "minimal",
      noautocmd = true,
      zindex = config.zindex,
    })
    vim.wo[notif.gutter_icon_win].winhighlight = "NormalFloat:FlemmaNotificationsBar"
  end
end

--- Apply extmark highlights to a notification buffer
---@param notification_bufnr integer
---@param highlights flemma.bar.RenderedHighlight[]
local function apply_highlights(notification_bufnr, highlights)
  vim.api.nvim_buf_clear_namespace(notification_bufnr, ns_id, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(notification_bufnr, ns_id, 0, hl.col_start, {
      end_col = hl.col_end,
      hl_group = hl.group,
    })
  end
end

--- Close the gutter border window for a buffer
---@param buf flemma.notifications.BufferState
local function close_gutter_border(buf)
  if buf.gutter_border_win and vim.api.nvim_win_is_valid(buf.gutter_border_win) then
    vim.api.nvim_win_close(buf.gutter_border_win, true)
  end
  buf.gutter_border_win = nil
  buf.gutter_border_bufnr = nil
end

--- Apply bottom border underline on the bottom-most notification.
--- Also manages a gutter-width window to extend the underline across the full window width
--- (matching nvim-treesitter-context's approach).
--- Uses a separate namespace so apply_highlights() cannot clear it.
---@param target_bufnr integer
---@param winid integer Parent window ID
---@param gutter_width integer Gutter width in columns
local function update_bottom_border(target_bufnr, winid, gutter_width)
  local buf = buffer_state[target_bufnr]
  if not buf then
    return
  end

  -- Clear border extmarks from all notification buffers (including gutter icon buffers)
  for _, notif in ipairs(buf.notifications) do
    if not notif.dismissed then
      if vim.api.nvim_buf_is_valid(notif.bufnr) then
        vim.api.nvim_buf_clear_namespace(notif.bufnr, border_ns_id, 0, -1)
      end
      if notif.gutter_icon_bufnr and vim.api.nvim_buf_is_valid(notif.gutter_icon_bufnr) then
        vim.api.nvim_buf_clear_namespace(notif.gutter_icon_bufnr, border_ns_id, 0, -1)
      end
    end
  end

  -- Find the bottom-most (last in list) active notification and its row
  local bottom_notif = nil
  local bottom_row = 0
  local row = 0
  for _, notif in ipairs(buf.notifications) do
    if not notif.dismissed and vim.api.nvim_buf_is_valid(notif.bufnr) then
      bottom_notif = notif
      bottom_row = row
      row = row + 1
    end
  end

  if not bottom_notif then
    close_gutter_border(buf)
    return
  end

  -- Apply underline extmark on the bottom notification buffer
  vim.api.nvim_buf_set_extmark(bottom_notif.bufnr, border_ns_id, 0, 0, {
    end_line = 1,
    hl_group = "FlemmaNotificationsBottom",
    hl_eol = true,
  })

  -- Apply underline to the bottom notification's gutter icon buffer if present
  -- (gutter icon window overlaps gutter_border_win at same zindex, so it needs its own extmark)
  if bottom_notif.gutter_icon_bufnr and vim.api.nvim_buf_is_valid(bottom_notif.gutter_icon_bufnr) then
    vim.api.nvim_buf_set_extmark(bottom_notif.gutter_icon_bufnr, border_ns_id, 0, 0, {
      end_line = 1,
      hl_group = "FlemmaNotificationsBottom",
      hl_eol = true,
    })
  end

  -- Extend underline into the gutter area via a separate floating window
  if gutter_width > 0 then
    local config = get_config()

    if not buf.gutter_border_bufnr or not vim.api.nvim_buf_is_valid(buf.gutter_border_bufnr) then
      buf.gutter_border_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf.gutter_border_bufnr, 0, -1, false, { "" })
      vim.bo[buf.gutter_border_bufnr].modifiable = false
      vim.bo[buf.gutter_border_bufnr].buftype = "nofile"
      vim.bo[buf.gutter_border_bufnr].bufhidden = "wipe"
      vim.bo[buf.gutter_border_bufnr].undolevels = -1
    end

    -- Apply the same underline extmark on the gutter buffer
    vim.api.nvim_buf_clear_namespace(buf.gutter_border_bufnr, border_ns_id, 0, -1)
    vim.api.nvim_buf_set_extmark(buf.gutter_border_bufnr, border_ns_id, 0, 0, {
      end_line = 1,
      hl_group = "FlemmaNotificationsBottom",
      hl_eol = true,
    })

    if buf.gutter_border_win and vim.api.nvim_win_is_valid(buf.gutter_border_win) then
      vim.api.nvim_win_set_config(buf.gutter_border_win, {
        relative = "win",
        win = winid,
        row = bottom_row,
        col = 0,
        width = gutter_width,
        height = 1,
      })
    else
      buf.gutter_border_win = vim.api.nvim_open_win(buf.gutter_border_bufnr, false, {
        relative = "win",
        win = winid,
        row = bottom_row,
        col = 0,
        width = gutter_width,
        height = 1,
        focusable = false,
        style = "minimal",
        noautocmd = true,
        zindex = config.zindex,
      })
      vim.wo[buf.gutter_border_win].winhighlight = "NormalFloat:Normal"
    end
  else
    close_gutter_border(buf)
  end
end

--- Reposition all active notifications for a buffer
--- Most recent is at row 0 (top), older ones shift down.
--- Manages gutter icon windows based on current gutter width.
---@param target_bufnr integer
local function reposition_notifications(target_bufnr)
  local buf = buffer_state[target_bufnr]
  if not buf then
    return
  end

  local winid = get_window_for_buffer(target_bufnr)
  if not winid then
    return
  end

  local win_width = vim.api.nvim_win_get_width(winid)
  local gutter_width = get_gutter_width(winid)
  local text_width = math.max(1, win_width - gutter_width)
  local use_gutter_icon = gutter_fits_icon(gutter_width)

  local row = 0
  for _, notif in ipairs(buf.notifications) do
    if not notif.dismissed and vim.api.nvim_win_is_valid(notif.win_id) then
      vim.api.nvim_win_set_config(notif.win_id, {
        relative = "win",
        win = winid,
        row = row,
        col = gutter_width,
        width = text_width,
        height = 1,
      })

      -- Manage gutter icon: create/reposition when gutter fits, close when it doesn't
      if use_gutter_icon then
        update_gutter_icon(notif, winid, gutter_width, row)
      else
        close_gutter_icon(notif)
      end

      row = row + 1
    end
  end

  update_bottom_border(target_bufnr, winid, gutter_width)
end

--- Dismiss a notification (close window, stop timer, mark dismissed)
---@param notif flemma.notifications.Notification
local function dismiss_notification(notif)
  if notif.dismissed then
    return
  end
  notif.dismissed = true

  if notif.timer then
    vim.fn.timer_stop(notif.timer)
    notif.timer = nil
  end

  close_gutter_icon(notif)

  if vim.api.nvim_win_is_valid(notif.win_id) then
    vim.api.nvim_win_close(notif.win_id, true)
  end
end

--- Enforce the notification limit, dismissing oldest notifications
---@param target_bufnr integer
---@param limit integer
local function enforce_limit(target_bufnr, limit)
  local buf = buffer_state[target_bufnr]
  if not buf then
    return
  end

  -- Count active notifications
  local active = {}
  for _, notif in ipairs(buf.notifications) do
    if not notif.dismissed then
      table.insert(active, notif)
    end
  end

  -- Dismiss oldest (last in list) until within limit
  while #active > limit do
    dismiss_notification(active[#active])
    table.remove(active)
  end

  -- Clean up dismissed notifications from the list
  buf.notifications = vim.tbl_filter(function(n)
    return not n.dismissed
  end, buf.notifications)
end

--- Create a notification bar window
--- Always re-renders segments at the current text area width.
---@param target_bufnr integer
---@param segments flemma.bar.Segment[]
---@param item_widths? table<string, integer> Optional minimum display widths per item key
---@return flemma.notifications.Notification
local function create_notification(target_bufnr, segments, item_widths)
  local config = get_config()

  local winid = get_window_for_buffer(target_bufnr)
  if not winid then
    error("Cannot create notification: buffer not visible")
  end

  local win_width = vim.api.nvim_win_get_width(winid)
  local gutter_width = get_gutter_width(winid)
  local text_width = math.max(1, win_width - gutter_width)
  local use_gutter_icon = gutter_fits_icon(gutter_width)

  -- Render for text area width (excludes gutter); skip prefix when icon is in gutter
  local bar = require("flemma.bar")
  local render_opts = use_gutter_icon and { skip_prefix = true } or nil
  local render_result = bar.render(segments, text_width, item_widths, render_opts)

  -- Create scratch buffer
  local notification_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(notification_bufnr, 0, -1, false, { render_result.text })

  -- Apply highlights
  apply_highlights(notification_bufnr, render_result.highlights)

  -- Set buffer options
  vim.bo[notification_bufnr].modifiable = false
  vim.bo[notification_bufnr].buftype = "nofile"
  vim.bo[notification_bufnr].bufhidden = "wipe"
  vim.bo[notification_bufnr].undolevels = -1

  -- Create floating window positioned after gutter
  local notification_win_id = vim.api.nvim_open_win(notification_bufnr, false, {
    relative = "win",
    win = winid,
    row = 0,
    col = gutter_width,
    width = text_width,
    height = 1,
    focusable = false,
    style = "minimal",
    noautocmd = true,
    zindex = config.zindex,
  })

  -- Set window highlight for distinct background
  vim.wo[notification_win_id].winhighlight = "Normal:FlemmaNotificationsBar"

  -- Build notification object
  ---@type flemma.notifications.Notification
  local notification = {
    win_id = notification_win_id,
    bufnr = notification_bufnr,
    target_bufnr = target_bufnr,
    timer = nil,
    dismissed = false,
    render_result = render_result,
    segments = segments,
  }

  -- Create gutter icon window when gutter is wide enough
  if use_gutter_icon then
    update_gutter_icon(notification, winid, gutter_width, 0)
  end

  -- Set up auto-dismiss timer (unless persistent)
  if config.timeout > 0 then
    notification.timer = vim.fn.timer_start(config.timeout, function()
      dismiss_notification(notification)

      -- Clean up and reposition
      if buffer_state[target_bufnr] then
        buffer_state[target_bufnr].notifications = vim.tbl_filter(function(n)
          return not n.dismissed
        end, buffer_state[target_bufnr].notifications)
        vim.schedule(function()
          reposition_notifications(target_bufnr)
        end)
      end
    end)
  end

  return notification
end

--- Re-render a notification with the current window width
---@param notif flemma.notifications.Notification
---@param win_width integer
---@param item_widths? table<string, integer> Optional minimum display widths per item key
---@param render_opts? flemma.bar.RenderOpts Optional render options (e.g. skip_prefix)
local function rerender_notification(notif, win_width, item_widths, render_opts)
  if notif.dismissed or not vim.api.nvim_buf_is_valid(notif.bufnr) then
    return
  end

  local bar = require("flemma.bar")
  local new_result = bar.render(notif.segments, win_width, item_widths, render_opts)
  notif.render_result = new_result

  vim.bo[notif.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(notif.bufnr, 0, -1, false, { new_result.text })
  vim.bo[notif.bufnr].modifiable = false

  apply_highlights(notif.bufnr, new_result.highlights)
end

--- Show pending notifications when buffer becomes visible
---@param bufnr integer
local function show_pending_for_buffer(bufnr)
  local pending = pending_notifications[bufnr]
  if not pending or #pending == 0 then
    return
  end

  pending_notifications[bufnr] = nil

  for _, notif_data in ipairs(pending) do
    local winid = get_window_for_buffer(bufnr)
    if winid then
      if not buffer_state[bufnr] then
        buffer_state[bufnr] = { notifications = {} }
      end

      -- Compute aligned widths across existing + new notification
      local item_widths = compute_aligned_widths(bufnr, notif_data.segments)

      -- Re-render existing notifications with updated alignment
      local win_width = vim.api.nvim_win_get_width(winid)
      local gutter_width = get_gutter_width(winid)
      local text_width = math.max(1, win_width - gutter_width)
      local render_opts = gutter_fits_icon(gutter_width) and { skip_prefix = true } or nil
      for _, notif in ipairs(buffer_state[bufnr].notifications) do
        rerender_notification(notif, text_width, item_widths, render_opts)
      end

      local notification = create_notification(bufnr, notif_data.segments, item_widths)

      -- Insert at front (most recent first)
      table.insert(buffer_state[bufnr].notifications, 1, notification)
      enforce_limit(bufnr, get_config().limit)
      reposition_notifications(bufnr)
    end
  end
end

--- Show a notification bar for a buffer
---@param segments flemma.bar.Segment[] Segments from usage.build_segments()
---@param bufnr integer Target buffer number
function M.show(segments, bufnr)
  local config = get_config()
  if not config.enabled then
    return
  end

  vim.schedule(function()
    -- Initialize buffer state
    if not buffer_state[bufnr] then
      buffer_state[bufnr] = { notifications = {} }
    end

    -- Store as last for recall
    buffer_state[bufnr].last = { segments = segments }

    -- If buffer not visible, queue for later
    if not get_window_for_buffer(bufnr) then
      if not pending_notifications[bufnr] then
        pending_notifications[bufnr] = {}
      end
      table.insert(pending_notifications[bufnr], { segments = segments })
      return
    end

    -- Compute aligned widths across all active notifications + the new one
    local item_widths = compute_aligned_widths(bufnr, segments)

    -- Re-render existing notifications with updated alignment
    local winid = get_window_for_buffer(bufnr)
    if winid then
      local win_width = vim.api.nvim_win_get_width(winid)
      local gutter_width = get_gutter_width(winid)
      local text_width = math.max(1, win_width - gutter_width)
      local render_opts = gutter_fits_icon(gutter_width) and { skip_prefix = true } or nil
      for _, notif in ipairs(buffer_state[bufnr].notifications) do
        rerender_notification(notif, text_width, item_widths, render_opts)
      end
    end

    local notification = create_notification(bufnr, segments, item_widths)

    -- Insert at front (most recent first)
    table.insert(buffer_state[bufnr].notifications, 1, notification)

    enforce_limit(bufnr, config.limit)
    reposition_notifications(bufnr)
  end)
end

--- Recall last notification for the current buffer
function M.recall_last()
  local current_bufnr = vim.api.nvim_get_current_buf()
  local buf = buffer_state[current_bufnr]

  if not buf or not buf.last then
    vim.notify("No notification for this buffer.", vim.log.levels.WARN)
    return
  end

  -- Check if any notification is still visible
  for _, notif in ipairs(buf.notifications) do
    if not notif.dismissed and vim.api.nvim_win_is_valid(notif.win_id) then
      return -- Already visible, don't duplicate
    end
  end

  M.show(buf.last.segments, current_bufnr)
end

--- Cleanup all notifications for a buffer
---@param bufnr integer
function M.cleanup_buffer(bufnr)
  pending_notifications[bufnr] = nil

  local buf = buffer_state[bufnr]
  if not buf then
    return
  end

  for _, notif in ipairs(buf.notifications) do
    dismiss_notification(notif)
  end

  close_gutter_border(buf)
  buffer_state[bufnr] = nil
end

--- Setup autocmds for notification management
function M.setup()
  local augroup = vim.api.nvim_create_augroup("FlemmaNotifications", { clear = true })

  -- Show pending notifications when buffer becomes visible
  vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      show_pending_for_buffer(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    callback = function(ev)
      show_pending_for_buffer(ev.buf)
    end,
  })

  -- Re-render notifications on window resize
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = augroup,
    callback = function()
      for bufnr, buf in pairs(buffer_state) do
        local winid = get_window_for_buffer(bufnr)
        if winid then
          local win_width = vim.api.nvim_win_get_width(winid)
          local gutter_width = get_gutter_width(winid)
          local text_width = math.max(1, win_width - gutter_width)
          local item_widths = compute_aligned_widths(bufnr)
          local render_opts = gutter_fits_icon(gutter_width) and { skip_prefix = true } or nil
          for _, notif in ipairs(buf.notifications) do
            rerender_notification(notif, text_width, item_widths, render_opts)
          end
          reposition_notifications(bufnr)
        end
      end
    end,
  })
end

return M
