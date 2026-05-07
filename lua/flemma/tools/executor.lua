--- Tool executor
--- Orchestrates tool execution with state management, concurrency control, and result handling
---@class flemma.tools.Executor
local M = {}

local registry = require("flemma.tools.registry")
local injector = require("flemma.tools.injector")
local editing = require("flemma.buffer.editing")
local config_facade = require("flemma.config")
local state = require("flemma.state")
local log = require("flemma.logging")
local autopilot = require("flemma.autopilot")
local cursor = require("flemma.cursor")
local bridge = require("flemma.bridge")
local hooks = require("flemma.hooks")
local context_module = require("flemma.context")
local parser = require("flemma.parser")
local ast = require("flemma.ast")
local sandbox_module = require("flemma.sandbox")
local tool_context = require("flemma.tools.context")
local path_util = require("flemma.utilities.path")
local truncate_module = require("flemma.tools.truncate")
local indicators = require("flemma.ui.indicators")
local ui = require("flemma.ui")
local variables = require("flemma.utilities.variables")
local writequeue = require("flemma.buffer.writequeue")
local messages = require("flemma.messages")
local tools_module = require("flemma.tools")

local JOB_ID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
local JOB_ID_LENGTH = 5

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
---@field job_id string|nil Background job ID; presence implies this is a background execution

---@class flemma.tools.BackgroundCompletion
---@field job_id string
---@field tool_id string
---@field tool_name string
---@field result flemma.tools.ExecutionResult
---@field completed_at? integer Not in spec; implementation detail for future diagnostics/ordering

---Check whether a named tool is available for a buffer's resolved tool set.
---@param name string Tool name to check
---@param bufnr integer Buffer number
---@return boolean
local function is_tool_available(name, bufnr)
  local available = tools_module.get_for_prompt(bufnr)
  return available[name] ~= nil
end

---Get or initialize the pending executions map for a buffer
---@param bufnr integer
---@return table<string, flemma.tools.PendingExecution>
local function get_buffer_pending(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if not buffer_state.pending_executions then
    buffer_state.pending_executions = {}
  end
  return buffer_state.pending_executions
end

---Get or initialize the completion queue for a buffer.
---@param bufnr integer
---@return flemma.tools.BackgroundCompletion[]
local function get_completion_queue(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if not buffer_state.completion_queue then
    buffer_state.completion_queue = {}
  end
  return buffer_state.completion_queue
end

---Generate a random unique background job identifier (e.g. "bg_k7x2m").
---Relies on Neovim seeding math.randomseed(vim.uv.hrtime()) at startup.
---@return string
function M.generate_job_id()
  local parts = { "bg_" }
  for _ = 1, JOB_ID_LENGTH do
    local idx = math.random(1, #JOB_ID_CHARS)
    parts[#parts + 1] = JOB_ID_CHARS:sub(idx, idx)
  end
  return table.concat(parts)
end

---Enqueue a completed background tool result for later delivery.
---@param bufnr integer
---@param item flemma.tools.BackgroundCompletion
function M.enqueue_background_completion(bufnr, item)
  local queue = get_completion_queue(bufnr)
  item.completed_at = item.completed_at or os.time()
  table.insert(queue, item)
end

---Check whether any background completions are waiting for delivery.
---@param bufnr integer
---@return boolean
function M.has_background_completions(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local queue = buffer_state.completion_queue
  return queue ~= nil and #queue > 0
end

---Drain and return all queued background completions in FIFO order.
---@param bufnr integer
---@return flemma.tools.BackgroundCompletion[]
function M.drain_background_completions(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local queue = buffer_state.completion_queue or {}
  buffer_state.completion_queue = {}
  return queue
end

---Count tools currently occupying execution slots for a buffer.
---Includes entries whose completed flag is true but haven't been cleaned up yet
---(async completion still processing via writequeue). This inclusive counting is
---correct for concurrency gating: an occupied slot is occupied regardless of
---whether the tool's result is still being injected.
---@param bufnr integer
---@return integer
function M.count_running(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local pending = buffer_state.pending_executions
  if not pending then
    return 0
  end
  local n = 0
  for _, entry in pairs(pending) do
    if not entry.job_id then
      n = n + 1
    end
  end
  return n
end

---Unlock the buffer if no more tools are actively executing
---@param bufnr integer
local function maybe_unlock_buffer(bufnr)
  if M.count_running(bufnr) == 0 then
    state.unlock_buffer(bufnr)
    -- Notify autopilot that all tool executions have completed
    autopilot.on_tools_complete(bufnr)
  end
end

---Check whether any tool executions are still in-flight for a buffer
---@param bufnr integer
---@return boolean
function M.has_pending(bufnr)
  return M.count_running(bufnr) > 0
end

---Clean up a pending execution entry
---@param bufnr integer
---@param tool_id string
local function cleanup_pending(bufnr, tool_id)
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.pending_executions then
    buffer_state.pending_executions[tool_id] = nil
  end
end

---Move cursor after result injection based on config
---@param bufnr integer
---@param tool_id string
---@param mode string "result" or "next"
local function move_cursor_after_result(bufnr, tool_id, mode)
  local doc = parser.get_parsed_document(bufnr)

  -- Find the tool_use segment by ID
  ---@type flemma.ast.ToolUseSegment|nil
  local tool_use_seg = nil
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "tool_use" and seg.id == tool_id then
        tool_use_seg = seg --[[@as flemma.ast.ToolUseSegment]]
        break
      end
    end
    if tool_use_seg then
      break
    end
  end

  if not tool_use_seg then
    return
  end

  local result_seg, result_msg = ast.find_tool_sibling(doc, tool_use_seg)
  if not result_seg then
    return
  end

  local target_line = nil
  if mode == "result" then
    target_line = result_seg.position.start_line
  elseif mode == "next" and result_msg then
    target_line = result_msg.position.end_line + 1
  end

  if target_line then
    cursor.request_move(bufnr, { line = target_line, reason = "tool-result/" .. mode })
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

  if entry and entry.job_id then
    entry.completed = true
    indicators.update_tool_indicator(bufnr, tool_id, result.success)
    indicators.schedule_tool_indicator_clear(bufnr, tool_id, 1500)
    M.enqueue_background_completion(bufnr, {
      job_id = entry.job_id,
      tool_id = tool_id,
      tool_name = entry.tool_name,
      result = result,
    })
    hooks.dispatch("tool:finished", {
      bufnr = bufnr,
      tool_name = entry.tool_name,
      tool_id = tool_id,
      status = result.success and "success" or "error",
    })
    log.debug("executor: background tool " .. tool_id .. " (job=" .. entry.job_id .. ") completed, queued for delivery")

    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local bs = state.get_buffer_state(bufnr)
      local fg_count = M.count_running(bufnr)
      if not bs.current_request and fg_count == 0 then
        log.debug("executor: conversation idle, triggering background drain for buffer " .. bufnr)
        bridge.drain_background_completions(bufnr)
      else
        log.debug(
          "executor: deferring background drain for buffer "
            .. bufnr
            .. " (request_active="
            .. tostring(bs.current_request ~= nil)
            .. " foreground_tools="
            .. fg_count
            .. ")"
        )
      end
    end)
    return
  end

  -- For async tools, join with placeholder injection as a single undo step
  -- only when the placeholder actually modified the buffer.
  -- For sync tools, all changes are already in one undo block (same handler),
  -- and calling undojoin would incorrectly merge with the PREVIOUS handler's block.
  opts = opts or {}
  if opts.async and entry and entry.placeholder_modified then
    pcall(vim.cmd --[[@as function]], "undojoin")
  end

  -- Inject result into buffer
  local ok, err = injector.inject_result(bufnr, tool_id, result)
  if not ok then
    log.error("executor: Failed to inject result for " .. tool_id .. ": " .. (err or "unknown"))
  end

  hooks.dispatch("tool:finished", {
    bufnr = bufnr,
    tool_name = entry and entry.tool_name or "unknown",
    tool_id = tool_id,
    status = result.success and "success" or "error",
  })

  -- Move cursor based on config (skip when autopilot is armed — it owns cursor positioning)
  if ok and autopilot.get_state(bufnr) ~= "armed" then
    local config = config_facade.get(bufnr)
    local cursor_mode = config.tools and config.tools.cursor_after_result or "result"
    if cursor_mode ~= "stay" then
      move_cursor_after_result(bufnr, tool_id, cursor_mode)
    end
  end

  -- Result injection may have displaced other tools' extmarks
  indicators.reposition_tool_indicators(bufnr)

  -- Update indicator
  indicators.update_tool_indicator(bufnr, tool_id, result.success)

  -- Free pending slot immediately so tool can be re-executed
  cleanup_pending(bufnr, tool_id)

  -- Unlock buffer if no more tools are actively executing.
  -- This must happen BEFORE scheduling indicator clear, so the buffer
  -- is editable and the on_lines listener can detect user edits.
  maybe_unlock_buffer(bufnr)

  -- Auto-dismiss indicator after delay (or immediately on user edit)
  indicators.schedule_tool_indicator_clear(bufnr, tool_id, 1500)

  ui.update_ui(bufnr)

  -- Auto-write after tool result injection so the buffer is saved between
  -- tool executions, not only after the next send_to_provider() completes.
  editing.auto_write(bufnr)

  if M.has_background_completions(bufnr) then
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local bs = state.get_buffer_state(bufnr)
      local fg_count = M.count_running(bufnr)
      if not bs.current_request and fg_count == 0 then
        log.debug(
          "executor: foreground tool done, conversation idle with pending background completions, triggering drain for buffer "
            .. bufnr
        )
        bridge.drain_background_completions(bufnr)
      end
    end)
  end
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
    writequeue.schedule(bufnr, function()
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
---@field tool_id? string Tool call ID (for overflow path resolution)
---@field __dirname? string Directory containing the .chat buffer
---@field __filename? string Full path of the .chat buffer

---Build an ExecutionContext with lazy-loaded sandbox/truncate/path namespaces.
---Sandbox, truncate, and path are loaded on first access via __index and then
---cached via rawset so subsequent accesses bypass the metamethod.
---@param params flemma.tools.ExecutionContextParams
---@return flemma.tools.ExecutionContext
function M.build_execution_context(params)
  local bufnr = params.bufnr
  local tool_name = params.tool_name
  local dirname = params.__dirname

  -- Core data fields. Namespace fields (sandbox, truncate, path) are added via
  -- __index metamethod; get_config is defined as a method below.
  local context = {
    bufnr = bufnr,
    cwd = params.cwd,
    timeout = params.timeout or DEFAULT_TIMEOUT,
    tool_id = params.tool_id,
    __dirname = dirname,
    __filename = params.__filename,
  }

  ---@return flemma.ast.DocumentNode
  function context:get_parsed_document()
    return parser.get_parsed_document(bufnr)
  end

  ---Get tool-specific config subtree (read-only copy).
  ---Returns config.tools[tool_name] via vim.deepcopy, or nil if no subtree exists.
  ---@return table|nil
  function context:get_config()
    local cfg = config_facade.materialize(bufnr)
    if not cfg.tools then
      return nil
    end
    local subtree = cfg.tools[tool_name]
    if subtree == nil then
      return nil
    end
    return vim.deepcopy(subtree)
  end

  return setmetatable(context, {
    __index = function(self, key)
      if key == "sandbox" then
        ---@type flemma.tools.SandboxContext
        local sandbox_namespace = {
          is_path_writable = function(path)
            return sandbox_module.is_path_writable(path, bufnr)
          end,
          wrap_command = function(cmd)
            return sandbox_module.wrap_command(cmd, bufnr)
          end,
        }
        rawset(self, "sandbox", sandbox_namespace)
        return sandbox_namespace
      elseif key == "truncate" then
        local bound = setmetatable({
          truncate_with_overflow = function(text, opts)
            opts.bufnr = bufnr
            opts.filename = params.__filename
            if not opts.source then
              opts.source = "tool"
            end
            if not opts.id then
              opts.id = params.tool_id or ""
            end
            return truncate_module.truncate_with_overflow(text, opts)
          end,
        }, { __index = truncate_module })
        rawset(self, "truncate", bound)
        return bound
      elseif key == "path" then
        ---@type flemma.tools.PathContext
        local path_namespace = {
          resolve = function(p)
            return path_util.resolve(p, dirname or vim.fn.getcwd())
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
---@param opts? { background?: boolean }
---@return boolean success
---@return string|nil error
function M.execute(bufnr, context, opts)
  opts = opts or {}
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
  if opts.background then
    pending[tool_id].job_id = M.generate_job_id()
    log.debug(
      "executor: allocated job_id " .. pending[tool_id].job_id .. " for " .. tool_id .. " (" .. tool_name .. ")"
    )
  end

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
  pending[tool_id].placeholder_modified = placeholder_opts ~= nil and placeholder_opts.modified

  -- Clear any (status) header suffix when the placeholder already existed.
  -- Phase 1 injects placeholders with status=approved; the executor's
  -- inject_placeholder call above finds that existing block and returns early
  -- (modified=false), leaving the (approved) suffix in the header.
  -- Without clearing it, on_tools_complete → resolve_all_tool_blocks
  -- rediscovers this tool as "approved" and schedules a duplicate execution
  -- attempt (race: sync tool completing inline during Phase 2's for loop triggers
  -- on_tools_complete while the autopilot state is already "armed").
  -- clear_header_status is a no-op when the header has no suffix.
  if placeholder_opts and not placeholder_opts.modified then
    injector.clear_header_status(bufnr, tool_id)
  end

  if opts.background and pending[tool_id] and pending[tool_id].job_id then
    local job_id = pending[tool_id].job_id --[[@as string]]
    local h_ok, h_err = injector.set_header_modeline(bufnr, tool_id, "job=" .. job_id)
    if not h_ok then
      log.warn("executor: failed to set background header for " .. tool_id .. ": " .. (h_err or "unknown"))
    end
    local placeholder_text
    if is_tool_available("flemma:job_status", bufnr) then
      placeholder_text = messages.render("background_available", { job_id = job_id })
    else
      placeholder_text = messages.render("background_unavailable", {})
    end
    local f_ok, f_err = injector.set_fence_content(bufnr, tool_id, placeholder_text or "Running in background.")
    if not f_ok then
      log.warn("executor: failed to set background placeholder for " .. tool_id .. ": " .. (f_err or "unknown"))
    end
    log.debug("executor: wrote background placeholder for " .. tool_id .. " (job=" .. job_id .. ")")
  end

  -- Show execution indicator
  local config = config_facade.materialize(bufnr)
  if not config.tools or config.tools.show_spinner ~= false then
    indicators.show_tool_indicator(bufnr, tool_id, header_line)
  end

  -- Placeholder injection may have displaced other tools' extmarks
  -- (e.g., when inserting before an existing placeholder via set_lines replacement)
  indicators.reposition_tool_indicators(bufnr)

  -- Update UI to reflect changes
  ui.update_ui(bufnr)

  -- Build execution context for tools that need buffer/sandbox info
  local buffer_context = context_module.from_buffer(bufnr)
  local dirname = buffer_context:get_dirname()

  -- Resolve cwd: config value may be a URN or variable
  local tool_config = config.tools and config.tools[tool_name]
  local raw_cwd = tool_config and tool_config.cwd
  local resolved_cwd
  if raw_cwd then
    resolved_cwd = variables.expand(raw_cwd, { bufnr = bufnr }) or vim.fn.getcwd()
  else
    resolved_cwd = vim.fn.getcwd()
  end

  local exec_context = M.build_execution_context({
    bufnr = bufnr,
    cwd = resolved_cwd,
    timeout = (config.tools and config.tools.default_timeout) or DEFAULT_TIMEOUT,
    tool_name = tool_name,
    tool_id = tool_id,
    __dirname = dirname,
    __filename = buffer_context:get_filename(),
  })

  hooks.dispatch("tool:executing", { bufnr = bufnr, tool_name = tool_name, tool_id = tool_id })

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

    local ok, cancel_or_err = pcall(executor_fn, context.input, exec_context, callback)
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
    local ok, result = pcall(executor_fn, context.input, exec_context)
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
  for bufnr, buffer_state in state.each_buffer_state() do
    local pending = buffer_state.pending_executions
    if not pending then
      goto continue
    end
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
    ::continue::
  end
  return false
end

---Cancel all pending executions for a buffer
---@param bufnr integer
function M.cancel_all(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local pending = buffer_state.pending_executions
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
  autopilot.disarm(bufnr)
end

---Get pending executions for a buffer
---@param bufnr integer
---@return flemma.tools.PendingExecution[]
function M.get_pending(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local pending = buffer_state.pending_executions
  if not pending then
    return {}
  end

  local result = {}
  for _, entry in pairs(pending) do
    if not entry.completed and not entry.job_id then
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
    bridge.cancel_request({ bufnr = bufnr })
    return true
  end
  if buffer_state.pending_send then
    bridge.cancel_request({ bufnr = bufnr })
    return true
  end
  local pending = M.get_pending(bufnr)
  if #pending > 0 then
    table.sort(pending, function(a, b)
      return a.started_at < b.started_at
    end)
    autopilot.disarm(bufnr)
    M.cancel(pending[1].tool_id)
    return true
  end
  return false
end

---Cancel the tool at cursor position, or the first pending tool if no cursor match
---@param bufnr integer
---@return boolean cancelled
function M.cancel_at_cursor(bufnr)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local ctx, _ = tool_context.resolve(bufnr, { row = cursor_pos[1], col = cursor_pos[2] })
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

---Background the foreground tool at cursor position.
---@param bufnr integer
---@return boolean success
---@return string|nil error
function M.background_at_cursor(bufnr)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local ctx, err = tool_context.resolve(bufnr, { row = cursor_pos[1], col = cursor_pos[2] })
  if not ctx then
    return false, err or "No tool call found at cursor"
  end

  local pending = get_buffer_pending(bufnr)
  local entry = pending[ctx.tool_id]
  if not entry then
    return false, "Tool " .. ctx.tool_id .. " is not currently executing"
  end
  if entry.completed then
    return false, "Tool " .. ctx.tool_id .. " has already completed"
  end
  if entry.job_id then
    return false, "Tool " .. ctx.tool_id .. " is already running in background"
  end

  entry.job_id = M.generate_job_id()
  local job_id = entry.job_id --[[@as string]]

  local header_ok, header_err = injector.set_header_modeline(bufnr, ctx.tool_id, "job=" .. job_id)
  if not header_ok then
    log.warn(
      "executor: background_at_cursor failed to update header for " .. ctx.tool_id .. ": " .. (header_err or "unknown")
    )
    entry.job_id = nil
    return false, "Failed to update header: " .. (header_err or "unknown")
  end

  local bg_placeholder_text
  if is_tool_available("flemma:job_status", bufnr) then
    bg_placeholder_text = messages.render("background_available", { job_id = job_id })
  else
    bg_placeholder_text = messages.render("background_unavailable", {})
  end
  local content_ok, content_err =
    injector.set_fence_content(bufnr, ctx.tool_id, bg_placeholder_text or "Running in background.")
  if not content_ok then
    log.warn(
      "executor: background_at_cursor failed to set fence for " .. ctx.tool_id .. ": " .. (content_err or "unknown")
    )
    injector.clear_header_status(bufnr, ctx.tool_id)
    entry.job_id = nil
    return false, content_err
  end

  indicators.reposition_tool_indicators(bufnr)
  maybe_unlock_buffer(bufnr)
  ui.update_ui(bufnr)
  log.info("executor: backgrounded tool " .. ctx.tool_id .. " as " .. job_id)

  if M.count_running(bufnr) == 0 then
    log.debug("executor: all foreground tools clear after backgrounding, scheduling send for buffer " .. bufnr)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        bridge.send_or_execute({ bufnr = bufnr })
      end
    end)
  end

  return true, nil
end

---Scan for orphaned background tool_results and inject error completion blocks.
---@param bufnr integer
---@return integer count Number of orphans resolved
function M.scan_orphaned_background_jobs(bufnr)
  log.debug("executor: scanning for orphaned background jobs in buffer " .. bufnr)
  local doc = parser.get_parsed_document(bufnr)

  local completed_jobs = {}
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "background_tool_completed" then
        ---@cast seg flemma.ast.BackgroundToolCompletedSegment
        completed_jobs[seg.job_id] = true
      end
    end
  end

  local buffer_state = state.get_buffer_state(bufnr)
  local active_jobs = {}
  if buffer_state.pending_executions then
    for _, entry in pairs(buffer_state.pending_executions) do
      if entry.job_id then
        active_jobs[entry.job_id] = true
      end
    end
  end

  local orphans = {}
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "tool_result" and seg.meta and seg.meta.job then
        ---@cast seg flemma.ast.ToolResultSegment
        local job_id = seg.meta.job
        if not completed_jobs[job_id] and not active_jobs[job_id] then
          table.insert(orphans, job_id)
        end
      end
    end
  end

  if #orphans > 0 then
    log.info("executor: found " .. #orphans .. " orphaned background job(s) in buffer " .. bufnr)
  else
    log.trace("executor: no orphaned background jobs in buffer " .. bufnr)
  end

  for _, job_id in ipairs(orphans) do
    log.debug("executor: resolving orphan " .. job_id .. " with error completion")
    injector.append_background_completion(bufnr, job_id, {
      success = false,
      error = "Background job lost: session ended before completion.",
    })
  end

  return #orphans
end

---Locate the tool_result placeholder for the tool at the cursor position. Returns
---the parsed `ctx` and the matching `flemma.ast.ToolResultSegment` when the tool
---has a lifecycle status suffix (pending/approved/denied/rejected/aborted). Errors
---out if there's no tool at cursor, no matching result placeholder, or the tool
---has already completed (status=nil or status="error").
---@param bufnr integer
---@return flemma.tools.ToolContext|nil ctx
---@return flemma.ast.ToolResultSegment|nil result_seg
---@return string|nil error
local function resolve_lifecycle_tool_at_cursor(bufnr)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local ctx, err = tool_context.resolve(bufnr, { row = cursor_pos[1], col = cursor_pos[2] })
  if not ctx then
    return nil, nil, err or "No tool call found"
  end

  local doc = parser.get_parsed_document(bufnr)
  local result_seg = ast.find_tool_sibling(doc, ctx.node)
  if not result_seg or result_seg.kind ~= "tool_result" then
    return nil, nil, "No tool result placeholder for " .. ctx.tool_id
  end
  ---@cast result_seg flemma.ast.ToolResultSegment

  if not result_seg.status or result_seg.status == "error" then
    return nil, nil, "Tool " .. ctx.tool_id .. " has already completed"
  end

  return ctx, result_seg, nil
end

---Set the `(approved)` header suffix on the tool_result placeholder at cursor.
---The tool is not executed here — the next `<C-]>` advances the cycle.
---@param bufnr integer
---@return boolean success
---@return string|nil error
function M.approve_at_cursor(bufnr)
  local ctx, _, err = resolve_lifecycle_tool_at_cursor(bufnr)
  if not ctx then
    return false, err
  end
  local ok, update_err = injector.set_header_status(bufnr, ctx.tool_id, "approved")
  if not ok then
    return false, update_err
  end
  editing.auto_write(bufnr)
  return true, nil
end

---Set the `(rejected)` header suffix on the tool_result placeholder at cursor,
---optionally replacing the fence body with a user-supplied message that the
---model will see as the rejection reason.
---@param bufnr integer
---@param message string|nil Optional rejection message written into the fence
---@return boolean success
---@return string|nil error
function M.reject_at_cursor(bufnr, message)
  local ctx, _, err = resolve_lifecycle_tool_at_cursor(bufnr)
  if not ctx then
    return false, err
  end
  local ok, update_err = injector.set_header_status(bufnr, ctx.tool_id, "rejected")
  if not ok then
    return false, update_err
  end
  if message and message ~= "" then
    local content_ok, content_err = injector.set_fence_content(bufnr, ctx.tool_id, message)
    if not content_ok then
      return false, content_err
    end
  end
  editing.auto_write(bufnr)
  return true, nil
end

---Resolve and execute the tool at cursor position.
---For rejected/denied tools, injects the appropriate error result instead of executing.
---@param bufnr integer
---@return boolean success
---@return string|nil error
function M.execute_at_cursor(bufnr)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local ctx, err = tool_context.resolve(bufnr, { row = cursor_pos[1], col = cursor_pos[2] })
  if not ctx then
    return false, err or "No tool call found"
  end

  -- Check if matching tool_result has a status that prevents execution
  local doc = parser.get_parsed_document(bufnr)
  -- Use the tool_use from ctx.node (already resolved by tool_context.resolve)
  local result_seg = ast.find_tool_sibling(doc, ctx.node)
  if result_seg and result_seg.kind == "tool_result" then
    ---@cast result_seg flemma.ast.ToolResultSegment
    if result_seg.status and (result_seg.status == "rejected" or result_seg.status == "denied") then
      injector.inject_result(bufnr, ctx.tool_id, {
        success = false,
        error = injector.resolve_error_message(result_seg.status --[[@as "rejected"|"denied"]], result_seg.content),
      })
      if autopilot.get_state(bufnr) == "paused" then
        autopilot.arm(bufnr)
      end
      editing.auto_write(bufnr)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          autopilot.on_tools_complete(bufnr)
        end
      end)
      return true, nil
    end
  end

  -- Re-arm autopilot only if it was paused (i.e., actively in a loop that
  -- stopped on this pending tool). Don't arm from idle — the user may be
  -- manually executing tools without an autopilot loop running.
  if autopilot.get_state(bufnr) == "paused" then
    autopilot.arm(bufnr)
  end

  return M.execute(bufnr, ctx)
end

---Clean up all state for a buffer (called on buffer close)
---@param bufnr integer
function M.cleanup_buffer(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local pending = buffer_state.pending_executions
  if pending then
    for _, entry in pairs(pending) do
      if entry.cancel_fn and not entry.completed then
        pcall(entry.cancel_fn)
      end
    end
  end
  buffer_state.pending_executions = nil
end

-- Register cleanup hook with state (breaks circular dependency: state cannot require executor)
state.register_cleanup("executor", function(bufnr)
  M.cleanup_buffer(bufnr)
end)

---@private
---@param bufnr integer
---@param tool_id string
---@param result flemma.tools.ExecutionResult
---@param opts? { async?: boolean }
function M._test_do_completion(bufnr, tool_id, result, opts)
  do_completion(bufnr, tool_id, result, opts)
end

return M
