--- Background-jobs observability bar.
--- Standalone consumer of hooks — shows active job count in a bottom-right
--- bar and animates a countdown when autopilot auto-resume is scheduled.
---@class flemma.ui.Jobs
local M = {}

local hooks = require("flemma.hooks")
local Bar = require("flemma.ui.bar")
local config_facade = require("flemma.config")
local spinners = require("flemma.ui.spinners")

local SPINNER_INTERVAL_MS = 100
local PRIORITY_COUNT = 100
local PRIORITY_RESUME = 200

local COUNTDOWN_FRAMES = spinners.FRAMES.countdown
local EXECUTING_FRAMES = spinners.FRAMES.tool
local EXECUTING_SPEED = spinners.SPEED.tool

---@class flemma.ui.jobs.BufferState
---@field bar? table Bar handle
---@field count integer Active background job count
---@field spinner_timer? integer vim.fn timer id for executing animation
---@field spinner_tick integer Current spinner tick counter
---@field resume_timer? integer vim.fn timer id for countdown animation
---@field resume_frame integer Current countdown frame index

---@type table<integer, flemma.ui.jobs.BufferState>
local buffer_states = {}

---@param bufnr integer
---@return flemma.ui.jobs.BufferState
local function get_state(bufnr)
  local s = buffer_states[bufnr]
  if not s then
    s = { count = 0, resume_frame = 0, spinner_tick = 0 }
    buffer_states[bufnr] = s
  end
  return s
end

---@param bufnr integer
local function cancel_spinner_timer(bufnr)
  local s = buffer_states[bufnr]
  if s and s.spinner_timer then
    vim.fn.timer_stop(s.spinner_timer)
    s.spinner_timer = nil
    s.spinner_tick = 0
  end
end

---@param bufnr integer
local function cancel_resume_timer(bufnr)
  local s = buffer_states[bufnr]
  if s and s.resume_timer then
    vim.fn.timer_stop(s.resume_timer)
    s.resume_timer = nil
    s.resume_frame = 0
  end
end

---Get the current spinner icon for the executing animation.
---@param s flemma.ui.jobs.BufferState
---@return string|nil
local function get_spinner_icon(s)
  if s.count <= 0 then
    return nil
  end
  local frame_index = (math.floor(s.spinner_tick / EXECUTING_SPEED) % #EXECUTING_FRAMES) + 1
  return EXECUTING_FRAMES[frame_index]
end

---Build segments from current buffer state.
---@param s flemma.ui.jobs.BufferState
---@return flemma.ui.bar.layout.Segment[]
local function build_segments(s)
  ---@type flemma.ui.bar.layout.Segment[]
  local segments = {}
  if s.count > 0 then
    local text = s.count == 1 and "1 job" or (s.count .. " jobs")
    segments[#segments + 1] = {
      key = "jobs",
      items = { { key = "count", text = text, priority = PRIORITY_COUNT } },
    }
  end
  if s.resume_frame > 0 then
    local frame = COUNTDOWN_FRAMES[s.resume_frame] or COUNTDOWN_FRAMES[#COUNTDOWN_FRAMES]
    segments[#segments + 1] = {
      key = "resume",
      items = { { key = "countdown", text = frame .. " Resuming…", priority = PRIORITY_RESUME } },
    }
  end
  return segments
end

---@param bufnr integer
---@return flemma.ui.bar.Position
local function get_position(bufnr)
  return config_facade.get(bufnr).ui.jobs.position
end

---@param bufnr integer
local function ensure_bar(bufnr)
  local s = get_state(bufnr)
  local segments = build_segments(s)
  local icon = get_spinner_icon(s)
  if s.bar and not s.bar:is_dismissed() then
    s.bar:set_icon(icon)
    s.bar:set_segments(segments)
  else
    s.bar = Bar.new({
      bufnr = bufnr,
      position = get_position(bufnr),
      icon = icon,
      segments = segments,
      on_dismiss = function()
        local inner = buffer_states[bufnr]
        if inner then
          inner.bar = nil
        end
      end,
    })
  end
end

---Start the spinner animation timer for a buffer.
---@param bufnr integer
local function start_spinner(bufnr)
  local s = get_state(bufnr)
  if s.spinner_timer then
    return
  end
  s.spinner_tick = 0
  s.spinner_timer = vim.fn.timer_start(SPINNER_INTERVAL_MS, function()
    local inner = buffer_states[bufnr]
    if not inner or not inner.spinner_timer then
      return
    end
    inner.spinner_tick = inner.spinner_tick + 1
    if inner.bar and not inner.bar:is_dismissed() then
      inner.bar:set_icon(get_spinner_icon(inner))
    end
  end, { ["repeat"] = -1 })
end

---@param bufnr integer
local function refresh(bufnr)
  local s = get_state(bufnr)
  if s.count > 0 or s.resume_frame > 0 then
    ensure_bar(bufnr)
    if s.count > 0 then
      start_spinner(bufnr)
    else
      cancel_spinner_timer(bufnr)
    end
  elseif s.bar and not s.bar:is_dismissed() then
    cancel_spinner_timer(bufnr)
    s.bar:dismiss()
  end
end

-- Hook subscriptions

hooks.on("job:submitted", function(data)
  local s = get_state(data.bufnr)
  s.count = data.active_count
  refresh(data.bufnr)
end)

hooks.on("job:completed", function(data)
  local s = get_state(data.bufnr)
  s.count = data.active_count
  refresh(data.bufnr)
end)

hooks.on("autopilot:resume-scheduled", function(data)
  local bufnr = data.bufnr
  cancel_resume_timer(bufnr)
  local s = get_state(bufnr)
  s.resume_frame = 1
  ensure_bar(bufnr)
  local frame_interval = math.max(1, math.floor(data.delay_ms / #COUNTDOWN_FRAMES))
  s.resume_timer = vim.fn.timer_start(frame_interval, function()
    local inner = buffer_states[bufnr]
    if not inner or not inner.resume_timer then
      return
    end
    inner.resume_frame = inner.resume_frame + 1
    if inner.resume_frame > #COUNTDOWN_FRAMES then
      inner.resume_timer = nil
      inner.resume_frame = 0
      refresh(bufnr)
      return
    end
    if inner.bar and not inner.bar:is_dismissed() then
      inner.bar:update({ segments = build_segments(inner) })
    end
  end, { ["repeat"] = #COUNTDOWN_FRAMES - 1 })
end)

hooks.on("autopilot:resume-cancelled", function(data)
  cancel_resume_timer(data.bufnr)
  refresh(data.bufnr)
end)

hooks.on("autopilot:resumed", function(data)
  cancel_resume_timer(data.bufnr)
  local s = get_state(data.bufnr)
  s.resume_frame = 0
  refresh(data.bufnr)
end)

---Clean up all state for a buffer. Called from buffer cleanup hooks.
---@param bufnr integer
function M.cleanup(bufnr)
  cancel_spinner_timer(bufnr)
  cancel_resume_timer(bufnr)
  local s = buffer_states[bufnr]
  if s and s.bar and not s.bar:is_dismissed() then
    s.bar:dismiss()
  end
  buffer_states[bufnr] = nil
end

---Exposed for testing only.
function M._reset()
  for bufnr, _ in pairs(buffer_states) do
    M.cleanup(bufnr)
  end
  buffer_states = {}
end

return M
