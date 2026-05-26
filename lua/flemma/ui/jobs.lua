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

local MIDDLE_DOT = " · "
local COUNTDOWN_FRAMES = spinners.FRAMES.countdown
local EXECUTING_FRAMES = spinners.FRAMES.tool
local EXECUTING_SPEED = spinners.SPEED.tool

local COUNTDOWN_SPEED = spinners.SPEED.countdown

---@class flemma.ui.jobs.BufferState
---@field bar? table Bar handle
---@field count integer Active background job count
---@field animation_timer? integer vim.fn timer id for the shared 100ms tick loop
---@field animation_tick integer Current tick counter (drives all frame selection)
---@field resume_delay_ms? integer Total resume delay in milliseconds
---@field resume_started_at? integer High-resolution start timestamp (vim.uv.hrtime)

---@type table<integer, flemma.ui.jobs.BufferState>
local buffer_states = {}

---@param bufnr integer
---@return flemma.ui.jobs.BufferState
local function get_state(bufnr)
  local s = buffer_states[bufnr]
  if not s then
    s = { count = 0, animation_tick = 0 }
    buffer_states[bufnr] = s
  end
  return s
end

---@param bufnr integer
local function cancel_animation_timer(bufnr)
  local s = buffer_states[bufnr]
  if s and s.animation_timer then
    vim.fn.timer_stop(s.animation_timer)
    s.animation_timer = nil
    s.animation_tick = 0
  end
end

---@param bufnr integer
local function clear_resume(bufnr)
  local s = buffer_states[bufnr]
  if s then
    s.resume_delay_ms = nil
    s.resume_started_at = nil
  end
end

---Compute seconds remaining until resume fires.
---@param s flemma.ui.jobs.BufferState
---@return number
local function get_resume_remaining(s)
  if not s.resume_started_at or not s.resume_delay_ms then
    return 0
  end
  local elapsed_ms = (vim.uv.hrtime() - s.resume_started_at) / 1e6
  return math.max(0, (s.resume_delay_ms - elapsed_ms) / 1000)
end

---Get the current frame for a spinner phase from the shared tick counter.
---@param s flemma.ui.jobs.BufferState
---@param frames string[]
---@param speed integer
---@return string
local function get_frame(s, frames, speed)
  local frame_index = (math.floor(s.animation_tick / speed) % #frames) + 1
  return frames[frame_index]
end

---Build segments from current buffer state.
---@param s flemma.ui.jobs.BufferState
---@return flemma.ui.bar.layout.Segment[]
local function build_segments(s)
  ---@type flemma.ui.bar.layout.Segment[]
  local segments = {}
  if s.resume_started_at then
    local frame = get_frame(s, COUNTDOWN_FRAMES, COUNTDOWN_SPEED)
    local remaining = string.format("%.1fs", get_resume_remaining(s))
    segments[#segments + 1] = {
      key = "resume",
      items = {
        { key = "countdown", text = frame .. " Resuming…" .. MIDDLE_DOT .. remaining, priority = PRIORITY_RESUME },
      },
    }
  end
  if s.count > 0 then
    local label = s.count == 1 and "1 job" or (s.count .. " jobs")
    local frame = get_frame(s, EXECUTING_FRAMES, EXECUTING_SPEED)
    segments[#segments + 1] = {
      key = "jobs",
      items = { { key = "count", text = frame .. " " .. label, priority = PRIORITY_COUNT } },
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
  if s.bar and not s.bar:is_dismissed() then
    s.bar:set_segments(segments)
  else
    s.bar = Bar.new({
      bufnr = bufnr,
      position = get_position(bufnr),
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

---Start the shared animation timer for a buffer.
---@param bufnr integer
local function start_animation(bufnr)
  local s = get_state(bufnr)
  if s.animation_timer then
    return
  end
  s.animation_tick = 0
  s.animation_timer = vim.fn.timer_start(SPINNER_INTERVAL_MS, function()
    local inner = buffer_states[bufnr]
    if not inner or not inner.animation_timer then
      return
    end
    inner.animation_tick = inner.animation_tick + 1
    if inner.resume_started_at and get_resume_remaining(inner) <= 0 then
      inner.resume_started_at = nil
      inner.resume_delay_ms = nil
    end
    if inner.count <= 0 and not inner.resume_started_at then
      cancel_animation_timer(bufnr)
      if inner.bar and not inner.bar:is_dismissed() then
        inner.bar:dismiss()
      end
      return
    end
    if inner.bar and not inner.bar:is_dismissed() then
      inner.bar:set_segments(build_segments(inner))
    end
  end, { ["repeat"] = -1 })
end

---@param bufnr integer
local function refresh(bufnr)
  local s = get_state(bufnr)
  if s.count > 0 or s.resume_started_at then
    ensure_bar(bufnr)
    start_animation(bufnr)
  else
    cancel_animation_timer(bufnr)
    if s.bar and not s.bar:is_dismissed() then
      s.bar:dismiss()
    end
  end
end

function M.setup()
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
    local s = get_state(data.bufnr)
    s.resume_delay_ms = data.delay_ms
    s.resume_started_at = vim.uv.hrtime()
    refresh(data.bufnr)
  end)

  hooks.on("autopilot:resume-cancelled", function(data)
    clear_resume(data.bufnr)
    refresh(data.bufnr)
  end)

  hooks.on("autopilot:resumed", function(data)
    clear_resume(data.bufnr)
    refresh(data.bufnr)
  end)
end

---Clean up all state for a buffer. Called from the buffer:destroyed hook.
---@param bufnr integer
function M.cleanup(bufnr)
  cancel_animation_timer(bufnr)
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
