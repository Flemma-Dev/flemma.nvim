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
---@field center boolean Center viewport after moving

---@class flemma.cursor.MoveOpts
---@field line integer Target line (1-based)
---@field col? integer Target column (0-based, default 0)
---@field bottom? boolean Target end-of-buffer (resolved at move time, overrides line)
---@field center? boolean Center the cursor line in the viewport after moving
---@field force? boolean Bypass idle timer and heuristics, execute immediately

local NAMESPACE = vim.api.nvim_create_namespace("flemma_cursor_target")
local EXTMARK_ID = 1

---Execute a cursor move immediately (internal — no heuristics).
---@param bufnr integer
---@param line integer 1-based target line
---@param col integer 0-based target column
---@param center boolean Center the viewport after moving
local function execute_move(bufnr, line, col, center)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  line = math.min(line, line_count)
  line = math.max(line, 1)
  vim.api.nvim_win_set_cursor(winid, { line, col })
  if center then
    vim.fn.win_execute(winid, "normal! zz")
  end
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
      log.debug("cursor: extmark lost for buffer " .. bufnr .. ", discarding pending move")
      clear_pending(bufnr)
      return
    end
    target_line = pos[1] + 1 -- 0-indexed → 1-indexed
  end

  execute_move(bufnr, target_line, col, pending.center)
  log.trace("cursor: deferred move to line " .. target_line .. " in buffer " .. bufnr)
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
  local center = opts.center or false
  local bottom = opts.bottom or false

  if opts.force then
    -- Force path: execute immediately, clear any pending deferred move
    clear_pending(bufnr)
    local buffer_state = state.get_buffer_state(bufnr)
    local timer = buffer_state.cursor_idle_timer
    if timer then
      ---@cast timer uv.uv_timer_t
      timer:stop()
    end

    if bottom then
      line = vim.api.nvim_buf_line_count(bufnr)
    end
    execute_move(bufnr, line, col, center)
    log.trace("cursor: force move to line " .. line .. " in buffer " .. bufnr)
    return
  end

  -- Deferred path: place extmark, start/reset idle timer
  local buffer_state = state.get_buffer_state(bufnr)

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
    center = center,
  }

  reset_idle_timer(buffer_state, bufnr)
  log.trace("cursor: deferred move requested to line " .. line .. " in buffer " .. bufnr)
end

---Cancel any pending deferred move for a buffer.
---@param bufnr integer
function M.cancel_pending(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
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
    end
  end)
end

return M
