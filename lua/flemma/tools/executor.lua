--- Tool executor
--- Orchestrates tool execution with state management, concurrency control, and result handling
local M = {}

local registry = require("flemma.tools.registry")
local injector = require("flemma.tools.injector")
local state = require("flemma.state")
local log = require("flemma.logging")

--- @class PendingExecution
--- @field tool_id string
--- @field tool_name string
--- @field bufnr integer
--- @field start_line integer
--- @field end_line integer
--- @field cancel_fn function|nil
--- @field started_at integer timestamp
--- @field completed boolean

-- Per-buffer pending executions: bufnr -> { tool_id -> PendingExecution }
local pending_by_buffer = {}

--- Get or initialize the pending map for a buffer
--- @param bufnr integer
--- @return table
local function get_buffer_pending(bufnr)
  if not pending_by_buffer[bufnr] then
    pending_by_buffer[bufnr] = {}
  end
  return pending_by_buffer[bufnr]
end

--- Count pending (non-completed) executions for a buffer
--- @param bufnr integer
--- @return integer
local function count_pending(bufnr)
  local pending = pending_by_buffer[bufnr]
  if not pending then
    return 0
  end
  local n = 0
  for _, entry in pairs(pending) do
    if not entry.completed then
      n = n + 1
    end
  end
  return n
end

--- Lock the buffer if not already locked
--- @param bufnr integer
local function lock_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.bo[bufnr].modifiable = false
  end
end

--- Unlock the buffer if no more pending executions
--- @param bufnr integer
local function maybe_unlock_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) and count_pending(bufnr) == 0 then
    vim.bo[bufnr].modifiable = true
  end
end

--- Clean up a pending execution entry
--- @param bufnr integer
--- @param tool_id string
local function cleanup_pending(bufnr, tool_id)
  local pending = pending_by_buffer[bufnr]
  if pending then
    pending[tool_id] = nil
  end
end

--- Move cursor after result injection based on config
--- @param bufnr integer
--- @param tool_id string
--- @param mode string "result" or "next"
local function move_cursor_after_result(bufnr, tool_id, mode)
  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  local target_line = nil
  for _, msg in ipairs(doc.messages) do
    if msg.role == "You" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" and seg.tool_use_id == tool_id then
          if mode == "result" then
            target_line = seg.position.start_line
          elseif mode == "next" then
            target_line = msg.position.end_line + 1
          end
          break
        end
      end
    end
    if target_line then
      break
    end
  end

  if target_line then
    target_line = math.min(target_line, vim.api.nvim_buf_line_count(bufnr))
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.api.nvim_win_set_cursor(winid, { target_line, 0 })
    end
  end
end

--- Handle completion of a tool execution (success or error)
--- @param bufnr integer
--- @param tool_id string
--- @param result table ExecutionResult {success, output, error}
local function handle_completion(bufnr, tool_id, result)
  local pending = get_buffer_pending(bufnr)
  local entry = pending[tool_id]

  -- Guard against double-completion
  if not entry or entry.completed then
    return
  end
  entry.completed = true

  -- Schedule buffer operations to main thread
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      cleanup_pending(bufnr, tool_id)
      return
    end

    -- Join with placeholder injection as a single undo step
    pcall(vim.cmd, "undojoin")

    -- Inject result into buffer
    local ui = require("flemma.ui")
    local ok, err = injector.inject_result(bufnr, tool_id, result)
    if not ok then
      log.warn("executor: Failed to inject result for " .. tool_id .. ": " .. (err or "unknown"))
    end

    -- Move cursor based on config
    if ok then
      local config = state.get_config()
      local cursor_mode = config.tools and config.tools.cursor_after_result or "result"
      if cursor_mode ~= "stay" then
        move_cursor_after_result(bufnr, tool_id, cursor_mode)
      end
    end

    -- Update indicator
    ui.update_tool_indicator(bufnr, tool_id, result.success)

    -- Brief delay then clear indicator
    vim.defer_fn(function()
      ui.clear_tool_indicator(bufnr, tool_id)
      cleanup_pending(bufnr, tool_id)
      maybe_unlock_buffer(bufnr)
      ui.update_ui(bufnr)
    end, 1500)
  end)
end

--- Execute a tool call
--- @param bufnr integer
--- @param context table ToolContext from context resolver
--- @return boolean success
--- @return string|nil error message
function M.execute(bufnr, context)
  local tool_id = context.tool_id
  local tool_name = context.tool_name

  -- Check for API request in flight (mutually exclusive)
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.current_request then
    return false, "Cannot execute tool while API request is in flight"
  end

  -- Check for duplicate execution
  local pending = get_buffer_pending(bufnr)
  if pending[tool_id] then
    return false, "Tool " .. tool_id .. " is already executing"
  end

  -- Validate tool exists and is executable
  if not registry.is_executable(tool_name) then
    local tool = registry.get(tool_name)
    if not tool then
      return false, "Unknown tool: " .. tool_name
    end
    return false, "Tool '" .. tool_name .. "' is not executable"
  end

  local executor_fn, is_async = registry.get_executor(tool_name)
  if not executor_fn then
    return false, "No executor found for tool: " .. tool_name
  end

  -- Create pending entry
  pending[tool_id] = {
    tool_id = tool_id,
    tool_name = tool_name,
    bufnr = bufnr,
    start_line = context.start_line,
    end_line = context.end_line,
    cancel_fn = nil,
    started_at = os.time(),
    completed = false,
  }

  -- Lock buffer
  lock_buffer(bufnr)

  -- Phase 1: Inject placeholder
  local header_line, inject_err = injector.inject_placeholder(bufnr, tool_id)
  if not header_line then
    cleanup_pending(bufnr, tool_id)
    maybe_unlock_buffer(bufnr)
    return false, "Failed to inject placeholder: " .. (inject_err or "unknown")
  end

  -- Show execution indicator
  local ui = require("flemma.ui")
  local config = state.get_config()
  if not config.tools or config.tools.show_spinner ~= false then
    ui.show_tool_indicator(bufnr, tool_id, header_line)
  end

  -- Update UI to reflect changes
  ui.update_ui(bufnr)

  -- Execute the tool
  if is_async then
    -- Async execution with callback
    local callback_called = false
    local function callback(result)
      if callback_called then
        return
      end
      callback_called = true
      result = result or { success = false, error = "Tool returned no result" }
      handle_completion(bufnr, tool_id, result)
    end

    local ok, cancel_or_err = pcall(executor_fn, context.input, callback)
    if not ok then
      -- Executor threw before starting async work
      handle_completion(bufnr, tool_id, {
        success = false,
        error = tostring(cancel_or_err),
      })
      return true, nil -- We handled the error
    end

    -- Store cancel function if returned
    if type(cancel_or_err) == "function" then
      pending[tool_id].cancel_fn = cancel_or_err
    end
  else
    -- Sync execution
    local ok, result = pcall(executor_fn, context.input)
    if not ok then
      handle_completion(bufnr, tool_id, {
        success = false,
        error = tostring(result),
      })
    elseif not result then
      handle_completion(bufnr, tool_id, {
        success = false,
        error = "Tool returned no result",
      })
    else
      handle_completion(bufnr, tool_id, result)
    end
  end

  return true, nil
end

--- Cancel a pending execution
--- @param tool_id string
--- @return boolean cancelled true if cancelled, false if not found
function M.cancel(tool_id)
  for bufnr, pending in pairs(pending_by_buffer) do
    local entry = pending[tool_id]
    if entry and not entry.completed then
      -- Call cancel function if available
      if entry.cancel_fn then
        pcall(entry.cancel_fn)
      end

      -- Record cancellation as error result
      handle_completion(bufnr, tool_id, {
        success = false,
        error = "User aborted tool execution.",
      })
      return true
    end
  end
  return false
end

--- Cancel all pending executions for a buffer
--- @param bufnr integer
function M.cancel_all(bufnr)
  local pending = pending_by_buffer[bufnr]
  if not pending then
    return
  end

  -- Collect tool_ids to cancel (don't modify during iteration)
  local to_cancel = {}
  for tool_id, entry in pairs(pending) do
    if not entry.completed then
      table.insert(to_cancel, tool_id)
    end
  end

  for _, tool_id in ipairs(to_cancel) do
    M.cancel(tool_id)
  end
end

--- Get pending executions for a buffer
--- @param bufnr integer
--- @return PendingExecution[]
function M.get_pending(bufnr)
  local pending = pending_by_buffer[bufnr]
  if not pending then
    return {}
  end

  local result = {}
  for _, entry in pairs(pending) do
    if not entry.completed then
      table.insert(result, entry)
    end
  end
  return result
end

--- Clean up all state for a buffer (called on buffer close)
--- @param bufnr integer
function M.cleanup_buffer(bufnr)
  local pending = pending_by_buffer[bufnr]
  if pending then
    for _, entry in pairs(pending) do
      if entry.cancel_fn and not entry.completed then
        pcall(entry.cancel_fn)
      end
    end
  end
  pending_by_buffer[bufnr] = nil
end

return M
