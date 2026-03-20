--- Per-buffer autopilot state machine for autonomous tool execution loops
--- Manages the cycle: LLM response → tool execution → re-send
---@class flemma.Autopilot
local M = {}

local config_facade = require("flemma.config")
local log = require("flemma.logging")
local bridge = require("flemma.bridge")
local cursor = require("flemma.cursor")
local parser = require("flemma.parser")
local state = require("flemma.state")
local tool_context = require("flemma.tools.context")

---@alias flemma.autopilot.State "idle"|"armed"|"sending"|"paused"

---@class flemma.autopilot.BufferState
---@field state flemma.autopilot.State
---@field iteration integer

---Get or initialize autopilot state for a buffer
---@param bufnr integer
---@return flemma.autopilot.BufferState
local function get_state(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if not buffer_state.autopilot then
    buffer_state.autopilot = { state = "idle", iteration = 0 }
  end
  return buffer_state.autopilot
end

---Check whether autopilot is enabled for a buffer.
---Reads from the config facade which resolves through all layers (defaults →
---setup → runtime → frontmatter). No separate override needed.
---@param bufnr integer
---@return boolean
function M.is_enabled(bufnr)
  local cfg = config_facade.materialize(bufnr)
  return cfg.tools.autopilot.enabled == true
end

---Enable or disable autopilot at runtime via the config facade.
---Writes to the RUNTIME layer so the change persists across re-materializations
---and is visible in :Flemma status as a runtime override.
---@param enabled boolean
function M.set_enabled(enabled)
  local w = config_facade.writer(nil, config_facade.LAYERS.RUNTIME)
  w.tools.autopilot.enabled = enabled
  state.set_config(config_facade.materialize())
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

  local cfg = config_facade.materialize(bufnr)
  local max_turns = cfg.tools.autopilot.max_turns

  if bs.iteration > max_turns then
    bs.state = "idle"
    vim.notify("Flemma: Autopilot stopped – exceeded " .. max_turns .. " consecutive turns.", vim.log.levels.WARN)
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
    -- Guard against a parallel on_tools_complete path that already dispatched a request
    if state.get_buffer_state(bufnr).current_request then
      return
    end
    bridge.send_or_execute({ bufnr = bufnr })
  end)
end

---Called from executor when all pending tool executions complete (count_pending == 0).
---Checks for remaining flemma:tool blocks or unprocessed tool_uses. If clear,
---sets sending and schedules send_or_execute. If pending remain, sets paused.
---@param bufnr integer
function M.on_tools_complete(bufnr)
  local bs = get_state(bufnr)

  -- Only continue if we're in the armed state
  if bs.state ~= "armed" then
    log.debug("autopilot: on_tools_complete ignored (state=" .. bs.state .. ")")
    return
  end

  -- Check if there are still unprocessed tool_use blocks (Phase 1 for-loop mid-iteration)
  local unmatched = tool_context.resolve_all_pending(bufnr)
  if #unmatched > 0 then
    log.debug("autopilot: " .. #unmatched .. " unprocessed tool_use blocks remain, waiting")
    return
  end

  -- Check for flemma:tool blocks by status
  local tool_blocks = tool_context.resolve_all_tool_blocks(bufnr)
  -- Only pause for empty pending blocks — user-filled ones will be resolved on send
  local first_empty_pending = nil
  for _, ctx in ipairs(tool_blocks["pending"] or {}) do
    if not ctx.has_content then
      first_empty_pending = ctx
      break
    end
  end
  local has_actionable = (tool_blocks["approved"] and #tool_blocks["approved"] > 0)
    or (tool_blocks["denied"] and #tool_blocks["denied"] > 0)
    or (tool_blocks["rejected"] and #tool_blocks["rejected"] > 0)

  if first_empty_pending then
    bs.state = "paused"
    log.debug("autopilot: flemma:tool status=pending blocks remain, pausing")
    cursor.request_move(bufnr, { line = first_empty_pending.tool_result.start_line, reason = "autopilot/pending-tool" })
    return
  end

  if has_actionable then
    -- Approved/denied/rejected blocks remain — schedule send_or_execute to process them
    bs.state = "sending"
    log.debug("autopilot: actionable flemma:tool blocks remain, scheduling send for buffer " .. bufnr)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      if state.get_buffer_state(bufnr).current_request then
        return
      end
      bridge.send_or_execute({ bufnr = bufnr })
    end)
    return
  end

  -- All tools resolved — continue the loop
  bs.state = "sending"
  log.debug("autopilot: all tools resolved, scheduling send for buffer " .. bufnr)

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if state.get_buffer_state(bufnr).current_request then
      return
    end
    bridge.send_or_execute({ bufnr = bufnr })
  end)
end

---Reset autopilot tracking for a buffer (used by tests for isolation)
---@param bufnr integer
function M.cleanup_buffer(bufnr)
  state.get_buffer_state(bufnr).autopilot = nil
end

return M
