--- Cursor movement engine for Flemma chat buffers
--- Centralizes all cursor movement behind a single choke point with
--- idle-aware deferral and focus-stealing prevention.
---@class flemma.Cursor
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")

---@class flemma.cursor.PendingTarget
---@field extmark_id integer Extmark tracking the target position (moves with text)
---@field bottom boolean If true, target is end-of-buffer (resolved at move time)
---@field reason string Logging label from the original request

---@class flemma.cursor.MoveOpts
---@field line integer Target line (1-based)
---@field col? integer Target column (0-based, default 0)
---@field bottom? boolean Target end-of-buffer (resolved at move time, overrides line)
---@field force? boolean Bypass idle timer and heuristics, execute immediately
---@field reason? string Short label for logging (e.g. "response-complete", "spinner/user-send")

local NAMESPACE = vim.api.nvim_create_namespace("flemma_cursor_target")
local EXTMARK_ID = 1

---Format a target description for log messages.
---@param line integer
---@param bottom boolean
---@return string
local function describe_target(line, bottom)
  local parts = "line " .. line
  if bottom then
    parts = parts .. " (bottom)"
  end
  return parts
end

---Execute a cursor move immediately (internal — no heuristics).
---@param bufnr integer
---@param line integer 1-based target line
---@param col integer 0-based target column
---@param reason string Logging label
local function execute_move(bufnr, line, col, reason)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    log.debug("cursor: skipped (" .. reason .. ") — buf " .. bufnr .. " not visible in any window")
    return
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local clamped_line = math.max(1, math.min(line, line_count))
  if clamped_line ~= line then
    log.trace(
      "cursor: clamped line "
        .. line
        .. " → "
        .. clamped_line
        .. " (buf "
        .. bufnr
        .. " has "
        .. line_count
        .. " lines)"
    )
  end
  vim.api.nvim_win_set_cursor(winid, { clamped_line, col })
end

---Clear pending cursor state for a buffer (extmark + pending table).
---Does NOT stop/close the timer — caller handles timer lifecycle.
---@param bufnr integer
local function clear_pending(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.cursor_pending then
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, NAMESPACE, EXTMARK_ID)
    end
    buffer_state.cursor_pending = nil
  end
end

---Evaluate and execute a pending deferred move (called when idle timer fires).
---@param bufnr integer
local function evaluate_pending(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.trace("cursor: idle timer fired but buf " .. bufnr .. " is invalid, skipping")
    return
  end

  local buffer_state = state.get_buffer_state(bufnr)
  local pending = buffer_state.cursor_pending
  if not pending then
    return
  end

  local target_line
  local col = 0

  if pending.bottom then
    target_line = vim.api.nvim_buf_line_count(bufnr)
  else
    -- Read extmark's current position (may have shifted due to buffer mutations)
    local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, NAMESPACE, pending.extmark_id, {})
    if not ok or not pos or #pos < 1 then
      log.debug("cursor: extmark lost (" .. pending.reason .. "), buf " .. bufnr .. " — discarding pending move")
      clear_pending(bufnr)
      return
    end
    target_line = pos[1] + 1 -- 0-indexed → 1-indexed
  end

  log.debug(
    "cursor: executing deferred move ("
      .. pending.reason
      .. ") → "
      .. describe_target(target_line, pending.bottom)
      .. ", buf "
      .. bufnr
  )
  execute_move(bufnr, target_line, col, pending.reason)
  clear_pending(bufnr)
end

-- Testing hook (not part of public API)
M._evaluate_pending = evaluate_pending

---Start or reset the idle timer for a buffer.
---@param buffer_state flemma.state.BufferState
---@param bufnr integer
local function reset_idle_timer(buffer_state, bufnr)
  if not buffer_state.cursor_idle_timer then
    buffer_state.cursor_idle_timer = vim.uv.new_timer()
  end
  local timer = buffer_state.cursor_idle_timer
  ---@cast timer uv.uv_timer_t
  timer:stop()
  timer:start(
    vim.o.updatetime,
    0,
    vim.schedule_wrap(function()
      evaluate_pending(bufnr)
    end)
  )
end

---Request a cursor move for a .chat buffer.
---force=true: execute immediately, clear any pending deferred move.
---force=false (default): place an extmark, start/reset the idle timer.
---Multiple non-forced requests coalesce — last one wins.
---@param bufnr integer
---@param opts flemma.cursor.MoveOpts
function M.request_move(bufnr, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local line = opts.line
  local col = opts.col or 0
  local bottom = opts.bottom or false
  local reason = opts.reason or "unknown"

  if opts.force then
    -- Force path: execute immediately, clear any pending deferred move
    local buffer_state = state.get_buffer_state(bufnr)
    if buffer_state.cursor_pending then
      log.trace(
        "cursor: force move ("
          .. reason
          .. ") clearing pending deferred move ("
          .. buffer_state.cursor_pending.reason
          .. "), buf "
          .. bufnr
      )
    end
    clear_pending(bufnr)
    local timer = buffer_state.cursor_idle_timer
    if timer then
      ---@cast timer uv.uv_timer_t
      timer:stop()
    end

    if bottom then
      line = vim.api.nvim_buf_line_count(bufnr)
    end
    log.debug("cursor: force move (" .. reason .. ") → " .. describe_target(line, bottom) .. ", buf " .. bufnr)
    execute_move(bufnr, line, col, reason)
    return
  end

  -- Deferred path: place extmark, start/reset idle timer
  local buffer_state = state.get_buffer_state(bufnr)

  if buffer_state.cursor_pending then
    log.trace(
      "cursor: deferred move ("
        .. reason
        .. ") supersedes pending ("
        .. buffer_state.cursor_pending.reason
        .. "), buf "
        .. bufnr
    )
  end

  -- Place or update the tracking extmark
  local target_line_0 = bottom and (vim.api.nvim_buf_line_count(bufnr) - 1) or (line - 1)
  target_line_0 = math.max(0, math.min(target_line_0, vim.api.nvim_buf_line_count(bufnr) - 1))

  pcall(vim.api.nvim_buf_set_extmark, bufnr, NAMESPACE, target_line_0, 0, {
    id = EXTMARK_ID,
    right_gravity = false,
  })

  buffer_state.cursor_pending = {
    extmark_id = EXTMARK_ID,
    bottom = bottom,
    reason = reason,
  }

  reset_idle_timer(buffer_state, bufnr)
  log.trace(
    "cursor: deferred move queued (" .. reason .. ") → " .. describe_target(line, bottom) .. ", buf " .. bufnr
  )
end

---Cancel any pending deferred move for a buffer.
---@param bufnr integer
function M.cancel_pending(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.cursor_pending then
    log.debug("cursor: cancel_pending (" .. buffer_state.cursor_pending.reason .. "), buf " .. bufnr)
  end
  local timer = buffer_state.cursor_idle_timer
  if timer then
    ---@cast timer uv.uv_timer_t
    timer:stop()
  end
  clear_pending(bufnr)
end

---Set up cursor engine autocmds and buffer cleanup.
function M.setup()
  local augroup = vim.api.nvim_create_augroup("FlemmaCursor", { clear = true })

  -- Reset idle timer on any user cursor movement in .chat buffers
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    pattern = "*.chat",
    callback = function(ev)
      local bufnr = ev.buf
      local buffer_state = state.get_buffer_state(bufnr)
      if buffer_state.cursor_pending and buffer_state.cursor_idle_timer then
        log.trace(
          "cursor: idle timer reset (CursorMoved), pending ("
            .. buffer_state.cursor_pending.reason
            .. "), buf "
            .. bufnr
        )
        reset_idle_timer(buffer_state, bufnr)
      end
    end,
  })

  -- Register cleanup hook for buffer teardown
  state.register_cleanup("cursor", function(bufnr)
    local buffer_state = state.get_buffer_state(bufnr)
    local timer = buffer_state.cursor_idle_timer
    if timer then
      ---@cast timer uv.uv_timer_t
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
      buffer_state.cursor_idle_timer = nil
      log.trace("cursor: cleanup timer for buf " .. bufnr)
    end
  end)
end

return M
