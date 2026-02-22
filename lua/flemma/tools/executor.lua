--- Tool executor
--- Orchestrates tool execution with state management, concurrency control, and result handling
---@class flemma.tools.Executor
local M = {}

local registry = require("flemma.tools.registry")
local injector = require("flemma.tools.injector")
local state = require("flemma.state")
local log = require("flemma.logging")

---@class flemma.tools.PendingExecution
---@field tool_id string
---@field tool_name string
---@field bufnr integer
---@field start_line integer
---@field end_line integer
---@field cancel_fn function|nil
---@field started_at integer timestamp
---@field completed boolean
---@field placeholder_modified boolean

-- Per-buffer pending executions: bufnr -> { tool_id -> flemma.tools.PendingExecution }
local pending_by_buffer = {}

---Get or initialize the pending map for a buffer
---@param bufnr integer
---@return table<string, flemma.tools.PendingExecution>
local function get_buffer_pending(bufnr)
  if not pending_by_buffer[bufnr] then
    pending_by_buffer[bufnr] = {}
  end
  return pending_by_buffer[bufnr]
end

---Count executions that have not been cleaned up yet for a buffer.
---Uses table presence (removed by cleanup_pending) rather than the completed
---flag, so that simultaneous async completions don't cause premature unlock.
---@param bufnr integer
---@return integer
local function count_pending(bufnr)
  local pending = pending_by_buffer[bufnr]
  if not pending then
    return 0
  end
  local n = 0
  for _ in pairs(pending) do
    n = n + 1
  end
  return n
end

---Unlock the buffer if no more tools are actively executing
---@param bufnr integer
local function maybe_unlock_buffer(bufnr)
  if count_pending(bufnr) == 0 then
    state.unlock_buffer(bufnr)
    -- Notify autopilot that all tool executions have completed
    require("flemma.autopilot").on_tools_complete(bufnr)
  end
end

---Check whether any tool executions are still in-flight for a buffer
---@param bufnr integer
---@return boolean
function M.has_pending(bufnr)
  return count_pending(bufnr) > 0
end

---Clean up a pending execution entry
---@param bufnr integer
---@param tool_id string
local function cleanup_pending(bufnr, tool_id)
  local pending = pending_by_buffer[bufnr]
  if pending then
    pending[tool_id] = nil
  end
end

---Move cursor after result injection based on config
---@param bufnr integer
---@param tool_id string
---@param mode string "result" or "next"
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

---Perform the actual completion work: inject result, move cursor, update UI
---@param bufnr integer
---@param tool_id string
---@param result flemma.tools.ExecutionResult
---@param opts? { async?: boolean } whether completion was scheduled via vim.schedule
local function do_completion(bufnr, tool_id, result, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    cleanup_pending(bufnr, tool_id)
    return
  end

  local pending = get_buffer_pending(bufnr)
  local entry = pending[tool_id]

  -- For async tools, join with placeholder injection as a single undo step
  -- only when the placeholder actually modified the buffer.
  -- For sync tools, all changes are already in one undo block (same handler),
  -- and calling undojoin would incorrectly merge with the PREVIOUS handler's block.
  opts = opts or {}
  if opts.async and entry and entry.placeholder_modified then
    pcall(vim.cmd --[[@as function]], "undojoin")
  end

  -- Inject result into buffer
  local ui = require("flemma.ui")
  local ok, err = injector.inject_result(bufnr, tool_id, result)
  if not ok then
    log.warn("executor: Failed to inject result for " .. tool_id .. ": " .. (err or "unknown"))
  end

  -- Move cursor based on config (skip when autopilot is armed — it owns cursor positioning)
  if ok and require("flemma.autopilot").get_state(bufnr) ~= "armed" then
    local config = state.get_config()
    local cursor_mode = config.tools and config.tools.cursor_after_result or "result"
    if cursor_mode ~= "stay" then
      move_cursor_after_result(bufnr, tool_id, cursor_mode)
    end
  end

  -- Result injection may have displaced other tools' extmarks
  ui.reposition_tool_indicators(bufnr)

  -- Update indicator
  ui.update_tool_indicator(bufnr, tool_id, result.success)

  -- Free pending slot immediately so tool can be re-executed
  cleanup_pending(bufnr, tool_id)

  -- Unlock buffer if no more tools are actively executing.
  -- This must happen BEFORE scheduling indicator clear, so the buffer
  -- is editable and the on_lines listener can detect user edits.
  maybe_unlock_buffer(bufnr)

  -- Auto-dismiss indicator after delay (or immediately on user edit)
  ui.schedule_tool_indicator_clear(bufnr, tool_id, 1500)

  ui.update_ui(bufnr)
end

---Handle completion of a tool execution (success or error)
---For sync tools, completes inline. For async tools, schedules to main thread.
---@param bufnr integer
---@param tool_id string
---@param result flemma.tools.ExecutionResult
---@param opts {async: boolean}
local function handle_completion(bufnr, tool_id, result, opts)
  local pending = get_buffer_pending(bufnr)
  local entry = pending[tool_id]

  -- Guard against double-completion
  if not entry or entry.completed then
    return
  end
  entry.completed = true

  if opts.async then
    vim.schedule(function()
      do_completion(bufnr, tool_id, result, { async = true })
    end)
  else
    do_completion(bufnr, tool_id, result)
  end
end

local DEFAULT_TIMEOUT = 30

---@class flemma.tools.ExecutionContextParams
---@field bufnr integer Buffer number
---@field cwd string Resolved working directory
---@field timeout? integer Default timeout in seconds (defaults to DEFAULT_TIMEOUT)
---@field tool_name string Name of the tool being executed (for get_config lookup)
---@field __dirname? string Directory containing the .chat buffer
---@field __filename? string Full path of the .chat buffer
---@field opts? flemma.opt.ResolvedOpts Per-buffer resolved options (captured by sandbox closures)

---Build an ExecutionContext with lazy-loaded sandbox/truncate/path namespaces.
---Sandbox, truncate, and path are loaded on first access via __index and then
---cached via rawset so subsequent accesses bypass the metamethod.
---@param params flemma.tools.ExecutionContextParams
---@return flemma.tools.ExecutionContext
function M.build_execution_context(params)
  local bufnr = params.bufnr
  local opts = params.opts
  local tool_name = params.tool_name
  local dirname = params.__dirname

  -- Core data fields. Namespace fields (sandbox, truncate, path) are added via
  -- __index metamethod; get_config is defined as a method below.
  local context = {
    bufnr = bufnr,
    cwd = params.cwd,
    timeout = params.timeout or DEFAULT_TIMEOUT,
    __dirname = dirname,
    __filename = params.__filename,
  }

  ---Get tool-specific config subtree (read-only copy).
  ---Returns config.tools[tool_name] via vim.deepcopy, or nil if no subtree exists.
  ---@return table|nil
  function context:get_config()
    local tool_config = state.get_config()
    if not tool_config.tools then
      return nil
    end
    local subtree = tool_config.tools[tool_name]
    if subtree == nil then
      return nil
    end
    return vim.deepcopy(subtree)
  end

  return setmetatable(context, {
    __index = function(self, key)
      if key == "sandbox" then
        local sandbox_module = require("flemma.sandbox")
        ---@type flemma.tools.SandboxContext
        local sandbox_namespace = {
          is_path_writable = function(path)
            return sandbox_module.is_path_writable(path, bufnr, opts)
          end,
          wrap_command = function(cmd)
            return sandbox_module.wrap_command(cmd, bufnr, opts)
          end,
        }
        rawset(self, "sandbox", sandbox_namespace)
        return sandbox_namespace
      elseif key == "truncate" then
        local truncate_module = require("flemma.tools.truncate")
        rawset(self, "truncate", truncate_module)
        return truncate_module
      elseif key == "path" then
        ---@type flemma.tools.PathContext
        local path_namespace = {
          resolve = function(path)
            if vim.startswith(path, "/") then
              return path
            end
            local base = dirname or vim.fn.getcwd()
            return base .. "/" .. path
          end,
        }
        rawset(self, "path", path_namespace)
        return path_namespace
      end
      return nil
    end,
  })
end

---Execute a tool call
---@param bufnr integer
---@param context flemma.tools.ToolContext
---@return boolean success
---@return string|nil error
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
    placeholder_modified = false,
  }

  -- Lock buffer to prevent user edits during execution
  state.lock_buffer(bufnr)

  -- Phase 1: Inject placeholder (pcall to ensure cleanup on unexpected errors like textlock)
  local ph_ok, header_line, inject_err, placeholder_opts = pcall(injector.inject_placeholder, bufnr, tool_id)
  if not ph_ok then
    cleanup_pending(bufnr, tool_id)
    maybe_unlock_buffer(bufnr)
    return false, "Failed to inject placeholder: " .. tostring(header_line)
  end
  if not header_line then
    cleanup_pending(bufnr, tool_id)
    maybe_unlock_buffer(bufnr)
    return false, "Failed to inject placeholder: " .. (inject_err or "unknown")
  end
  pending[tool_id].placeholder_modified = (placeholder_opts and placeholder_opts.modified) or false

  -- Show execution indicator
  local ui = require("flemma.ui")
  local config = state.get_config()
  if not config.tools or config.tools.show_spinner ~= false then
    ui.show_tool_indicator(bufnr, tool_id, header_line)
  end

  -- Placeholder injection may have displaced other tools' extmarks
  -- (e.g., when inserting before an existing placeholder via set_lines replacement)
  ui.reposition_tool_indicators(bufnr)

  -- Update UI to reflect changes
  ui.update_ui(bufnr)

  -- Build execution context for tools that need buffer/sandbox info
  local buffer_context = require("flemma.context").from_buffer(bufnr)
  local dirname = buffer_context:get_dirname()

  -- Resolve cwd: config value may contain $FLEMMA_BUFFER_PATH pseudo-variable
  local raw_cwd = config.tools and config.tools.bash and config.tools.bash.cwd
  local resolved_cwd
  if raw_cwd == "$FLEMMA_BUFFER_PATH" then
    resolved_cwd = dirname or vim.fn.getcwd()
  elseif raw_cwd then
    resolved_cwd = raw_cwd
  else
    resolved_cwd = vim.fn.getcwd()
  end

  -- Resolve per-buffer opts if available (for sandbox per-buffer overrides)
  local resolved_opts = nil
  local opts_ok, opts_result = pcall(require("flemma.processor").resolve_buffer_opts, bufnr)
  if opts_ok and opts_result then
    resolved_opts = opts_result
  end

  local exec_context = M.build_execution_context({
    bufnr = bufnr,
    cwd = resolved_cwd,
    timeout = (config.tools and config.tools.default_timeout) or DEFAULT_TIMEOUT,
    tool_name = tool_name,
    __dirname = dirname,
    __filename = buffer_context:get_filename(),
    opts = resolved_opts,
  })

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
      handle_completion(bufnr, tool_id, result, { async = true })
    end

    local ok, cancel_or_err = pcall(executor_fn, context.input, callback, exec_context)
    if not ok then
      -- Executor threw before starting async work
      handle_completion(bufnr, tool_id, {
        success = false,
        error = tostring(cancel_or_err),
      }, { async = false })
      return true, nil -- We handled the error
    end

    -- Store cancel function if returned
    if type(cancel_or_err) == "function" then
      pending[tool_id].cancel_fn = cancel_or_err
    end
  else
    -- Sync execution — complete inline for reliable undojoin
    local ok, result = pcall(executor_fn, context.input, nil, exec_context)
    if not ok then
      handle_completion(bufnr, tool_id, {
        success = false,
        error = tostring(result),
      }, { async = false })
    elseif not result then
      handle_completion(bufnr, tool_id, {
        success = false,
        error = "Tool returned no result",
      }, { async = false })
    else
      handle_completion(bufnr, tool_id, result, { async = false })
    end
  end

  return true, nil
end

---Cancel a pending execution
---@param tool_id string
---@return boolean cancelled true if cancelled, false if not found
function M.cancel(tool_id)
  for bufnr, pending in pairs(pending_by_buffer) do
    local entry = pending[tool_id]
    if entry and not entry.completed then
      -- Call cancel function if available
      if entry.cancel_fn then
        pcall(entry.cancel_fn)
      end

      -- Record cancellation as error result (cancel is always called from main thread)
      handle_completion(bufnr, tool_id, {
        success = false,
        error = "User aborted tool execution.",
      }, { async = false })
      return true
    end
  end
  return false
end

---Cancel all pending executions for a buffer
---@param bufnr integer
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

  -- Disarm autopilot after cancelling all tools
  require("flemma.autopilot").disarm(bufnr)
end

---Get pending executions for a buffer
---@param bufnr integer
---@return flemma.tools.PendingExecution[]
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

---Cancel the active operation for a buffer (API request or first pending tool)
---@param bufnr integer
---@return boolean cancelled
function M.cancel_for_buffer(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.current_request then
    require("flemma.core").cancel_request()
    return true
  end
  local pending = M.get_pending(bufnr)
  if #pending > 0 then
    table.sort(pending, function(a, b)
      return a.started_at < b.started_at
    end)
    require("flemma.autopilot").disarm(bufnr)
    M.cancel(pending[1].tool_id)
    return true
  end
  return false
end

---Cancel the tool at cursor position, or the first pending tool if no cursor match
---@param bufnr integer
---@return boolean cancelled
function M.cancel_at_cursor(bufnr)
  local autopilot = require("flemma.autopilot")
  local cursor = vim.api.nvim_win_get_cursor(0)
  local tool_context = require("flemma.tools.context")
  local ctx, _ = tool_context.resolve(bufnr, { row = cursor[1], col = cursor[2] })
  if ctx then
    autopilot.disarm(bufnr)
    return M.cancel(ctx.tool_id)
  end
  local pending = M.get_pending(bufnr)
  if #pending > 0 then
    table.sort(pending, function(a, b)
      return a.started_at < b.started_at
    end)
    autopilot.disarm(bufnr)
    return M.cancel(pending[1].tool_id)
  end
  return false
end

---Resolve and execute the tool at cursor position.
---For rejected/denied tools, injects the appropriate error result instead of executing.
---@param bufnr integer
---@return boolean success
---@return string|nil error
function M.execute_at_cursor(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local tool_context = require("flemma.tools.context")
  local ctx, err = tool_context.resolve(bufnr, { row = cursor[1], col = cursor[2] })
  if not ctx then
    return false, err or "No tool call found"
  end

  -- Check if matching tool_result has a status that prevents execution
  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)
  for _, msg in ipairs(doc.messages) do
    if msg.role == "You" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" and seg.tool_use_id == ctx.tool_id and seg.status then
          if seg.status == "rejected" or seg.status == "denied" then
            -- Resolve the block by injecting the appropriate error result
            injector.inject_result(bufnr, ctx.tool_id, {
              success = false,
              error = injector.resolve_error_message(seg.status --[[@as "rejected"|"denied"]], seg.content),
            })
            -- Re-arm autopilot if it was paused (same logic as the pending/approved
            -- path below) so that on_tools_complete can resume the loop.
            local autopilot = require("flemma.autopilot")
            if autopilot.get_state(bufnr) == "paused" then
              autopilot.arm(bufnr)
            end
            -- Notify autopilot so it can resume the loop
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(bufnr) then
                require("flemma.autopilot").on_tools_complete(bufnr)
              end
            end)
            return true, nil
          end
        end
      end
    end
  end

  -- Re-arm autopilot only if it was paused (i.e., actively in a loop that
  -- stopped on this pending tool). Don't arm from idle — the user may be
  -- manually executing tools without an autopilot loop running.
  local autopilot = require("flemma.autopilot")
  if autopilot.get_state(bufnr) == "paused" then
    autopilot.arm(bufnr)
  end

  return M.execute(bufnr, ctx)
end

---Clean up all state for a buffer (called on buffer close)
---@param bufnr integer
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
