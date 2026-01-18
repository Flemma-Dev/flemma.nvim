--- Flemma notification functionality
local M = {}


-- Per-buffer notifications: { [bufnr] = { notifications = {...}, ... } }
local buffer_notifications = {}

-- Pending notifications for buffers not currently visible (e.g., in another tab)
-- { [bufnr] = { { msg = ..., opts = ... }, ... } }
local pending_notifications = {}

-- Default notification options
M.default_opts = {
  enabled = true,
  timeout = 8000,
  max_width = 60,
  padding = 1,
  border = "rounded",
  title = nil,
}

-- Get the window ID for a buffer, or nil if buffer is not displayed
local function get_window_for_buffer(bufnr)
  if not bufnr then
    return nil
  end
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return nil
  end
  return winid
end

-- Reposition all active notifications for a specific buffer
local function reposition_notifications(bufnr)
  local buf_notifs = buffer_notifications[bufnr]
  if not buf_notifs then
    return
  end

  local winid = get_window_for_buffer(bufnr)
  if not winid then
    return
  end

  local win_width = vim.api.nvim_win_get_width(winid)
  local row = 1

  for _, notif in ipairs(buf_notifs.notifications) do
    if notif.valid and vim.api.nvim_win_is_valid(notif.win_id) then
      vim.api.nvim_win_set_config(notif.win_id, {
        relative = "win",
        win = winid,
        row = row,
        col = win_width - notif.width - 2,
      })
      row = row + notif.height + 1
    end
  end
end

-- Create a notification window for a specific buffer
local function create_notification(msg, opts, target_bufnr)
  -- Get the window for the target buffer
  local winid = get_window_for_buffer(target_bufnr)
  if not winid then
    -- Buffer is not displayed, fall back to editor-relative positioning
    winid = nil
  end

  -- Split message into lines and calculate max line length
  local msg_lines = vim.split(msg, "\n", { plain = true })
  local lines = {}
  local max_line_length = 0

  -- Process each line separately for wrapping if needed
  for _, msg_line in ipairs(msg_lines) do
    if msg_line == "" then
      table.insert(lines, "")
    else
      -- If line is longer than max_width, wrap it
      if #msg_line > opts.max_width then
        local current_line = ""
        for word in msg_line:gmatch("%S+") do
          if #current_line + #word + 1 <= opts.max_width then
            current_line = current_line == "" and word or current_line .. " " .. word
          else
            table.insert(lines, current_line)
            max_line_length = math.max(max_line_length, #current_line)
            current_line = word
          end
        end
        if current_line ~= "" then
          table.insert(lines, current_line)
          max_line_length = math.max(max_line_length, #current_line)
        end
      else
        -- Line fits within max_width, keep it as is
        table.insert(lines, msg_line)
        max_line_length = math.max(max_line_length, #msg_line)
      end
    end
  end

  -- Add padding to each line
  local padded_lines = {}
  local padding_str = string.rep(" ", opts.padding)
  for _, line in ipairs(lines) do
    if line:match("%S") then
      table.insert(padded_lines, padding_str .. line .. padding_str)
    else
      table.insert(padded_lines, line) -- Keep empty lines as-is
    end
  end

  -- Calculate dimensions - use actual content width but respect screen/window bounds
  local available_width = winid and vim.api.nvim_win_get_width(winid) or vim.o.columns
  local width = math.min(max_line_length + (opts.padding * 2), available_width - 4)
  local height = #padded_lines

  -- Calculate initial position (will be adjusted by reposition)
  local row = 1
  local col = available_width - width - 2

  -- Create buffer for the notification
  local notify_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(notify_bufnr, 0, -1, false, padded_lines)

  -- Set buffer options
  vim.api.nvim_buf_set_option(notify_bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(notify_bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(notify_bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(notify_bufnr, "filetype", "flemma_notify")
  -- Remove markdown parser since we're using our own syntax
  vim.treesitter.stop(notify_bufnr)

  -- Create window with title if provided
  local win_opts = {
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.border,
    noautocmd = true,
  }

  -- Position relative to buffer's window if available, otherwise editor
  if winid then
    win_opts.relative = "win"
    win_opts.win = winid
  else
    win_opts.relative = "editor"
  end

  if opts.title then
    win_opts.title = opts.title
    win_opts.title_pos = "center"
  end

  local notify_win_id = vim.api.nvim_open_win(notify_bufnr, false, win_opts)

  -- Set window options
  vim.api.nvim_win_set_option(notify_win_id, "wrap", true)
  vim.api.nvim_win_set_option(notify_win_id, "winblend", 15)
  vim.api.nvim_win_set_option(notify_win_id, "conceallevel", 3)
  vim.api.nvim_win_set_option(notify_win_id, "concealcursor", "nvic")

  -- Initialize per-buffer notifications table if needed
  if target_bufnr and not buffer_notifications[target_bufnr] then
    buffer_notifications[target_bufnr] = { notifications = {} }
  end

  -- Create notification object first
  local notification = {
    win_id = notify_win_id,
    bufnr = notify_bufnr,
    target_bufnr = target_bufnr, -- The buffer this notification belongs to
    height = height,
    width = width,
    dismissed = false,
    valid = true,
    timer = nil, -- Will be set after object creation
  }

  -- Now set up the timer with access to the notification object
  notification.timer = vim.fn.timer_start(opts.timeout, function()
    if vim.api.nvim_win_is_valid(notify_win_id) then
      vim.api.nvim_win_close(notify_win_id, true)
    end
    notification.valid = false
    notification.dismissed = true

    -- Clean up notifications list and reposition remaining ones
    if target_bufnr and buffer_notifications[target_bufnr] then
      buffer_notifications[target_bufnr].notifications = vim.tbl_filter(function(n)
        return not n.dismissed
      end, buffer_notifications[target_bufnr].notifications)

      reposition_notifications(target_bufnr)
    end
  end)

  -- Store in per-buffer notifications
  if target_bufnr then
    table.insert(buffer_notifications[target_bufnr].notifications, notification)
    reposition_notifications(target_bufnr)
  end

  return notification
end

-- Show pending notifications for a buffer (called when buffer becomes visible)
local function show_pending_for_buffer(bufnr)
  local pending = pending_notifications[bufnr]
  if not pending or #pending == 0 then
    return
  end

  -- Clear pending list before showing (to avoid re-entrancy)
  pending_notifications[bufnr] = nil

  -- Show each pending notification
  for _, notif in ipairs(pending) do
    create_notification(notif.msg, notif.opts, bufnr)
  end
end

-- Show a notification if enabled
-- @param msg string - The message to display
-- @param opts table - Options (merged with default_opts)
-- @param bufnr number|nil - Buffer number to anchor notification to (nil = editor-relative)
function M.show(msg, opts, bufnr)
  -- Merge with default options
  local final_opts = vim.tbl_deep_extend("force", M.default_opts, opts or {})

  -- Check if notifications are enabled
  if not final_opts.enabled then
    return
  end

  vim.schedule(function()
    -- If buffer is specified but not visible, queue for later
    if bufnr and not get_window_for_buffer(bufnr) then
      if not pending_notifications[bufnr] then
        pending_notifications[bufnr] = {}
      end
      table.insert(pending_notifications[bufnr], { msg = msg, opts = final_opts })
      -- Store as last for this buffer (for recall)
      if not buffer_notifications[bufnr] then
        buffer_notifications[bufnr] = { notifications = {} }
      end
      buffer_notifications[bufnr].last = { message = msg, options = final_opts, ref = nil }
      return
    end

    local notif = create_notification(msg, final_opts, bufnr)

    -- Store as last notification for this buffer (for recall)
    if bufnr then
      if not buffer_notifications[bufnr] then
        buffer_notifications[bufnr] = { notifications = {} }
      end
      buffer_notifications[bufnr].last = { message = msg, options = final_opts, ref = notif }
    end
  end)
end

-- Check if a notification is still visible on screen
local function is_notification_visible(notif)
  if not notif then
    return false
  end
  return notif.valid and not notif.dismissed and notif.win_id and vim.api.nvim_win_is_valid(notif.win_id)
end

-- Function to recall last notification for the current buffer
function M.recall_last()
  local current_bufnr = vim.api.nvim_get_current_buf()
  local buf_state = buffer_notifications[current_bufnr]

  if not buf_state or not buf_state.last then
    vim.notify("No notification for this buffer.", vim.log.levels.WARN)
    return
  end

  local last = buf_state.last

  -- Don't show again if already visible
  if is_notification_visible(last.ref) then
    return
  end

  M.show(last.message, last.options, current_bufnr)
end

-- Cleanup notifications for a specific buffer
-- Called when a buffer is deleted to close any pending notifications
function M.cleanup_buffer(bufnr)
  -- Clear any pending notifications
  pending_notifications[bufnr] = nil

  local buf_notifs = buffer_notifications[bufnr]
  if not buf_notifs then
    return
  end

  -- Close all notification windows and stop timers
  for _, notif in ipairs(buf_notifs.notifications) do
    if notif.timer then
      vim.fn.timer_stop(notif.timer)
    end
    if notif.win_id and vim.api.nvim_win_is_valid(notif.win_id) then
      vim.api.nvim_win_close(notif.win_id, true)
    end
    notif.valid = false
    notif.dismissed = true
  end

  -- Remove the buffer's entry
  buffer_notifications[bufnr] = nil
end

-- Setup autocmds to show pending notifications when buffer becomes visible
function M.setup()
  local augroup = vim.api.nvim_create_augroup("FlemmaNotify", { clear = true })

  -- WinEnter fires when entering a window (including tab switches)
  -- Check if the buffer in this window has pending notifications
  vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      show_pending_for_buffer(bufnr)
    end,
  })

  -- Also check on BufWinEnter for when a buffer is first displayed
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    callback = function(ev)
      show_pending_for_buffer(ev.buf)
    end,
  })
end

return M
