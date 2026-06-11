--- Tool executor
--- Orchestrates tool execution with state management, concurrency control, and result handling
---@class flemma.tools.Executor
local M = {}

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
local navigation = require("flemma.navigation")
local tool_context = require("flemma.tools.context")
local path_util = require("flemma.utilities.path")
local truncate_module = require("flemma.tools.truncate")
local indicators = require("flemma.ui.indicators")
local ui = require("flemma.ui")
local variables = require("flemma.utilities.variables")
local writequeue = require("flemma.buffer.writequeue")
local messages = require("flemma.messages")
local tools_module = require("flemma.tools")
local readiness = require("flemma.readiness")
local notify = require("flemma.notify")

local JOB_ID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
local JOB_ID_LENGTH = 8

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

---@class flemma.tools.JobDelivery
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
---@return flemma.tools.JobDelivery[]
local function get_delivery_queue(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if not buffer_state.delivery_queue then
    buffer_state.delivery_queue = {}
  end
  return buffer_state.delivery_queue
end

---Collect all job IDs referenced in the buffer (tool_result meta.job + job_result IDs).
---@param bufnr integer
---@return table<string, true>
function M.collect_buffer_job_ids(bufnr)
  local doc = parser.get_parsed_document(bufnr)
  local ids = {}
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "tool_result" and seg.meta and seg.meta.job then
        ids[seg.meta.job] = true
      elseif seg.kind == "job_result" then
        ---@cast seg flemma.ast.JobResultSegment
        ids[seg.job_id] = true
      end
    end
  end
  return ids
end

local MAX_JOB_ID_ATTEMPTS = 100

---Generate a single random job ID candidate using OS-level randomness.
---@return string
local function generate_raw_job_id()
  local bytes = vim.uv.random(JOB_ID_LENGTH) --[[@as string]]
  local parts = { "job_" }
  for i = 1, JOB_ID_LENGTH do
    local idx = (
      bytes:byte(i) --[[@as integer]]
      % #JOB_ID_CHARS
    ) + 1
    parts[#parts + 1] = JOB_ID_CHARS:sub(idx, idx)
  end
  return table.concat(parts)
end

---Generate a random job identifier (e.g. "job_k7x2m") that does not collide
---with any ID already present in the buffer or the provided exclusion set.
---@param existing_ids? table<string, true>
---@return string
function M.generate_job_id(existing_ids)
  for _ = 1, MAX_JOB_ID_ATTEMPTS do
    local id = generate_raw_job_id()
    if not existing_ids or not existing_ids[id] then
      return id
    end
    log.debug("executor: job ID collision detected (" .. id .. "), regenerating")
  end
  return generate_raw_job_id()
end

---Enqueue a completed job result for later delivery.
---@param bufnr integer
---@param item flemma.tools.JobDelivery
function M.enqueue_job_completion(bufnr, item)
  local queue = get_delivery_queue(bufnr)
  item.completed_at = item.completed_at or os.time()
  table.insert(queue, item)
end

---Check whether any job completions are waiting for delivery.
---@param bufnr integer
---@return boolean
function M.has_job_completions(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local queue = buffer_state.delivery_queue
  return queue ~= nil and #queue > 0
end

---Drain and return all queued job completions in FIFO order.
---@param bufnr integer
---@return flemma.tools.JobDelivery[]
function M.drain_job_completions(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local queue = buffer_state.delivery_queue or {}
  buffer_state.delivery_queue = {}
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

---Count background jobs still in progress for a buffer.
---Includes jobs that are executing and jobs whose results are queued but not yet
---drained into the buffer. This is the user-facing "active" count: a job is
---active until its result is visible in the conversation.
---@param bufnr integer
---@return integer
function M.count_active_jobs(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local pending = buffer_state.pending_executions
  if not pending then
    return 0
  end
  local n = 0
  for _, entry in pairs(pending) do
    if entry.job_id then
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
  local tool_use_seg = ast.find_tool_use_by_id(doc, tool_id)
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
    M.enqueue_job_completion(bufnr, {
      job_id = entry.job_id,
      tool_id = tool_id,
      tool_name = entry.tool_name,
      result = result,
    })
    hooks.dispatch("tool:completed", {
      bufnr = bufnr,
      tool_name = entry.tool_name,
      tool_id = tool_id,
      status = result.success and "success" or "error",
    })
    log.debug("executor: job " .. entry.job_id .. " (tool=" .. tool_id .. ") completed, queued for delivery")

    maybe_unlock_buffer(bufnr)

    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local bs = state.get_buffer_state(bufnr)
      local fg_count = M.count_running(bufnr)
      if not bs.current_request and fg_count == 0 then
        log.debug("executor: conversation idle, triggering job drain for buffer " .. bufnr)
        bridge.drain_job_completions(bufnr)
      else
        log.debug(
          "executor: deferring job drain for buffer "
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
  local completion_config = config_facade.get(bufnr)
  local ok, err = injector.inject_result(
    bufnr,
    tool_id,
    result,
    { compact = completion_config.editing and completion_config.editing.compact_headers }
  )
  if not ok then
    log.error("executor: Failed to inject result for " .. tool_id .. ": " .. (err or "unknown"))
  end

  hooks.dispatch("tool:completed", {
    bufnr = bufnr,
    tool_name = entry and entry.tool_name or "unknown",
    tool_id = tool_id,
    status = result.success and "success" or "error",
  })

  -- Move cursor based on config (skip when autopilot is armed — it owns cursor positioning)
  if ok and autopilot.get_state(bufnr) ~= "armed" then
    local cursor_mode = completion_config.tools and completion_config.tools.cursor_after_result or "result"
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

  if M.has_job_completions(bufnr) then
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local bs = state.get_buffer_state(bufnr)
      local fg_count = M.count_running(bufnr)
      if not bs.current_request and fg_count == 0 then
        log.debug(
          "executor: foreground tool done, conversation idle with pending job completions, triggering drain for buffer "
            .. bufnr
        )
        bridge.drain_job_completions(bufnr)
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
        local store_config
        do
          local cfg = config_facade.materialize(bufnr)
          store_config = cfg.tools and cfg.tools.store or {}
        end
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
            opts.store_opts = {
              __filename = params.__filename,
              __dirname = params.__dirname,
              path_format = store_config.path_format,
              unnamed_path_format = store_config.unnamed_path_format,
              backup = store_config.backup,
            }
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
---@return boolean success
---@return string|nil error
function M.execute(bufnr, context)
  local tool_id = context.tool_id
  local tool_name = context.tool_name

  -- Extract execution directives from the tool input so that both the normal
  -- flow (core.lua) and manual approval (execute_at_cursor) share one path.
  local is_background = context.input and context.input.background == true
  if is_background then
    context.input = vim.tbl_extend("keep", {}, context.input)
    context.input.background = nil
    log.debug("executor: tool " .. tool_id .. " (" .. tool_name .. ") requested background execution")
  end

  -- Check for API request in flight (mutually exclusive)
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.current_request then
    return false, "Cannot execute tool while API request is in flight"
  end

  -- Check for duplicate execution
  local pending = get_buffer_pending(bufnr)
  if pending[tool_id] then
    local existing_entry = pending[tool_id]
    if existing_entry.job_id then
      -- Background job already running for this tool_id (undo + resend scenario).
      -- Re-adopt: link the fresh (approved) placeholder to the existing job.
      log.debug(
        "executor: re-adopting existing job "
          .. existing_entry.job_id
          .. " for "
          .. tool_id
          .. " ("
          .. existing_entry.tool_name
          .. ") — started_at="
          .. existing_entry.started_at
          .. " completed="
          .. tostring(existing_entry.completed)
      )
      injector.clear_header_status(bufnr, tool_id)
      local header_ok, header_err = injector.set_header_modeline(bufnr, tool_id, "job=" .. existing_entry.job_id)
      if not header_ok then
        log.warn("executor: failed to set re-adopt header for " .. tool_id .. ": " .. (header_err or "unknown"))
      end
      local placeholder_text
      if is_tool_available("flemma.jobs.status", bufnr) then
        placeholder_text = messages.render("job-executing--tracked", { job_id = existing_entry.job_id })
      else
        placeholder_text = messages.render("job-executing--untracked")
      end
      local readopt_config = config_facade.materialize(bufnr)
      local fence_ok, fence_err = injector.set_fence_content(
        bufnr,
        tool_id,
        placeholder_text,
        { compact = readopt_config.editing and readopt_config.editing.compact_headers }
      )
      if not fence_ok then
        log.warn("executor: failed to set re-adopt placeholder for " .. tool_id .. ": " .. (fence_err or "unknown"))
      end
      return true, nil
    end
    return false, "Tool " .. tool_id .. " is already executing"
  end

  -- Validate tool exists and is executable.
  -- Use tools_module.get() so pending third-party modules are loaded first.
  if not tools_module.get(tool_name) then
    return false, "Unknown tool: " .. tool_name
  end
  if not tools_module.is_executable(tool_name) then
    return false, "Tool '" .. tool_name .. "' is not executable"
  end

  local executor_fn, is_async = tools_module.get_executor(tool_name)
  if not executor_fn then
    return false, "No executor found for tool: " .. tool_name
  end

  local job_status_tool_available = false
  if is_background then
    job_status_tool_available = is_tool_available("flemma.jobs.status", bufnr)
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
  if is_background then
    -- Reuse existing job_id from the tool_result header when re-executing, so that
    -- the completed result replaces the existing Job Result block in-place.
    local existing_job_id = nil
    local doc = parser.get_parsed_document(bufnr)
    local sibling = ast.find_tool_sibling(doc, context.node)
    if sibling and sibling.kind == "tool_result" then
      ---@cast sibling flemma.ast.ToolResultSegment
      existing_job_id = sibling.meta and sibling.meta.job --[[@as string|nil]]
    end
    pending[tool_id].job_id = existing_job_id or M.generate_job_id(M.collect_buffer_job_ids(bufnr))
    log.debug(
      "executor: "
        .. (existing_job_id and "reusing" or "allocated")
        .. " job_id "
        .. pending[tool_id].job_id
        .. " for "
        .. tool_id
        .. " ("
        .. tool_name
        .. ")"
    )
  end

  -- Lock buffer to prevent user edits during execution
  state.lock_buffer(bufnr)

  local exec_config = config_facade.materialize(bufnr)
  local exec_compact = exec_config.editing and exec_config.editing.compact_headers

  -- Phase 1: Inject placeholder (pcall to ensure cleanup on unexpected errors like textlock)
  local ph_ok, header_line, inject_err, placeholder_opts =
    pcall(injector.inject_placeholder, bufnr, tool_id, { compact = exec_compact })
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

  if is_background and pending[tool_id] and pending[tool_id].job_id then
    local job_id = pending[tool_id].job_id --[[@as string]]
    local h_ok, h_err = injector.set_header_modeline(bufnr, tool_id, "job=" .. job_id)
    if not h_ok then
      log.warn("executor: failed to set background header for " .. tool_id .. ": " .. (h_err or "unknown"))
    end
    local placeholder_text
    if job_status_tool_available then
      placeholder_text = messages.render("job-executing--tracked", { job_id = job_id })
    else
      placeholder_text = messages.render("job-executing--untracked")
    end
    local f_ok, f_err = injector.set_fence_content(bufnr, tool_id, placeholder_text, { compact = exec_compact })
    if not f_ok then
      log.warn("executor: failed to set background placeholder for " .. tool_id .. ": " .. (f_err or "unknown"))
    end
    log.debug("executor: wrote background placeholder for " .. tool_id .. " (job=" .. job_id .. ")")
    hooks.dispatch("job:submitted", {
      bufnr = bufnr,
      job_id = job_id,
      tool_id = tool_id,
      tool_name = tool_name,
      active_count = M.count_active_jobs(bufnr),
    })
  end

  -- Show execution indicator
  if not exec_config.tools or exec_config.tools.show_spinner ~= false then
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
  local tool_config = exec_config.tools and exec_config.tools[tool_name]
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
    timeout = (exec_config.tools and exec_config.tools.default_timeout) or DEFAULT_TIMEOUT,
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

    -- Background tools are dispatched — unlock immediately so autopilot can
    -- resume without waiting for the job to finish.
    if is_background then
      maybe_unlock_buffer(bufnr)
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
      local is_background = entry.job_id ~= nil
      log.info(
        "executor: cancelling "
          .. (is_background and "background" or "foreground")
          .. " tool "
          .. tool_id
          .. (entry.job_id and (" (job=" .. entry.job_id .. ")") or "")
          .. " in buffer "
          .. bufnr
      )
      if entry.cancel_fn then
        pcall(entry.cancel_fn)
      end

      handle_completion(bufnr, tool_id, {
        success = false,
        error = messages.render("tool-aborted"),
      }, { async = false })
      return true
    end
    ::continue::
  end
  log.debug("executor: cancel(" .. tool_id .. ") — tool not found or already completed")
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

  local to_cancel = {}
  for tool_id, entry in pairs(pending) do
    if not entry.completed then
      table.insert(to_cancel, tool_id)
    end
  end

  if #to_cancel > 0 then
    log.info("executor: cancel_all() — cancelling " .. #to_cancel .. " tool(s) in buffer " .. bufnr)
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

---Cancel the active operation for a buffer: API request, queued send, or tool under cursor.
---Does NOT fall back to "oldest pending tool" — if the cursor isn't on a tool, the caller
---should handle the miss (e.g., double-tap RAGE cancel).
---@param bufnr integer
---@return boolean cancelled
function M.cancel_for_buffer(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.current_request then
    log.debug("cancel_for_buffer(): cancelling active API request in buffer " .. bufnr)
    bridge.cancel_request({ bufnr = bufnr })
    return true
  end
  if buffer_state.pending_send then
    log.debug("cancel_for_buffer(): cancelling queued send in buffer " .. bufnr)
    bridge.cancel_request({ bufnr = bufnr })
    return true
  end
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local ctx, _ = tool_context.resolve(bufnr, { row = cursor_pos[1], col = cursor_pos[2] })
  if ctx then
    log.debug("cancel_for_buffer(): cursor on tool " .. ctx.tool_id .. ", attempting cancel")
    autopilot.disarm(bufnr)
    return M.cancel(ctx.tool_id)
  end
  log.debug("cancel_for_buffer(): nothing to cancel in buffer " .. bufnr)
  return false
end

---Cancel the tool at cursor position (foreground or background).
---@param bufnr integer
---@return boolean cancelled
function M.cancel_at_cursor(bufnr)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local ctx, _ = tool_context.resolve(bufnr, { row = cursor_pos[1], col = cursor_pos[2] })
  if ctx then
    autopilot.disarm(bufnr)
    return M.cancel(ctx.tool_id)
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

  entry.job_id = M.generate_job_id(M.collect_buffer_job_ids(bufnr))
  local job_id = entry.job_id --[[@as string]]

  local header_ok, header_err = injector.set_header_modeline(bufnr, ctx.tool_id, "job=" .. job_id)
  if not header_ok then
    log.warn(
      "executor: background_at_cursor failed to update header for " .. ctx.tool_id .. ": " .. (header_err or "unknown")
    )
    entry.job_id = nil
    return false, "Failed to update header: " .. (header_err or "unknown")
  end

  local job_placeholder_text
  if is_tool_available("flemma.jobs.status", bufnr) then
    job_placeholder_text = messages.render("job-executing--tracked", { job_id = job_id })
  else
    job_placeholder_text = messages.render("job-executing--untracked")
  end
  local bg_config = config_facade.materialize(bufnr)
  local content_ok, content_err = injector.set_fence_content(
    bufnr,
    ctx.tool_id,
    job_placeholder_text,
    { compact = bg_config.editing and bg_config.editing.compact_headers }
  )
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

  local ap_state = autopilot.get_state(bufnr)
  if M.count_running(bufnr) == 0 and ap_state ~= "sending" then
    log.debug(
      "executor: all foreground tools clear after backgrounding (autopilot="
        .. ap_state
        .. "), scheduling send for buffer "
        .. bufnr
    )
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        bridge.send_or_execute({ bufnr = bufnr })
      end
    end)
  end

  return true, nil
end

---Resolve orphaned job results by injecting error blocks.
---@param bufnr integer
---@return integer count Number of orphans resolved
function M.resolve_orphaned_jobs(bufnr)
  log.debug("executor: scanning for orphaned background jobs in buffer " .. bufnr)
  local doc = parser.get_parsed_document(bufnr)

  local completed_jobs = {}
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "job_result" then
        ---@cast seg flemma.ast.JobResultSegment
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

  ---@type { job_id: string, tool_use_id: string }[]
  local orphans = {}
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "tool_result" and seg.meta and seg.meta.job then
        ---@cast seg flemma.ast.ToolResultSegment
        local job_id = seg.meta.job --[[@as string]]
        if not completed_jobs[job_id] and not active_jobs[job_id] then
          table.insert(orphans, {
            job_id = job_id,
            tool_use_id = seg.tool_use_id,
          })
        end
      end
    end
  end

  if #orphans > 0 then
    log.info("executor: found " .. #orphans .. " orphaned background job(s) in buffer " .. bufnr)
  else
    log.trace("executor: no orphaned background jobs in buffer " .. bufnr)
  end

  local orphan_config = #orphans > 0 and config_facade.materialize(bufnr) or nil
  local orphan_compact_opts = orphan_config
    and { compact = orphan_config.editing and orphan_config.editing.compact_headers }
  for _, orphan in ipairs(orphans) do
    log.debug("executor: resolving orphan " .. orphan.job_id .. " with error completion")
    injector.set_header_modeline(bufnr, orphan.tool_use_id, "error job=" .. orphan.job_id)
    injector.append_job_result(bufnr, orphan.job_id, {
      success = false,
      error = messages.render("job-lost"),
    }, orphan_compact_opts)
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

---Validate that a tool_result placeholder exists and is in a lifecycle state
---(pending/approved/denied/rejected) — not already completed or errored.
---@param bufnr integer
---@param tool_id string
---@return boolean ok
---@return string|nil error
local function validate_lifecycle_status(bufnr, tool_id)
  local doc = parser.get_parsed_document(bufnr)
  local tool_use_seg = ast.find_tool_use_by_id(doc, tool_id)
  if not tool_use_seg then
    return false, "Tool not found: " .. tool_id
  end
  local result_seg = ast.find_tool_sibling(doc, tool_use_seg)
  if not result_seg or result_seg.kind ~= "tool_result" then
    return false, "No tool result placeholder for " .. tool_id
  end
  ---@cast result_seg flemma.ast.ToolResultSegment
  if not result_seg.status or result_seg.status == "error" then
    return false, "Tool " .. tool_id .. " has already completed"
  end
  return true, nil
end

---Set the `(approved)` header suffix on a tool_result placeholder by tool ID.
---Re-engages autopilot if it was paused waiting for approval.
---@param bufnr integer
---@param tool_id string
---@param opts? { defer_ui?: boolean } defer_ui skips the synchronous UI refresh
---  (used by approve_all_pending, which refreshes once after the whole batch)
---@return boolean success
---@return string|nil error
function M.approve(bufnr, tool_id, opts)
  local valid, validate_err = validate_lifecycle_status(bufnr, tool_id)
  if not valid then
    return false, validate_err
  end
  local ok, update_err = injector.set_header_status(bufnr, tool_id, "approved")
  if not ok then
    return false, update_err
  end
  -- Refresh the full UI synchronously so the interactive approval prompt and the
  -- settled "— <label>" preview footer swap in a single redraw frame. The prompt
  -- (tool_approval_ns) is otherwise dropped on the incidental CursorMoved while
  -- the footer (tool_preview_ns, rendered only by add_tool_previews inside
  -- update_ui) doesn't appear until the next CursorHold-driven update_ui — which
  -- made the buffer "dance" up then down ~updatetime ms apart.
  if not (opts and opts.defer_ui) then
    ui.update_ui(bufnr)
  end
  editing.auto_write(bufnr)
  autopilot.nudge(bufnr)
  return true, nil
end

---Set the `(rejected)` header suffix on a tool_result placeholder by tool ID,
---optionally replacing the fence body with a user-supplied message that the
---model will see as the rejection reason.
---Re-engages autopilot if it was paused waiting for approval.
---@param bufnr integer
---@param tool_id string
---@param message string|nil Optional rejection message written into the fence
---@return boolean success
---@return string|nil error
function M.reject(bufnr, tool_id, message)
  local valid, validate_err = validate_lifecycle_status(bufnr, tool_id)
  if not valid then
    return false, validate_err
  end
  local ok, update_err = injector.set_header_status(bufnr, tool_id, "rejected")
  if not ok then
    return false, update_err
  end
  if message and message ~= "" then
    local reject_config = config_facade.materialize(bufnr)
    local content_ok, content_err = injector.set_fence_content(
      bufnr,
      tool_id,
      message,
      { compact = reject_config.editing and reject_config.editing.compact_headers }
    )
    if not content_ok then
      return false, content_err
    end
  end
  -- Refresh synchronously for the same reason as M.approve: keep the approval
  -- prompt → settled-state swap within one redraw frame instead of dancing.
  ui.update_ui(bufnr)
  editing.auto_write(bufnr)
  autopilot.nudge(bufnr)
  return true, nil
end

---Set the `(approved)` header suffix on the tool_result placeholder at cursor.
---Resolves the tool ID from cursor position, then delegates to approve().
---Advances cursor to the next pending tool result if any remain.
---@param bufnr integer
---@return boolean success
---@return string|nil error
function M.approve_at_cursor(bufnr)
  local ctx, _, err = resolve_lifecycle_tool_at_cursor(bufnr)
  if not ctx then
    return false, err
  end
  local ok, approve_err = M.approve(bufnr, ctx.tool_id)
  if ok then
    navigation.advance_to_next_pending(bufnr, ctx.tool_id)
  end
  return ok, approve_err
end

---Set the `(rejected)` header suffix on the tool_result placeholder at cursor.
---Resolves the tool ID from cursor position, then delegates to reject().
---Advances cursor to the next pending tool result if any remain.
---@param bufnr integer
---@param message string|nil Optional rejection message written into the fence
---@return boolean success
---@return string|nil error
function M.reject_at_cursor(bufnr, message)
  local ctx, _, err = resolve_lifecycle_tool_at_cursor(bufnr)
  if not ctx then
    return false, err
  end
  local ok, reject_err = M.reject(bufnr, ctx.tool_id, message)
  if ok then
    navigation.advance_to_next_pending(bufnr, ctx.tool_id)
  end
  return ok, reject_err
end

---Approve all pending tool_result placeholders in the buffer.
---@param bufnr integer
---@return boolean success
---@return string|nil error
function M.approve_all_pending(bufnr)
  local doc = parser.get_parsed_document(bufnr)
  local pending_ids = {}
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "tool_result" and seg.status == "pending" then
        pending_ids[#pending_ids + 1] = seg.tool_use_id
      end
    end
  end

  if #pending_ids == 0 then
    return false, "No pending tools to approve"
  end

  local failures = {}
  for _, tool_id in ipairs(pending_ids) do
    -- Defer the per-tool UI refresh; render once after the whole batch below.
    local ok, approve_err = M.approve(bufnr, tool_id, { defer_ui = true })
    if not ok then
      failures[#failures + 1] = tool_id .. ": " .. (approve_err or "unknown")
    end
  end

  ui.update_ui(bufnr)

  if #failures > 0 then
    log.warn("approve_all_pending: " .. #failures .. " failure(s): " .. table.concat(failures, "; "))
    return false, table.concat(failures, "; ")
  end

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
      local eac_config = config_facade.materialize(bufnr)
      injector.inject_result(bufnr, ctx.tool_id, {
        success = false,
        error = injector.resolve_error_message(result_seg.status --[[@as "rejected"|"denied"]], result_seg.content),
      }, { compact = eac_config.editing and eac_config.editing.compact_headers })
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
  elseif autopilot.get_state(bufnr) == "idle" then
    autopilot.disarm(bufnr)
  end

  local ok, success_or_err, err_msg = pcall(M.execute, bufnr, ctx)
  if not ok then
    local raised = success_or_err --[[@as flemma.readiness.Suspense|string]]
    if readiness.is_suspense(raised) then
      local suspense = raised --[[@as flemma.readiness.Suspense]]
      notify.warn(suspense.message)
      return false, suspense.message
    end
    error(raised)
  end
  return success_or_err, --[[@as boolean]]
    err_msg --[[@as string|nil]]
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

function M.setup()
  hooks.on("buffer:destroyed", function(data)
    M.cleanup_buffer(data.bufnr)
  end)
end

---@private
---@param bufnr integer
---@param tool_id string
---@param result flemma.tools.ExecutionResult
---@param opts? { async?: boolean }
function M._test_complete_execution(bufnr, tool_id, result, opts)
  do_completion(bufnr, tool_id, result, opts)
end

bridge.register("resolve_orphaned_jobs", M.resolve_orphaned_jobs)

return M
