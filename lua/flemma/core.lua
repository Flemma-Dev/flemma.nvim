--- Core runtime functionality for Flemma plugin
--- Handles provider initialization, switching, and main request-response lifecycle
---@class flemma.Core
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")
local config_manager = require("flemma.core.config.manager")
local buffer_utils = require("flemma.utilities.buffer")
local editing = require("flemma.buffer.editing")
local writequeue = require("flemma.buffer.writequeue")
local ui = require("flemma.ui")
local registry = require("flemma.provider.registry")
local autopilot = require("flemma.autopilot")
local bridge = require("flemma.core.bridge")
local client = require("flemma.client")
local context_module = require("flemma.context")
local diagnostics_module = require("flemma.diagnostics")
local executor = require("flemma.tools.executor")
local injector = require("flemma.tools.injector")
local models_data = require("flemma.models")
local notifications = require("flemma.notifications")
local parser = require("flemma.parser")
local pipeline = require("flemma.pipeline")
local processor = require("flemma.processor")
local session_module = require("flemma.session")
local tool_approval = require("flemma.tools.approval")
local tool_context = require("flemma.tools.context")
local tools_module = require("flemma.tools")
local cursor = require("flemma.cursor")
local usage = require("flemma.usage")

local ABORT_MESSAGE = "Response interrupted by the user."
local DEFAULT_MAX_CONCURRENT = 2

-- For testing purposes
local last_request_body_for_testing = nil

---Initialize or switch provider based on configuration
---@param provider_name string
---@param model_name? string
---@param parameters? table<string, any>
---@return flemma.provider.Base|nil
local function initialize_provider(provider_name, model_name, parameters)
  -- Prepare configuration using the centralized config manager
  local provider_config, err = config_manager.prepare_config(provider_name, model_name, parameters)
  if not provider_config then
    vim.notify(err --[[@as string]], vim.log.levels.ERROR)
    return nil
  end

  -- Apply the configuration to global state
  config_manager.apply_config(provider_config)

  -- Create a fresh provider instance with the merged parameters
  local provider_module = registry.get(provider_config.provider)
  if not provider_module then
    local err_msg = "initialize_provider(): Invalid provider after validation: " .. tostring(provider_config.provider)
    log.error(err_msg)
    return nil
  end

  local new_provider = require(provider_module).new(provider_config.parameters)

  -- Update the global provider reference
  state.set_provider(new_provider)

  return new_provider
end

---Initialize provider for initial setup (exposed version)
---@param provider_name string
---@param model_name? string
---@param parameters? table<string, any>
---@return flemma.provider.Base|nil
function M.initialize_provider(provider_name, model_name, parameters)
  return initialize_provider(provider_name, model_name, parameters)
end

---Switch to a different provider or model
---@param provider_name string
---@param model_name? string
---@param parameters? table<string, any>
---@return flemma.provider.Base|nil
function M.switch_provider(provider_name, model_name, parameters)
  if not provider_name then
    vim.notify("Flemma: Provider name is required", vim.log.levels.ERROR)
    return
  end

  -- Check for ongoing requests
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.current_request then
    vim.notify("Flemma: Cannot switch providers while a request is in progress.", vim.log.levels.WARN)
    return
  end

  -- Ensure parameters is a table if nil
  parameters = parameters or {}

  -- Merge parameters using centralized logic
  local config = state.get_config()
  local merged_params = config_manager.merge_parameters(config.parameters, provider_name, parameters)

  -- Initialize the new provider using the centralized approach
  -- but do not commit the global config until validation succeeds.
  local prev_provider = state.get_provider()
  state.set_provider(nil) -- Clear the current provider
  local new_provider = initialize_provider(provider_name, model_name, merged_params)

  if not new_provider then
    -- Restore previous provider and keep existing config unchanged.
    state.set_provider(prev_provider)
    log.warn("switch_provider(): Aborting switch due to invalid provider: " .. log.inspect(provider_name))
    return nil
  end

  -- Commit the new configuration now that initialization succeeded.
  -- The config has already been updated by initialize_provider via config_manager.apply_config
  local updated_config = state.get_config()

  -- Force the new provider to clear its API key cache
  new_provider:reset({ auth = true })

  -- Clear diagnostics request history — cache state doesn't carry across providers,
  -- so comparing requests from different providers would produce spurious warnings.
  buffer_state.diagnostics_previous_request = nil
  buffer_state.diagnostics_current_request = nil

  -- Notify the user
  local model_info = updated_config.model and (" with model '" .. updated_config.model .. "'") or ""
  vim.notify("Flemma: Switched to '" .. updated_config.provider .. "'" .. model_info .. ".", vim.log.levels.INFO)

  -- Refresh lualine if available to update the model component
  local lualine_ok, lualine = pcall(require, "lualine")
  if lualine_ok and lualine.refresh then
    lualine.refresh()
    log.debug("switch_provider(): Lualine refreshed.")
  else
    log.debug("switch_provider(): Lualine not found or refresh function unavailable.")
  end

  return new_provider
end

---Cancel ongoing request if any
function M.cancel_request()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer_state = state.get_buffer_state(bufnr)

  if buffer_state.current_request then
    log.info("cancel_request(): job_id = " .. tostring(buffer_state.current_request))

    -- Mark as cancelled
    buffer_state.request_cancelled = true

    -- Discard any queued writes from on_content / on_request_complete
    -- that haven't executed yet. Must happen before the abort marker
    -- insertion below to prevent stale streaming content from appearing
    -- after the abort comment.
    writequeue.clear(bufnr)

    -- Use client to cancel the request
    if client.cancel_request(buffer_state.current_request) then
      buffer_state.current_request = nil
      parser.clear_ast_snapshot_before_send(bufnr)

      -- Clean up the buffer
      local last_line_content = buffer_utils.get_last_line(bufnr)

      if last_line_content == "@Assistant:" then
        -- No content received — clean up progress placeholder (empty @Assistant: block)
        log.debug("cancel_request(): ... Cleaning up empty @Assistant: progress placeholder")
        ui.cleanup_progress(bufnr)
      else
        -- Content was received — mark the response as aborted
        ui.cleanup_progress(bufnr)
        buffer_utils.with_modifiable(bufnr, function()
          local last_content, line_count = buffer_utils.get_last_line(bufnr)
          local separator = (last_content == "") and {} or { "" }
          ui.buffer_cmd(bufnr, "undojoin")
          vim.api.nvim_buf_set_lines(
            bufnr,
            line_count,
            line_count,
            false,
            vim.list_extend(separator, { "<!-- flemma:aborted: " .. ABORT_MESSAGE .. " -->" })
          )
        end)
        editing.auto_write(bufnr)
      end

      state.unlock_buffer(bufnr)

      -- Disarm autopilot on cancellation
      autopilot.disarm(bufnr)

      local msg = "Flemma: Request cancelled"
      if log.is_enabled() then
        msg = msg .. ". See " .. log.get_path() .. " for details"
      end
      vim.notify(msg, vim.log.levels.INFO)
      -- Force UI update after cancellation
      ui.update_ui(bufnr)
    end
  else
    log.debug("cancel_request(): No current request found")
    -- If there was no request, ensure buffer is modifiable if it somehow got stuck
    local bs = state.get_buffer_state(bufnr)
    if bs.locked then
      state.unlock_buffer(bufnr)
    end
  end
end

---Phase 2 (Execute): Process flemma:tool blocks by status.
---Called from Phase 1 via vim.schedule (undo boundary) or directly when Phase 1 has nothing.
---@param opts { on_request_complete?: fun(), bufnr: integer, evaluated_frontmatter?: flemma.processor.EvaluatedFrontmatter, frontmatter_opts?: flemma.opt.FrontmatterOpts, user_initiated?: boolean }
local function advance_phase2(opts)
  local bufnr = opts.bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Guard: if a provider request is already in flight (e.g., the user pressed
  -- <C-]> between the scheduled Phase 1 and this Phase 2), bail out to avoid
  -- a double-send race.
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.current_request then
    return
  end

  local autopilot_active = autopilot.is_enabled(bufnr)

  local tool_blocks = tool_context.resolve_all_tool_blocks(bufnr)

  -- Resolve user-filled pending blocks: the user pasted output into a
  -- flemma:tool status=pending block. Strip the fence info string so the
  -- content becomes a normal resolved tool_result sent to the provider.
  local pending = tool_blocks["pending"] or {}
  for _, ctx in ipairs(pending) do
    if ctx.has_content then
      local ok, err = injector.strip_fence_info_string(bufnr, ctx.tool_id)
      if not ok then
        log.warn("Failed to strip fence info string for " .. ctx.tool_id .. ": " .. (err or "unknown"))
      end
    end
  end

  -- Process denied → replace with error
  local denied = tool_blocks["denied"] or {}
  for _, ctx in ipairs(denied) do
    injector.inject_result(bufnr, ctx.tool_id, {
      success = false,
      error = injector.resolve_error_message("denied"),
    })
  end

  -- Process rejected → replace with user content or default error
  local rejected = tool_blocks["rejected"] or {}
  for _, ctx in ipairs(rejected) do
    injector.inject_result(bufnr, ctx.tool_id, {
      success = false,
      error = injector.resolve_error_message("rejected", ctx.content),
    })
  end

  -- Process aborted → replace with abort message from the marker
  local aborted = tool_blocks["aborted"] or {}
  for _, ctx in ipairs(aborted) do
    injector.inject_result(bufnr, ctx.tool_id, {
      success = false,
      error = ctx.aborted_message or ABORT_MESSAGE,
    })
  end

  -- Process approved → execute tool (pass pre-evaluated opts to avoid re-evaluating frontmatter)
  local approved = tool_blocks["approved"] or {}
  local config = state.get_config()
  local max_concurrent
  if opts.frontmatter_opts and opts.frontmatter_opts.max_concurrent ~= nil then
    max_concurrent = opts.frontmatter_opts.max_concurrent
  else
    max_concurrent = (config.tools and config.tools.max_concurrent) or DEFAULT_MAX_CONCURRENT
  end
  local executed_count = 0
  local throttled = false

  for _, ctx in ipairs(approved) do
    if max_concurrent > 0 and executor.count_running(bufnr) >= max_concurrent then
      throttled = true
      break
    end
    local ok, err = executor.execute(bufnr, ctx, opts.frontmatter_opts)
    if not ok then
      vim.notify("Flemma: " .. (err or "Execution failed"), vim.log.levels.ERROR)
    else
      executed_count = executed_count + 1
    end
  end

  if throttled and opts.user_initiated then
    vim.notify(
      "Flemma: Executing " .. executed_count .. "/" .. #approved .. " tools (max_concurrent=" .. max_concurrent .. ")",
      vim.log.levels.INFO
    )
  end

  -- Collect truly-pending blocks (empty content — user-filled ones were already resolved).
  -- Re-resolve positions if other blocks were processed (their injections shift line numbers).
  local pending_blocks = {}
  for _, ctx in ipairs(pending) do
    if not ctx.has_content then
      table.insert(pending_blocks, ctx)
    end
  end
  if (#denied > 0 or #rejected > 0 or #aborted > 0 or #approved > 0) and #pending_blocks > 0 then
    local fresh = tool_context.resolve_all_tool_blocks(bufnr)
    pending_blocks = {}
    for _, ctx in ipairs(fresh["pending"] or {}) do
      if not ctx.has_content then
        table.insert(pending_blocks, ctx)
      end
    end
  end

  if #approved > 0 then
    -- Tools were dispatched for execution — arm autopilot
    if autopilot_active then
      autopilot.arm(bufnr)
      -- Sync tools complete inline during the loop above, calling on_tools_complete
      -- before arm() — those calls are ignored (state wasn't "armed" yet).
      -- If all tools were sync, nothing will trigger on_tools_complete again, so
      -- we fire it manually. For async tools still running, their completion will
      -- trigger on_tools_complete normally (state is now "armed").
      if not executor.has_pending(bufnr) then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            autopilot.on_tools_complete(bufnr)
          end
        end)
      end
    end
    if opts.on_request_complete then
      opts.on_request_complete()
    end
    return
  end

  if #pending_blocks > 0 then
    -- Pending blocks remain — move cursor to the first one so the user can act
    local first = pending_blocks[1]
    cursor.request_move(bufnr, { line = first.tool_result.start_line, reason = "phase2/pending-block" })
    if opts.on_request_complete then
      opts.on_request_complete()
    end
    return
  end

  -- All denied/rejected/aborted were processed synchronously, no approved, no pending
  if #denied > 0 or #rejected > 0 or #aborted > 0 then
    editing.auto_write(bufnr)
    -- Non-empty tool blocks were processed — re-check if we should continue
    if autopilot_active then
      autopilot.arm(bufnr)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          autopilot.on_tools_complete(bufnr)
        end
      end)
    end
    if opts.on_request_complete then
      opts.on_request_complete()
    end
    return
  end

  -- Phase 3: No flemma:tool blocks remain and no unmatched tool_uses → send to provider
  M.send_to_provider({
    on_request_complete = opts.on_request_complete,
    bufnr = opts.bufnr,
    evaluated_frontmatter = opts.evaluated_frontmatter,
    user_initiated = opts.user_initiated,
  })
end

---Unified dispatch: three-phase advance algorithm.
---Phase 1 (Categorize): Find unmatched tool_use blocks → run approval → inject flemma:tool placeholders.
---Phase 2 (Execute): Process flemma:tool blocks by status (approved/denied/rejected/pending).
---Phase 3 (Continue): No tool blocks remain → send to provider.
---Both <C-]> and autopilot call this same function.
---@param opts? { on_request_complete?: fun(), bufnr?: integer, user_initiated?: boolean }
function M.send_or_execute(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  -- Early guard: reject immediately if a provider request is already in flight.
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.current_request then
    vim.notify("Flemma: A request is already in progress. Use <C-c> to cancel it first.", vim.log.levels.WARN)
    return
  end

  -- Evaluate frontmatter once per dispatch cycle. The result is threaded through
  -- approval, executor, and pipeline so no caller needs to re-evaluate.
  local doc = parser.get_parsed_document(bufnr)
  local context = context_module.from_buffer(bufnr)
  local evaluated_frontmatter = processor.evaluate_frontmatter(doc, context)
  local frontmatter_opts = evaluated_frontmatter.context:get_opts()

  -- Set per-buffer autopilot override unconditionally (nil clears a previous override)
  buffer_state.autopilot_override = frontmatter_opts and frontmatter_opts.autopilot

  -- Phase 1: Categorize — find tool_use blocks without matching tool_result
  local pending = tool_context.resolve_all_pending(bufnr)

  if #pending > 0 then
    local first_placeholder_line = nil

    -- Partition into aborted (skip approval) and normal (run approval)
    local aborted_pending = {}
    local normal_pending = {}
    for _, ctx in ipairs(pending) do
      if ctx.aborted then
        table.insert(aborted_pending, ctx)
      else
        table.insert(normal_pending, ctx)
      end
    end

    -- Aborted tools: inject placeholder with status=aborted directly (no approval)
    for _, ctx in ipairs(aborted_pending) do
      injector.inject_placeholder(bufnr, ctx.tool_id, { status = "aborted" })
    end

    -- Normal tools: run through approval flow
    for _, ctx in ipairs(normal_pending) do
      local decision = tool_approval.resolve(
        ctx.tool_name,
        ctx.input,
        { bufnr = bufnr, tool_id = ctx.tool_id, opts = frontmatter_opts }
      )

      ---@type flemma.ast.ToolStatus
      local status
      if decision == "approve" then
        status = "approved"
      elseif decision == "deny" then
        status = "denied"
      else
        status = "pending"
      end

      local header_line = injector.inject_placeholder(bufnr, ctx.tool_id, { status = status })
      if header_line and status == "pending" then
        if not first_placeholder_line or header_line < first_placeholder_line then
          first_placeholder_line = header_line
        end
      end
    end

    -- Move cursor to first pending placeholder so the user can review
    if first_placeholder_line then
      cursor.request_move(bufnr, { line = first_placeholder_line, reason = "phase1/pending-placeholder" })
    end

    -- Schedule Phase 2 via vim.schedule for undo boundary separation.
    -- Autopilot is NOT armed here — Phase 1 is purely categorization.
    -- Phase 2 arms autopilot after dispatching approved tools.
    local phase2_opts = {
      on_request_complete = opts.on_request_complete,
      bufnr = bufnr,
      evaluated_frontmatter = evaluated_frontmatter,
      frontmatter_opts = frontmatter_opts,
      user_initiated = opts.user_initiated,
    }
    writequeue.schedule(bufnr, function()
      advance_phase2(phase2_opts)
    end)
    return
  end

  -- Phase 1 had nothing to categorize — run Phase 2 directly
  -- (handles existing flemma:tool blocks from a previous Phase 1)
  advance_phase2({
    on_request_complete = opts.on_request_complete,
    bufnr = bufnr,
    evaluated_frontmatter = evaluated_frontmatter,
    frontmatter_opts = frontmatter_opts,
    user_initiated = opts.user_initiated,
  })
end

---Handle the AI provider interaction
---@param opts? { on_request_complete?: fun(), bufnr?: integer, evaluated_frontmatter?: flemma.processor.EvaluatedFrontmatter, user_initiated?: boolean }
function M.send_to_provider(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local buffer_state = state.get_buffer_state(bufnr)

  -- Check if there's already a request in progress
  if buffer_state.current_request then
    vim.notify("Flemma: A request is already in progress. Use <C-c> to cancel it first.", vim.log.levels.WARN)
    return
  end

  -- Check if tool executions are in progress (mutually exclusive with API requests)
  local pending_tools = executor.get_pending(bufnr)
  if #pending_tools > 0 then
    vim.notify("Flemma: Cannot send while tool execution is in progress.", vim.log.levels.WARN)
    return
  end

  -- Gate on async tool sources being ready
  if not tools_module.is_ready() then
    vim.notify("Flemma: Waiting for tool definitions to load…", vim.log.levels.WARN)
    if buffer_state.waiting_for_tools then
      return -- already queued
    end
    buffer_state.waiting_for_tools = true
    local target_bufnr = bufnr
    tools_module.on_ready(function()
      buffer_state.waiting_for_tools = false
      if vim.api.nvim_buf_is_valid(target_bufnr) and vim.api.nvim_get_current_buf() == target_bufnr then
        M.send_to_provider(opts)
      end
    end)
    return
  end

  log.info("send_to_provider(): Starting new request for buffer " .. bufnr)
  buffer_state.request_cancelled = false
  buffer_state.api_error_occurred = false -- Initialize flag for API errors

  -- Make the buffer non-modifiable to prevent user edits during request
  state.lock_buffer(bufnr)

  -- Parse buffer via cached AST (single buffer read + parse, reused below)
  local doc = parser.get_parsed_document(bufnr)

  -- Check if buffer has content
  if #doc.messages == 0 and not doc.frontmatter then
    log.warn("send_to_provider(): Empty buffer - nothing to send")
    state.unlock_buffer(bufnr)
    return
  end

  -- Get current provider
  local current_provider = state.get_provider()
  if not current_provider then
    log.error("send_to_provider(): No provider available")
    vim.notify("Flemma: No provider configured. Use :Flemma switch to select one.", vim.log.levels.ERROR)
    state.unlock_buffer(bufnr)
    return
  end

  -- Create context ONCE for the entire pipeline (used by frontmatter, @./file refs, etc.)
  local context = context_module.from_buffer(bufnr)

  -- Run the pipeline with the pre-parsed document. If frontmatter was already
  -- evaluated by send_or_execute, reuse it to avoid re-executing frontmatter code.
  local prompt, evaluated = pipeline.run(doc, context, {
    evaluated_frontmatter = opts.evaluated_frontmatter,
    bufnr = bufnr,
  })

  if #prompt.history == 0 then
    log.warn("send_to_provider(): No messages found in buffer")
    vim.notify("Flemma: No messages found in buffer.", vim.log.levels.WARN)
    state.unlock_buffer(bufnr)
    return
  end

  log.debug("send_to_provider(): Processed messages count: " .. #prompt.history)

  -- Display diagnostics to user if any
  local diagnostics = evaluated.diagnostics or {}
  if #diagnostics > 0 then
    local has_errors = false
    local by_type = { frontmatter = {}, expression = {}, file = {}, tool_result = {}, tool_use = {} }

    for _, diag in ipairs(diagnostics) do
      if diag.severity == "error" then
        has_errors = true
      end
      local type_bucket = by_type[diag.type] or {}
      table.insert(type_bucket, diag)
      by_type[diag.type] = type_bucket
    end

    local diagnostic_lines = {}
    local max_per_type = 5

    local function format_position(pos)
      if not pos then
        return ""
      end
      if pos.start_line then
        if pos.start_col then
          return string.format(":%d:%d", pos.start_line, pos.start_col)
        end
        return string.format(":%d", pos.start_line)
      end
      return ""
    end

    -- Format frontmatter errors
    if #by_type.frontmatter > 0 then
      table.insert(diagnostic_lines, "Frontmatter errors:")
      for i, d in ipairs(by_type.frontmatter) do
        if i <= max_per_type then
          local loc = (d.source_file or "N/A") .. format_position(d.position)
          table.insert(diagnostic_lines, string.format("  [%s] %s", loc, d.error))
        elseif i == max_per_type + 1 then
          table.insert(diagnostic_lines, string.format("  …and %d more", #by_type.frontmatter - max_per_type))
          break
        end
      end
    end

    -- Format expression errors (non-fatal warnings)
    if #by_type.expression > 0 then
      table.insert(diagnostic_lines, "Expression evaluation errors (request will still be sent):")
      for i, d in ipairs(by_type.expression) do
        if i <= max_per_type then
          local loc = (d.source_file or "N/A") .. format_position(d.position)
          local role_info = d.message_role and (" in @" .. d.message_role) or ""
          table.insert(diagnostic_lines, string.format("  [%s%s] %s", loc, role_info, d.error))
          table.insert(diagnostic_lines, string.format("    Expression: {{ %s }}", d.expression or ""))
        elseif i == max_per_type + 1 then
          table.insert(diagnostic_lines, string.format("  …and %d more", #by_type.expression - max_per_type))
          break
        end
      end
    end

    -- Format file reference warnings
    if #by_type.file > 0 then
      table.insert(diagnostic_lines, "File reference errors:")
      for i, d in ipairs(by_type.file) do
        if i <= max_per_type then
          local loc = (d.source_file or "N/A") .. format_position(d.position)
          local ref = d.filename or d.raw or "unknown"
          table.insert(diagnostic_lines, string.format("  [%s] %s: %s", loc, ref, d.error))
          if d.include_stack and #d.include_stack > 0 then
            table.insert(diagnostic_lines, "  Caused by:")
            for _, path in ipairs(d.include_stack) do
              table.insert(diagnostic_lines, "  ↓ " .. path)
            end
            table.insert(diagnostic_lines, "  → " .. (d.raw or d.filename))
          end
        elseif i == max_per_type + 1 then
          table.insert(diagnostic_lines, string.format("  …and %d more", #by_type.file - max_per_type))
          break
        end
      end
    end

    -- Format tool use/result warnings
    local tool_diags = {}
    for _, d in ipairs(by_type.tool_use) do
      table.insert(tool_diags, d)
    end
    for _, d in ipairs(by_type.tool_result) do
      table.insert(tool_diags, d)
    end
    if #tool_diags > 0 then
      table.insert(diagnostic_lines, "Tool calling errors:")
      for i, d in ipairs(tool_diags) do
        if i <= max_per_type then
          local loc = format_position(d.position)
          table.insert(diagnostic_lines, string.format("  [%s] %s", loc, d.error))
        elseif i == max_per_type + 1 then
          table.insert(diagnostic_lines, string.format("  …and %d more", #tool_diags - max_per_type))
          break
        end
      end
    end

    -- Generic fallback: render any custom: diagnostic type.
    -- Diagnostics must carry a `label` field for the section heading.
    for dtype, bucket in pairs(by_type) do
      if dtype:sub(1, 7) == "custom:" and #bucket > 0 then
        local short_type = dtype:sub(8) -- strip "custom:" prefix
        local heading = string.format("[%s] %s", short_type, bucket[1].label or short_type)
        table.insert(diagnostic_lines, heading)
        for i, d in ipairs(bucket) do
          if i <= max_per_type then
            table.insert(diagnostic_lines, string.format("  %s", d.error or "unknown"))
          elseif i == max_per_type + 1 then
            table.insert(diagnostic_lines, string.format("  …and %d more", #bucket - max_per_type))
            break
          end
        end
      end
    end

    local level = has_errors and vim.log.levels.ERROR or vim.log.levels.WARN
    vim.notify("Flemma diagnostics:\n" .. table.concat(diagnostic_lines, "\n"), level)
    log.warn("send_to_provider(): Diagnostics occurred: " .. #diagnostics .. " total")

    -- Block request if there are critical errors (frontmatter parsing failures)
    if has_errors then
      log.error("send_to_provider(): Blocking request due to critical errors")
      state.unlock_buffer(bufnr)
      return
    end
  end

  log.debug("send_to_provider(): Prompt history for provider: " .. log.inspect(prompt.history))
  log.debug("send_to_provider(): System instruction: " .. log.inspect(prompt.system))

  -- Apply frontmatter parameter overrides so that get_endpoint / get_api_key see them.
  -- Merge general parameters (flemma.opt.cache_retention) with provider-specific ones
  -- (flemma.opt.anthropic.thinking_budget). Provider-specific wins on conflict.
  local provider_key = state.get_config().provider
  local general_overrides = prompt.opts and prompt.opts.parameters
  local provider_specific_overrides = prompt.opts and prompt.opts[provider_key]
  local merged_overrides = nil
  if general_overrides or provider_specific_overrides then
    merged_overrides = {}
    if general_overrides then
      for k, v in pairs(general_overrides) do
        merged_overrides[k] = v
      end
    end
    if provider_specific_overrides then
      for k, v in pairs(provider_specific_overrides) do
        merged_overrides[k] = v
      end
    end
  end
  if merged_overrides and merged_overrides.max_tokens ~= nil then
    local config = state.get_config()
    config_manager.resolve_max_tokens(config.provider, config.model, merged_overrides)
  end
  current_provider:set_parameter_overrides(merged_overrides)

  -- Validate provider (endpoint, API key, headers) and build request body.
  -- Wrapped in pcall so any provider error unlocks the buffer cleanly.
  local prep_ok, prep_result = pcall(function()
    local endpoint = current_provider:get_endpoint()
    if not endpoint then
      error("Provider did not return an endpoint.", 0)
    end

    local fixture_path = client.find_fixture_for_endpoint(endpoint)

    local headers
    if not fixture_path then
      local api_key = current_provider:get_api_key()
      if not api_key then
        error("No API key available for provider '" .. state.get_config().provider .. "'.", 0)
      end
      headers = current_provider:get_request_headers()
      if not headers then
        error("Provider did not return request headers.", 0)
      end
    else
      headers = { "content-type: application/json" }
    end

    local request_body = current_provider:build_request(prompt, context)
    local trailing_keys = current_provider:get_trailing_keys()
    return { endpoint = endpoint, headers = headers, request_body = request_body, trailing_keys = trailing_keys }
  end)

  if not prep_ok then
    vim.notify("Flemma: " .. tostring(prep_result), vim.log.levels.ERROR)
    state.unlock_buffer(bufnr)
    return
  end

  local endpoint = prep_result.endpoint
  local headers = prep_result.headers
  local request_body = prep_result.request_body
  local trailing_keys = prep_result.trailing_keys
  last_request_body_for_testing = request_body -- Store for testing

  -- Capture timeout now so the on_request_complete closure doesn't read stale proxy state
  local effective_timeout = current_provider.parameters.timeout

  -- Log the request details (using the provider's stored model)
  log.debug(
    "send_to_provider(): Sending request for provider "
      .. log.inspect(state.get_config().provider)
      .. " with model "
      .. log.inspect(current_provider.parameters.model)
  )

  -- Snapshot the AST before the @Assistant: placeholder is written.
  -- During streaming, get_parsed_document will parse only the suffix.
  parser.create_ast_snapshot_before_send(bufnr)

  ---@type integer|nil
  local progress_timer = ui.start_progress(bufnr, { force = opts.user_initiated, timeout = effective_timeout or 600 })
  local response_started = false

  -- Reset in-flight usage tracking for this buffer
  -- Include the provider's output_has_thoughts flag so usage.lua can display correctly
  local provider_capabilities = registry.get_capabilities(state.get_config().provider)
  buffer_state.inflight_usage = {
    input_tokens = 0,
    output_tokens = 0,
    thoughts_tokens = 0,
    output_has_thoughts = provider_capabilities and provider_capabilities.output_has_thoughts or false,
    cache_read_input_tokens = 0,
    cache_creation_input_tokens = 0,
  }

  -- Capture request start time for duration tracking (before callbacks so closures can see it)
  local request_started_at = session_module.now()

  -- Set up callbacks for the provider
  local callbacks = {
    on_error = function(msg)
      writequeue.schedule(bufnr, function()
        if progress_timer then
          vim.fn.timer_stop(progress_timer)
        end
        ui.cleanup_progress(bufnr)
        buffer_state.current_request = nil
        parser.clear_ast_snapshot_before_send(bufnr)
        buffer_state.api_error_occurred = true -- Set flag indicating API error

        state.unlock_buffer(bufnr)

        -- Auto-write on error if enabled
        editing.auto_write(bufnr)

        local notify_msg = "Flemma: " .. msg
        if current_provider:is_context_overflow(msg) then
          notify_msg = notify_msg
            .. "\n\nYour conversation is too long for this model."
            .. " Remove earlier messages or start a new conversation."
        elseif current_provider:is_auth_error(msg) then
          current_provider:reset({ auth = true })
          notify_msg = notify_msg .. "\n\nAuthentication expired. Send again to generate a fresh token."
        elseif current_provider:is_rate_limit_error(msg) then
          local details = current_provider:format_rate_limit_details()
          if details then
            notify_msg = notify_msg .. "\n\n" .. details
          end
          notify_msg = notify_msg .. "\n\nTry again in a moment."
        end
        if log.is_enabled() then
          notify_msg = notify_msg .. "\nSee " .. log.get_path() .. " for details"
        end
        vim.notify(notify_msg, vim.log.levels.ERROR)
      end)
    end,

    on_usage = function(usage_data)
      if usage_data.type == "input" then
        buffer_state.inflight_usage.input_tokens = usage_data.tokens
      elseif usage_data.type == "output" then
        buffer_state.inflight_usage.output_tokens = usage_data.tokens
      elseif usage_data.type == "thoughts" then
        buffer_state.inflight_usage.thoughts_tokens = usage_data.tokens
      elseif usage_data.type == "cache_read" then
        buffer_state.inflight_usage.cache_read_input_tokens = usage_data.tokens
      elseif usage_data.type == "cache_creation" then
        buffer_state.inflight_usage.cache_creation_input_tokens = usage_data.tokens
      end
    end,

    on_response_complete = function()
      vim.schedule(function()
        local config = state.get_config()

        -- Get tokens from in-flight usage
        local input_tokens = buffer_state.inflight_usage.input_tokens or 0
        local output_tokens = buffer_state.inflight_usage.output_tokens or 0
        local thoughts_tokens = buffer_state.inflight_usage.thoughts_tokens or 0

        -- Get buffer filepath (resolved to handle symlinks, relative paths, etc.)
        local filepath = nil
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        if bufname and bufname ~= "" then
          -- Resolve to canonical path (handles symlinks, .. etc.)
          filepath = vim.loop.fs_realpath(bufname) or bufname
        end

        -- Add request to session with pricing snapshot
        local provider_data = models_data.providers[config.provider]
        local model_info = provider_data and provider_data.models[config.model]
        local pricing_info = model_info and model_info.pricing

        if pricing_info then
          local session = state.get_session()
          session:add_request({
            provider = config.provider,
            model = config.model,
            input_tokens = input_tokens,
            output_tokens = output_tokens,
            thoughts_tokens = thoughts_tokens,
            input_price = pricing_info.input,
            output_price = pricing_info.output,
            filepath = filepath,
            bufnr = bufnr,
            started_at = request_started_at,
            completed_at = session_module.now(),
            output_has_thoughts = provider_capabilities and provider_capabilities.output_has_thoughts or false,
            cache_read_input_tokens = buffer_state.inflight_usage.cache_read_input_tokens,
            cache_creation_input_tokens = buffer_state.inflight_usage.cache_creation_input_tokens,
            cache_read_price = pricing_info.cache_read,
            cache_write_price = pricing_info.cache_write,
          })

          -- Use the just-created Request for the notification
          local latest_request = session:get_latest_request()
          local segments = usage.build_segments(latest_request, session)
          if #segments > 0 then
            notifications.show(segments, bufnr)
          end
        end

        -- Diagnostics: compare request with previous
        if config.diagnostics and config.diagnostics.enabled then
          local raw_json_str = buffer_state._diagnostics_raw_json
          if raw_json_str then
            diagnostics_module.record_and_compare(bufnr, raw_json_str)
            buffer_state._diagnostics_raw_json = nil
          end
        end

        -- Auto-write when response is complete
        writequeue.enqueue(bufnr, function()
          editing.auto_write(bufnr)
        end)

        -- Reset in-flight usage for next request
        -- Note: output_has_thoughts will be set again when the next request starts
        buffer_state.inflight_usage = {
          input_tokens = 0,
          output_tokens = 0,
          thoughts_tokens = 0,
          output_has_thoughts = false, -- Default, will be overwritten on next request
          cache_read_input_tokens = 0,
          cache_creation_input_tokens = 0,
        }
      end)
    end,

    on_thinking = function(delta)
      vim.schedule(function()
        buffer_state.progress_char_count = buffer_state.progress_char_count + #delta
        -- Stay in virt_text mode (no buffer content yet), but show counter instead of "Waiting..."
        if buffer_state.progress_phase == "waiting" or buffer_state.progress_phase == "thinking" then
          buffer_state.progress_phase = "thinking"
        end
      end)
    end,

    on_content = function(text)
      writequeue.schedule(bufnr, function()
        -- Skip whitespace-only content before the response has started.
        -- Some models (e.g. Opus 4.6 with adaptive thinking) emit a text block
        -- containing only newlines before the thinking block. Writing this would
        -- prematurely clear the thinking preview extmark.
        if not response_started and not text:match("%S") then
          return
        end

        buffer_utils.with_modifiable(bufnr, function()
          if not response_started then
            -- Transition progress to streaming BEFORE modifying the buffer so the
            -- timer never attempts to update the inline extmark on a line that is
            -- about to be deleted.
            buffer_state.progress_phase = "streaming"

            -- Remove the @Assistant: placeholder line that start_progress created.
            -- The code below re-writes @Assistant: with actual content.
            local placeholder = buffer_utils.get_last_line(bufnr)
            if placeholder == "@Assistant:" then
              local lc = vim.api.nvim_buf_line_count(bufnr)
              local prev_content = lc > 1 and buffer_utils.get_line(bufnr, lc - 1) or nil
              ui.buffer_cmd(bufnr, "undojoin")
              if prev_content and prev_content:match("%S") then
                vim.api.nvim_buf_set_lines(bufnr, lc - 1, lc, false, { "" })
              else
                vim.api.nvim_buf_set_lines(bufnr, lc - 1, lc, false, {})
              end
            end
          end

          -- Split content into lines
          local content_lines = vim.split(text, "\n", { plain = true })

          if #content_lines > 0 then
            local last_line = vim.api.nvim_buf_line_count(bufnr)

            if not response_started then
              local header_lines

              if content_lines[1]:match("^%*%*Tool Use:%*%*") then
                -- Tool use header on its own line so the block is independently foldable
                ui.buffer_cmd(bufnr, "undojoin")
                vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant:", "", content_lines[1] })
                header_lines = 3
              elseif content_lines[1]:match("^```") then
                -- Code fence on its own line (no blank separator needed)
                ui.buffer_cmd(bufnr, "undojoin")
                vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant:", content_lines[1] })
                header_lines = 2
              else
                ui.buffer_cmd(bufnr, "undojoin")
                vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant:", content_lines[1] })
                header_lines = 2
              end

              -- Add remaining lines if any
              if #content_lines > 1 then
                ui.buffer_cmd(bufnr, "undojoin")
                vim.api.nvim_buf_set_lines(
                  bufnr,
                  last_line + header_lines,
                  last_line + header_lines,
                  false,
                  { unpack(content_lines, 2) }
                )
              end
            else
              -- Get the last line's content
              local last_line_content = buffer_utils.get_line(bufnr, last_line)

              if #content_lines == 1 then
                -- Just append to the last line
                ui.buffer_cmd(bufnr, "undojoin")
                vim.api.nvim_buf_set_lines(
                  bufnr,
                  last_line - 1,
                  last_line,
                  false,
                  { last_line_content .. content_lines[1] }
                )
              else
                -- First chunk goes to the end of the last line
                ui.buffer_cmd(bufnr, "undojoin")
                vim.api.nvim_buf_set_lines(
                  bufnr,
                  last_line - 1,
                  last_line,
                  false,
                  { last_line_content .. content_lines[1] }
                )

                -- Remaining lines get added as new lines
                ui.buffer_cmd(bufnr, "undojoin")
                vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { unpack(content_lines, 2) })
              end
            end

            response_started = true

            -- Update progress tracking
            buffer_state.progress_phase = "streaming"
            buffer_state.progress_char_count = buffer_state.progress_char_count + #text
            buffer_state.progress_last_line = vim.api.nvim_buf_line_count(bufnr) - 1

            -- Force UI update after appending content
            ui.update_ui(bufnr)
          end
        end)
      end)
    end,

    on_tool_input = function(delta)
      vim.schedule(function()
        buffer_state.progress_phase = "buffering"
        buffer_state.progress_char_count = buffer_state.progress_char_count + #delta
      end)
    end,

    on_request_complete = function(code)
      writequeue.schedule(bufnr, function()
        -- If the request was cancelled, M.cancel_request() handles cleanup including modifiable.
        if buffer_state.request_cancelled then
          -- M.cancel_request should have already set modifiable = true
          -- and stopped the progress timer.
          if progress_timer then
            vim.fn.timer_stop(progress_timer)
            progress_timer = nil
          end
          return
        end

        -- Stop the progress timer if it's still active.
        -- cleanup_progress will also try to stop state.progress_timer.
        if progress_timer then
          vim.fn.timer_stop(progress_timer)
          progress_timer = nil
        end
        buffer_state.current_request = nil -- Mark request as no longer current
        parser.clear_ast_snapshot_before_send(bufnr)

        -- Ensure buffer is modifiable for final operations and user interaction
        state.unlock_buffer(bufnr)

        if code == 0 then
          -- cURL request completed successfully (exit code 0)
          if buffer_state.api_error_occurred then
            log.debug(
              "send_to_provider(): on_request_complete: cURL success (code 0), but an API error was previously handled. Skipping new prompt."
            )
            buffer_state.api_error_occurred = false -- Reset flag for next request
            if not response_started then
              ui.cleanup_progress(bufnr)
            end
            editing.auto_write(bufnr) -- Still auto-write if configured
            ui.update_ui(bufnr) -- Update UI
            return -- Do not proceed to add new prompt or call opts.on_request_complete
          end

          -- Clean up progress line extmarks and float (timer already stopped above).
          -- On the happy path the @Assistant: placeholder has real content, so
          -- cleanup_progress won't remove any buffer lines — it only removes a
          -- bare "@Assistant:" placeholder.
          ui.cleanup_progress(bufnr)

          if not response_started then
            log.warn(
              "send_to_provider(): on_request_complete: cURL success (code 0), no API error, but no response content was processed."
            )
            vim.notify("Flemma: Request completed but no response was received.", vim.log.levels.WARN)
          end

          -- Add new "@You:" prompt for the next message (buffer is already modifiable)
          local last_line_content, last_line_idx = buffer_utils.get_last_line(bufnr)

          local lines_to_insert
          local cursor_line_offset
          if last_line_content == "" then
            lines_to_insert = { "@You:", "" }
            cursor_line_offset = 2
          else
            lines_to_insert = { "", "@You:", "" }
            cursor_line_offset = 3
          end

          ui.buffer_cmd(bufnr, "undojoin")
          vim.api.nvim_buf_set_lines(bufnr, last_line_idx, last_line_idx, false, lines_to_insert)

          -- Position cursor on the blank content line after @You:
          local new_prompt_line = last_line_idx + cursor_line_offset
          cursor.request_move(bufnr, { line = new_prompt_line, bottom = true, reason = "response-complete" })

          editing.auto_write(bufnr)
          ui.update_ui(bufnr)

          if opts.on_request_complete then
            opts.on_request_complete()
          end

          -- Hook autopilot: check if assistant response contains tool_use
          autopilot.on_response_complete(bufnr)
        else
          -- cURL request failed (exit code ~= 0)
          -- Buffer is already set to modifiable = true
          ui.cleanup_progress(bufnr)

          local error_msg
          if code == 6 then -- CURLE_COULDNT_RESOLVE_HOST
            error_msg =
              string.format("Flemma: cURL could not resolve host (exit code %d). Check network or hostname.", code)
          elseif code == 7 then -- CURLE_COULDNT_CONNECT
            error_msg = string.format(
              "Flemma: cURL could not connect to host (exit code %d). Check network or if the host is up.",
              code
            )
          elseif code == 28 then -- cURL timeout error
            local timeout_value = effective_timeout -- Captured before async callback
            error_msg = string.format(
              "Flemma: cURL request timed out (exit code %d). Timeout is %s seconds.",
              code,
              tostring(timeout_value)
            )
          else -- Other cURL errors
            error_msg = string.format("Flemma: cURL request failed (exit code %d).", code)
          end

          if log.is_enabled() then
            error_msg = error_msg .. " See " .. log.get_path() .. " for details."
          end
          vim.notify(error_msg, vim.log.levels.ERROR)

          editing.auto_write(bufnr) -- Auto-write if enabled, even on error
          ui.update_ui(bufnr) -- Update UI to remove any artifacts
        end
      end)
    end,
  }

  -- Headers and endpoint are already obtained above with API key validation

  -- Send the request using the client
  buffer_state.current_request = client.send_request({
    request_body = request_body,
    headers = headers,
    endpoint = endpoint,
    parameters = current_provider.parameters,
    callbacks = callbacks,
    trailing_keys = trailing_keys,
    process_response_line_fn = function(line, cb)
      return current_provider:process_response_line(line, cb)
    end,
    finalize_response_fn = function(exit_code, cb)
      return current_provider:finalize_response(exit_code, cb)
    end,
    reset_fn = function()
      return current_provider:reset()
    end,
    on_response_headers_fn = function(response_headers)
      current_provider:set_response_headers(response_headers)
    end,
    on_raw_json = function(raw_json_str)
      -- Store for diagnostics — will be compared after response completes
      local cfg = state.get_config()
      if cfg.diagnostics and cfg.diagnostics.enabled then
        buffer_state._diagnostics_raw_json = raw_json_str
      end
    end,
  })

  if not buffer_state.current_request or buffer_state.current_request == 0 or buffer_state.current_request == -1 then
    log.error("send_to_provider(): Failed to start provider job.")
    -- Stop the progress timer if it was started
    if progress_timer then
      vim.fn.timer_stop(progress_timer)
      buffer_state.progress_timer = nil
    end
    ui.cleanup_progress(bufnr)
    parser.clear_ast_snapshot_before_send(bufnr)
    state.unlock_buffer(bufnr)
    return
  end
  -- If job started successfully, modifiable remains false (as set at the start of this function).
end

---Get the last request body (for testing)
---@return table<string, any>|nil
function M._get_last_request_body()
  return last_request_body_for_testing
end

---Expose UI update function
---@param bufnr integer
function M.update_ui(bufnr)
  return ui.update_ui(bufnr)
end

-- Register core functions with the bridge so modules that cannot
-- require core directly (due to circular dependencies) can dispatch to them.
bridge.register("send_or_execute", M.send_or_execute)
bridge.register("cancel_request", M.cancel_request)
bridge.register("update_ui", M.update_ui)

return M
