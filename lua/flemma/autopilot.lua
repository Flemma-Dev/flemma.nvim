--- Per-buffer autopilot state machine for autonomous tool execution loops
--- Manages the cycle: LLM response → tool execution → re-send
---@class flemma.Autopilot
local M = {}

local log = require("flemma.logging")

---@alias flemma.autopilot.State "idle"|"armed"|"sending"|"paused"

---@class flemma.autopilot.BufferState
---@field state flemma.autopilot.State
---@field iteration integer

---@type table<integer, flemma.autopilot.BufferState>
local buffer_states = {}

---Get or initialize autopilot state for a buffer
---@param bufnr integer
---@return flemma.autopilot.BufferState
local function get_state(bufnr)
  if not buffer_states[bufnr] then
    buffer_states[bufnr] = { state = "idle", iteration = 0 }
  end
  return buffer_states[bufnr]
end

---Check whether autopilot is enabled, with per-buffer frontmatter override.
---Priority: frontmatter flemma.opt.tools.autopilot > global config > default (true).
---@param bufnr integer
---@return boolean
function M.is_enabled(bufnr)
  -- Check per-buffer frontmatter override first
  local ok, processor = pcall(require, "flemma.processor")
  if ok then
    local opts = processor.resolve_buffer_opts(bufnr)
    if opts and opts.autopilot ~= nil then
      return opts.autopilot
    end
  end

  local state = require("flemma.state")
  local config = state.get_config()
  if not config.tools then
    return false
  end
  local autopilot = config.tools.autopilot
  if not autopilot then
    return false
  end
  -- Default to true if enabled field is not explicitly set
  if autopilot.enabled == nil then
    return true
  end
  return autopilot.enabled == true
end

---Enable or disable autopilot at runtime by mutating the live config.
---In normal usage config.tools and config.tools.autopilot are always populated
---by setup(); the nil guards are defensive for edge cases (e.g. tests).
---@param enabled boolean
function M.set_enabled(enabled)
  local state = require("flemma.state")
  local config = state.get_config()
  if config.tools and config.tools.autopilot then
    config.tools.autopilot.enabled = enabled
  elseif config.tools then
    config.tools.autopilot = { enabled = enabled, max_turns = 100 }
  end
  log.debug("autopilot: set_enabled(" .. tostring(enabled) .. ")")
end

---Get the current autopilot state for a buffer
---@param bufnr integer
---@return flemma.autopilot.State
function M.get_state(bufnr)
  return get_state(bufnr).state
end

---Set buffer state to armed (tools are executing, will fire on completion)
---@param bufnr integer
function M.arm(bufnr)
  local bs = get_state(bufnr)
  bs.state = "armed"
  log.debug("autopilot: armed buffer " .. bufnr)
end

---Reset buffer state to idle (cancel, error, user abort)
---@param bufnr integer
function M.disarm(bufnr)
  local bs = get_state(bufnr)
  bs.state = "idle"
  bs.iteration = 0
  log.debug("autopilot: disarmed buffer " .. bufnr)
end

---Called after a successful LLM response completes.
---Checks the last assistant message for tool_use segments. If found, arms and
---schedules send_or_execute. If none, stays idle (conversation done).
---@param bufnr integer
function M.on_response_complete(bufnr)
  if not M.is_enabled(bufnr) then
    return
  end

  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  -- Find the last assistant message
  local last_assistant = nil
  for i = #doc.messages, 1, -1 do
    if doc.messages[i].role == "Assistant" then
      last_assistant = doc.messages[i]
      break
    end
  end

  if not last_assistant then
    return
  end

  -- Check for tool_use segments
  local has_tool_use = false
  for _, seg in ipairs(last_assistant.segments) do
    if seg.kind == "tool_use" then
      has_tool_use = true
      break
    end
  end

  if not has_tool_use then
    log.debug("autopilot: no tool_use in last assistant message, staying idle")
    return
  end

  -- Safety: check iteration limit
  local bs = get_state(bufnr)
  bs.iteration = bs.iteration + 1

  local state = require("flemma.state")
  local config = state.get_config()
  local autopilot_config = config.tools and config.tools.autopilot
  local max_turns = (autopilot_config and autopilot_config.max_turns) or 100

  if bs.iteration > max_turns then
    bs.state = "idle"
    vim.notify("Flemma: Autopilot stopped — exceeded " .. max_turns .. " consecutive turns.", vim.log.levels.WARN)
    log.warn("autopilot: exceeded max_turns (" .. max_turns .. ") for buffer " .. bufnr)
    return
  end

  bs.state = "armed"
  log.debug("autopilot: armed buffer " .. bufnr .. " (iteration " .. bs.iteration .. ")")

  -- Schedule send_or_execute for the next event loop tick
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if get_state(bufnr).state ~= "armed" then
      return
    end
    local core = require("flemma.core")
    core.send_or_execute({ bufnr = bufnr })
  end)
end

---Called from executor when all pending tool executions complete (count_pending == 0).
---Checks for remaining flemma:pending or unprocessed tool_uses. If clear,
---sets sending and schedules send_or_execute. If pending remain, sets paused.
---@param bufnr integer
function M.on_tools_complete(bufnr)
  local bs = get_state(bufnr)

  -- Only continue if we're in the armed state
  if bs.state ~= "armed" then
    log.debug("autopilot: on_tools_complete ignored (state=" .. bs.state .. ")")
    return
  end

  local tool_context = require("flemma.tools.context")

  -- Check if there are still unprocessed tool_use blocks (Phase 1 for-loop mid-iteration)
  local pending = tool_context.resolve_all_pending(bufnr)
  if #pending > 0 then
    log.debug("autopilot: " .. #pending .. " unprocessed tool_use blocks remain, waiting")
    return
  end

  -- Check if there are flemma:pending placeholders awaiting user action
  local awaiting = tool_context.resolve_all_awaiting_execution(bufnr)
  if #awaiting > 0 then
    bs.state = "paused"
    log.debug("autopilot: " .. #awaiting .. " flemma:pending placeholders remain, pausing")
    return
  end

  -- All tools resolved — continue the loop
  bs.state = "sending"
  log.debug("autopilot: all tools resolved, scheduling send for buffer " .. bufnr)

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local core = require("flemma.core")
    core.send_or_execute({ bufnr = bufnr })
  end)
end

---Remove all autopilot tracking for a buffer
---@param bufnr integer
function M.cleanup_buffer(bufnr)
  buffer_states[bufnr] = nil
end

return M
