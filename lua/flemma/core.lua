--- Core runtime functionality for Flemma plugin
--- Handles provider initialization, switching, and main request-response lifecycle
---@class flemma.Core
local M = {}

local config_facade = require("flemma.config")
local loader = require("flemma.loader")
local log = require("flemma.logging")
local notify = require("flemma.notify")
local readiness = require("flemma.readiness")
local secrets = require("flemma.secrets")
local state = require("flemma.state")
local normalize = require("flemma.provider.normalize")
local buffer_utils = require("flemma.utilities.buffer")
local editing = require("flemma.buffer.editing")
local writequeue = require("flemma.buffer.writequeue")
local ui = require("flemma.ui")
local registry = require("flemma.provider.registry")
local autopilot = require("flemma.autopilot")
local bridge = require("flemma.bridge")
local client = require("flemma.client")
local context_module = require("flemma.context")
local diagnostic_format = require("flemma.utilities.diagnostic")
local diagnostics_module = require("flemma.diagnostics")
local executor = require("flemma.tools.executor")
local injector = require("flemma.tools.injector")
local parser = require("flemma.parser")
local pipeline = require("flemma.pipeline")
local processor = require("flemma.processor")
local session_module = require("flemma.session")
local tool_approval = require("flemma.tools.approval")
local tool_context = require("flemma.tools.context")
local tools_module = require("flemma.tools")
local cursor = require("flemma.cursor")
local hooks = require("flemma.hooks")
local preprocessor = require("flemma.preprocessor")
local str = require("flemma.utilities.string")
local usage = require("flemma.usage")

local nav = require("flemma.schema.navigation")
local schema_definition = require("flemma.config.schema")

local ABORT_MESSAGE = "Response interrupted by the user."
local DEFAULT_MAX_CONCURRENT = 2

-- For testing purposes
local last_request_body_for_testing = nil

--- The parameters schema node, used to distinguish static (general) fields
--- from DISCOVER-resolved (provider-specific) fields.
---@type flemma.schema.Node
local parameters_schema = nav.unwrap_optional(schema_definition):get_child_schema("parameters") --[[@as flemma.schema.Node]]

---Write provider, model, and explicit parameters to the facade layer.
---General parameters are written to `parameters.<key>`, provider-specific
---parameters to `parameters.<provider>.<key>`.
---@param provider_name string Resolved provider name
---@param model_name? string Validated model name
---@param explicit_params? table<string, any> User's explicit parameter overrides
---@param layer? integer Facade layer to write to (default: RUNTIME)
local function apply_config(provider_name, model_name, explicit_params, layer)
  layer = layer or config_facade.LAYERS.RUNTIME
  local w = config_facade.writer(nil, layer)
  w.provider = provider_name
  if model_name then
    w.model = model_name
  end

  -- Write each explicit parameter to the correct namespaced path.
  -- Static fields on the parameters schema (max_tokens, thinking, etc.) are
  -- general params; everything else is provider-specific via DISCOVER.
  -- vim.NIL values (from modeline parse with preserve_nil) mean "explicitly
  -- clear this parameter" — convert to real nil for the proxy write, which
  -- records a set-nil op that shadows lower layers.
  if explicit_params then
    for k, v in pairs(explicit_params) do
      if k ~= "model" then
        local write_value
        if v == vim.NIL then
          write_value = nil
        else
          write_value = v
        end
        if parameters_schema:has_field(k) then
          w.parameters[k] = write_value
        else
          w.parameters[provider_name][k] = write_value
        end
      end
    end
  end

  log.debug(
    "apply_config(): Applied config - provider: "
      .. log.inspect(provider_name)
      .. ", model: "
      .. log.inspect(model_name)
      .. " (layer: "
      .. tostring(layer)
      .. ")"
  )
end

---Validate provider/model and write configuration to the facade layer.
---Providers are request-scoped — no global instance is created here.
---@param provider_name string
---@param model_name? string
---@param explicit_params? table<string, any> Only the user's explicit overrides
---@param layer? integer Facade layer for apply_config (default: RUNTIME)
---@return boolean success, string[] param_warnings, string|nil model_fallback_warning
local function initialize_provider(provider_name, model_name, explicit_params, layer)
  -- Validate provider
  if not registry.has(provider_name) then
    local err = string.format(
      "Unknown provider '%s'. Supported providers are: %s",
      tostring(provider_name),
      table.concat(registry.supported_providers(), ", ")
    )
    log.error("initialize_provider(): " .. err)
    notify.error(err)
    return false, {}
  end

  -- Resolve provider alias (e.g., 'claude' -> 'anthropic')
  local resolved_provider = registry.resolve(provider_name)

  -- Validate and get appropriate model
  local validated_model = registry.get_appropriate_model(model_name, resolved_provider)
  ---@type string|nil
  local model_fallback_warning
  if validated_model ~= model_name and model_name ~= nil then
    model_fallback_warning = string.format(
      "Model '%s' is not valid for provider '%s'. Using default: '%s'.",
      tostring(model_name),
      tostring(resolved_provider),
      tostring(validated_model)
    )
  end

  -- Write to facade
  apply_config(resolved_provider, validated_model, explicit_params, layer)

  -- Validate provider-specific parameters (advisory warnings, never fails)
  ---@type string[]
  local param_warnings = {}
  if validated_model then
    local resolved_config = config_facade.materialize()
    local flat_params = normalize.flatten_parameters(resolved_provider, resolved_config)
    normalize.resolve_max_tokens(resolved_provider, validated_model, flat_params)
    local provider_module_path = registry.get(resolved_provider)
    if provider_module_path then
      local provider_module = loader.load(provider_module_path)
      local _, warnings = provider_module.validate_parameters(validated_model, flat_params)
      if warnings then
        for _, w in ipairs(warnings) do
          table.insert(param_warnings, w)
          log.warn("validate_parameters(" .. resolved_provider .. "): " .. w)
        end
      end
    end
  end

  log.debug(
    "initialize_provider(): Prepared config for provider "
      .. log.inspect(resolved_provider)
      .. " with model "
      .. log.inspect(validated_model)
  )
  return true, param_warnings, model_fallback_warning
end

---Initialize provider for initial setup (exposed version).
---Emits validation warnings directly (unlike switch_provider which merges them).
---@param provider_name string
---@param model_name? string
---@param explicit_params? table<string, any> Only the user's explicit overrides
---@param layer? integer Facade layer for apply_config (default: RUNTIME)
---@return boolean success
function M.initialize_provider(provider_name, model_name, explicit_params, layer)
  local success, param_warnings, model_fallback = initialize_provider(provider_name, model_name, explicit_params, layer)
  if model_fallback or #param_warnings > 0 then
    -- Same multi-line format as switch_provider: header + bullet lines
    local resolved = registry.resolve(provider_name) or provider_name
    local validated_model = config_facade.get().model
    local model_desc = validated_model and (" with model '" .. validated_model .. "'") or ""
    local lines = { "Initialized '" .. resolved .. "'" .. model_desc }
    if model_fallback then
      table.insert(lines, "  ⚠ " .. model_fallback)
    end
    for _, w in ipairs(param_warnings) do
      table.insert(lines, "  • " .. w)
    end
    notify.warn(table.concat(lines, "\n"))
  end
  return success
end

---Switch to a different provider or model.
---Writes to the config facade RUNTIME layer. Providers are request-scoped —
---no global instance is created or stored.
---@param provider_name string
---@param model_name? string
---@param parameters? table<string, any>
---@param opts? { bufnr: integer }
---@return true|nil success True on success, nil on failure
function M.switch_provider(provider_name, model_name, parameters, opts)
  if not provider_name then
    notify.error("Provider name is required")
    return
  end

  local bufnr = (opts and opts.bufnr) or vim.api.nvim_get_current_buf()
  local buffer_state = state.get_buffer_state(bufnr)

  -- No mid-request guard needed: providers are request-scoped, so switching
  -- only affects the config facade. In-flight requests captured their own
  -- provider instance and are unaffected.
  --
  -- Note: prepare_config() validates before writing, so the facade is only
  -- mutated for valid providers. No rollback mechanism — if this fails, the
  -- facade retains its previous state from the last successful write.
  local init_ok, param_warnings, model_fallback = initialize_provider(provider_name, model_name, parameters or {})
  if not init_ok then
    log.warn("switch_provider(): Aborting switch due to invalid provider: " .. log.inspect(provider_name))
    return nil
  end

  -- Invalidate cached API keys — credentials don't carry across providers
  secrets.invalidate_all()

  -- Clear diagnostics request history — cache state doesn't carry across providers,
  -- so comparing requests from different providers would produce spurious warnings.
  buffer_state.diagnostics_previous_request = nil
  buffer_state.diagnostics_current_request = nil

  -- Evaluate frontmatter so L40 is populated before comparing. Without this,
  -- buffers that haven't sent yet would have empty L40 and the override check
  -- would silently miss frontmatter provider overrides.
  local fm_result = processor.evaluate_buffer_frontmatter(bufnr)
  buffer_state.frontmatter_eval_code = fm_result.frontmatter_code

  -- Notify the user. Header line + optional bullet lines for warnings/overrides.
  local global_config = config_facade.get()
  local buffer_config = config_facade.get(bufnr)
  local model_info = global_config.model and (" with model '" .. global_config.model .. "'") or ""
  local header = "Switched to '" .. global_config.provider .. "'" .. model_info
  ---@type string[]
  local lines = {}
  local notify_level = vim.log.levels.INFO

  -- Model fallback warning (invalid model → provider default)
  if model_fallback then
    table.insert(lines, "  ⚠ " .. model_fallback)
    notify_level = vim.log.levels.WARN
  end

  -- High-cost warning
  local model_entry = global_config.model and registry.get_model_info(global_config.provider, global_config.model)
  local high_cost_threshold = global_config.pricing.high_cost_threshold
  if
    model_entry
    and model_entry.pricing
    and model_entry.pricing.input + model_entry.pricing.output > high_cost_threshold
  then
    table.insert(lines, "  ⚠ Billed at " .. str.format_pricing_suffix(model_entry.pricing))
    notify_level = vim.log.levels.WARN
  end

  -- Frontmatter override notice (provider, model, or both)
  if buffer_config.provider ~= global_config.provider or buffer_config.model ~= global_config.model then
    local parts = {}
    if buffer_config.provider ~= global_config.provider then
      table.insert(parts, "'" .. buffer_config.provider .. "'")
    end
    if buffer_config.model ~= global_config.model then
      table.insert(parts, "model '" .. buffer_config.model .. "'")
    end
    table.insert(lines, "  • This buffer uses " .. table.concat(parts, " / ") .. " (frontmatter)")
  end

  -- Parameter validation warnings
  for _, w in ipairs(param_warnings) do
    table.insert(lines, "  • " .. w)
    notify_level = vim.log.levels.WARN
  end

  if #lines == 0 then
    header = header .. "."
  end
  table.insert(lines, 1, header)
  notify.notify(table.concat(lines, "\n"), notify_level)

  hooks.dispatch("config:updated")

  return true
end

---Cancel ongoing request if any
---@param opts? { bufnr: integer }
function M.cancel_request(opts)
  local bufnr = (opts and opts.bufnr) or vim.api.nvim_get_current_buf()
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

      local msg = "Request cancelled"
      if log.is_enabled() then
        msg = msg .. ". See " .. log.get_path() .. " for details"
      end
      notify.info(msg)
      -- Force UI update after cancellation
      ui.update_ui(bufnr)
      hooks.dispatch("request:finished", { bufnr = bufnr, status = "cancelled" })
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

---Phase 2 (Execute): Process tool_result blocks by lifecycle status.
---Called from Phase 1 via vim.schedule (undo boundary) or directly when Phase 1 has nothing.
---@param opts { on_request_complete?: fun(), bufnr: integer, evaluated_frontmatter?: flemma.processor.EvaluatedFrontmatter, user_initiated?: boolean }
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
  -- (pending) tool_result placeholder. Clear the header status suffix so
  -- the content becomes a normal resolved tool_result sent to the provider.
  local pending = tool_blocks["pending"] or {}
  for _, ctx in ipairs(pending) do
    if ctx.has_content then
      local ok, err = injector.clear_header_status(bufnr, ctx.tool_id)
      if not ok then
        log.warn("Failed to clear header status for " .. ctx.tool_id .. ": " .. (err or "unknown"))
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

  -- Process approved → execute tool
  local approved = tool_blocks["approved"] or {}
  local config = config_facade.get(bufnr)
  local max_concurrent = (config.tools and config.tools.max_concurrent) or DEFAULT_MAX_CONCURRENT
  local executed_count = 0
  local throttled = false

  for _, ctx in ipairs(approved) do
    if max_concurrent > 0 and executor.count_running(bufnr) >= max_concurrent then
      throttled = true
      break
    end
    local ok, err = executor.execute(bufnr, ctx)
    if not ok then
      notify.error(err or "Execution failed")
    else
      executed_count = executed_count + 1
    end
  end

  if throttled and opts.user_initiated then
    notify.info(
      "Executing " .. executed_count .. "/" .. #approved .. " tools (max_concurrent=" .. max_concurrent .. ")"
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
    -- Force UI update so tool preview virt_lines appear immediately.
    -- When all tools need approval (none approved), no executor.execute runs,
    -- so the update_ui call inside executor is never reached.
    ui.update_ui(bufnr)
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

  -- Phase 3: No lifecycle-status tool_result blocks remain and no unmatched tool_uses → send to provider
  M.send_to_provider({
    on_request_complete = opts.on_request_complete,
    bufnr = opts.bufnr,
    evaluated_frontmatter = opts.evaluated_frontmatter,
    user_initiated = opts.user_initiated,
  })
end

---Unified dispatch: three-phase advance algorithm.
---Phase 1 (Categorize): Find unmatched tool_use blocks → run approval → inject tool_result placeholders with a (status) suffix.
---Phase 2 (Execute): Process tool_result blocks by lifecycle status (approved/denied/rejected/pending).
---Phase 3 (Continue): No lifecycle-status blocks remain → send to provider.
---Both <C-]> and autopilot call this same function.
---@param opts? { on_request_complete?: fun(), bufnr?: integer, user_initiated?: boolean }
function M.send_or_execute(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  -- Early guard: reject immediately if a provider request is already in flight.
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.current_request then
    notify.warn("A request is already in progress. Use <C-c> to cancel it first.")
    return
  end

  -- Evaluate frontmatter once per dispatch cycle. The result is threaded through
  -- approval, executor, and pipeline so no caller needs to re-evaluate.
  -- Get raw (pre-rewriter) AST for a fresh interactive rewriter pass
  local raw_doc = parser.get_raw_document(bufnr)
  local interactive_doc = vim.deepcopy(raw_doc)

  -- Run preprocessor in interactive mode (may suspend for confirmations)
  local doc, rewriter_diagnostics = preprocessor.run(interactive_doc, bufnr, { interactive = true })
  if not doc then
    -- Confirmation pending — send aborted, UI prompt will be shown
    return
  end

  -- Store rewriter diagnostics for diagnostic rendering in send_to_provider
  buffer_state.rewriter_diagnostics = rewriter_diagnostics
  local context = context_module.from_buffer(bufnr)
  -- Evaluate frontmatter — writes config ops to the store's FRONTMATTER layer.
  -- After this call, config.get(bufnr) returns the resolved config including frontmatter.
  local evaluated_frontmatter = processor.evaluate_frontmatter(doc, context, bufnr)
  buffer_state.frontmatter_eval_code = evaluated_frontmatter.frontmatter_code
  -- Validation failures are merged into diagnostics below for unified rendering
  -- (they flow through the same flemma.notify formatter as other diagnostics).

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
      local decision = tool_approval.resolve(ctx.tool_name, ctx.input, { bufnr = bufnr, tool_id = ctx.tool_id })

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
      user_initiated = opts.user_initiated,
    }
    writequeue.schedule(bufnr, function()
      advance_phase2(phase2_opts)
    end)
    return
  end

  -- Phase 1 had nothing to categorize — run Phase 2 directly
  -- (handles existing lifecycle-status tool_result blocks from a previous Phase 1)
  advance_phase2({
    on_request_complete = opts.on_request_complete,
    bufnr = bufnr,
    evaluated_frontmatter = evaluated_frontmatter,
    user_initiated = opts.user_initiated,
  })
end

---@class flemma.core.BuildPromptFailure
---@field code "empty_buffer"|"no_provider"|"no_messages"|"unknown_provider"
---@field message string

---Build the prompt, context, and request-scoped provider for a buffer.
---Pure — no buffer lock, no progress UI, no HTTP side effects. Callers decide
---how to surface failures. `send_to_provider` uses this for the per-request
---build chain; `try_estimate_usage` uses the same helper for the count-tokens
---probe so both produce an identical request body.
---@param bufnr integer
---@param opts? { evaluated_frontmatter?: flemma.processor.EvaluatedFrontmatter }
---@return flemma.pipeline.Prompt|nil prompt
---@return flemma.Context|nil context
---@return flemma.provider.Base|nil provider
---@return flemma.processor.EvaluatedResult|nil evaluated
---@return flemma.core.BuildPromptFailure|nil failure
function M.build_prompt_and_provider(bufnr, opts)
  opts = opts or {}

  local doc = parser.get_parsed_document(bufnr)
  if #doc.messages == 0 and not doc.frontmatter then
    return nil, nil, nil, nil, { code = "empty_buffer", message = "Empty buffer — nothing to send." }
  end

  if not config_facade.get(bufnr).provider then
    return nil,
      nil,
      nil,
      nil,
      { code = "no_provider", message = "No provider configured. Use :Flemma switch to select one." }
  end

  local context = context_module.from_buffer(bufnr)
  local prompt, evaluated = pipeline.run(doc, context, {
    evaluated_frontmatter = opts.evaluated_frontmatter,
    bufnr = bufnr,
  })

  if #prompt.history == 0 then
    return nil, nil, nil, nil, { code = "no_messages", message = "No messages found in buffer." }
  end

  local effective_bufnr = prompt.bufnr
  local cfg = normalize.resolve_preset(config_facade.materialize(effective_bufnr))
  local provider_key = cfg.provider
  local flat_params = normalize.flatten_parameters(provider_key, cfg)
  normalize.resolve_max_tokens(provider_key, cfg.model, flat_params)

  local provider_module_path = registry.get(provider_key)
  if not provider_module_path then
    return nil,
      nil,
      nil,
      nil,
      {
        code = "unknown_provider",
        message = "Unknown provider '" .. tostring(provider_key) .. "'.",
      }
  end

  local provider = loader.load(provider_module_path).new(flat_params)
  return prompt, context, provider, evaluated, nil
end

---Handle the AI provider interaction
---@param opts? { on_request_complete?: fun(), bufnr?: integer, evaluated_frontmatter?: flemma.processor.EvaluatedFrontmatter, user_initiated?: boolean }
function M.send_to_provider(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local buffer_state = state.get_buffer_state(bufnr)

  -- Check if there's already a request in progress
  if buffer_state.current_request then
    notify.warn("A request is already in progress. Use <C-c> to cancel it first.")
    return
  end

  -- Check if tool executions are in progress (mutually exclusive with API requests)
  local pending_tools = executor.get_pending(bufnr)
  if #pending_tools > 0 then
    notify.warn("Cannot send while tool execution is in progress.")
    return
  end

  -- Gate on async tool sources being ready
  if not tools_module.is_ready() then
    notify.warn("Waiting for tool definitions to load…")
    if buffer_state.waiting_for_tools then
      return -- already queued
    end
    buffer_state.waiting_for_tools = true
    local target_bufnr = bufnr
    tools_module.on_ready(function()
      buffer_state.waiting_for_tools = false
      if vim.api.nvim_buf_is_valid(target_bufnr) then
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

  local prompt, context, current_provider, evaluated, build_failure = M.build_prompt_and_provider(bufnr, {
    evaluated_frontmatter = opts.evaluated_frontmatter,
  })

  if build_failure then
    state.unlock_buffer(bufnr)
    if build_failure.code == "empty_buffer" then
      log.warn("send_to_provider(): " .. build_failure.message)
    elseif build_failure.code == "no_provider" then
      log.error("send_to_provider(): No provider configured")
      notify.error(build_failure.message)
    elseif build_failure.code == "no_messages" then
      log.warn("send_to_provider(): No messages found in buffer")
      notify.warn(build_failure.message)
    elseif build_failure.code == "unknown_provider" then
      log.error("send_to_provider(): " .. build_failure.message)
      notify.error(build_failure.message)
    end
    return
  end
  ---@cast prompt flemma.pipeline.Prompt
  ---@cast context flemma.Context
  ---@cast current_provider flemma.provider.Base
  ---@cast evaluated flemma.processor.EvaluatedResult

  log.debug("send_to_provider(): Processed messages count: " .. #prompt.history)

  -- Merge rewriter diagnostics from interactive preprocessor pass
  local diagnostics = evaluated.diagnostics or {}
  for _, d in ipairs(buffer_state.rewriter_diagnostics or {}) do
    table.insert(diagnostics, d)
  end

  -- Display diagnostics to user if any
  if #diagnostics > 0 then
    local has_errors = false
    for _, diag in ipairs(diagnostics) do
      if diag.severity == "error" then
        has_errors = true
        break
      end
    end

    -- Leading blank so the first entry sits below the "Flemma:" title prefix
    -- that vim.notify's default adapter prepends; multi-line diagnostics
    -- otherwise collapse onto the prefix line.
    local diagnostic_lines = { "" }
    local MAX_DIAGNOSTICS = 10
    local sorted = diagnostic_format.sort(diagnostics)

    -- Render each diagnostic as icon + message, then location on next line.
    local rendered = 0
    for _, d in ipairs(sorted) do
      if rendered >= MAX_DIAGNOSTICS then
        table.insert(diagnostic_lines, string.format(" …and %d more", #sorted - MAX_DIAGNOSTICS))
        break
      end

      -- Blank line between diagnostics for readability (but not before the first)
      if rendered > 0 then
        table.insert(diagnostic_lines, "")
      end

      table.insert(diagnostic_lines, " " .. diagnostic_format.format_message(d))

      local loc = diagnostic_format.format_location(d)
      if loc then
        table.insert(diagnostic_lines, "   " .. loc)
      end

      for _, stack_line in ipairs(diagnostic_format.format_include_stack(d)) do
        table.insert(diagnostic_lines, "   " .. stack_line)
      end

      rendered = rendered + 1
    end

    -- Footer: clarify whether the request was blocked
    if has_errors then
      table.insert(diagnostic_lines, "")
      table.insert(diagnostic_lines, "Request blocked — fix errors to send.")
    end

    local level = has_errors and vim.log.levels.ERROR or vim.log.levels.WARN
    notify.notify(table.concat(diagnostic_lines, "\n"), level)
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
        error("No API key available for provider '" .. config_facade.get(bufnr).provider .. "'.", 0)
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
    if readiness.is_suspense(prep_result) then
      state.unlock_buffer(bufnr)
      error(prep_result)
    end
    notify.error(tostring(prep_result))
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
      .. log.inspect(config_facade.get(bufnr).provider)
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
  local provider_capabilities = registry.get_capabilities(config_facade.get(bufnr).provider)
  buffer_state.inflight_usage = {
    input_tokens = 0,
    output_tokens = 0,
    thoughts_tokens = 0,
    output_has_thoughts = provider_capabilities ~= nil and provider_capabilities.output_has_thoughts,
    cache_read_input_tokens = 0,
    cache_creation_input_tokens = 0,
  }

  -- Capture request start time for duration tracking (before callbacks so closures can see it)
  local request_started_at = session_module.now()

  -- Populated by on_response_complete once the session entry is recorded,
  -- then read by on_request_complete so the request:finished hook can carry
  -- the just-recorded request in its payload.
  ---@type flemma.session.Request|nil
  local latest_request = nil

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

        local notify_msg = msg
        if current_provider:is_context_overflow(msg) then
          notify_msg = notify_msg
            .. "\n\nYour conversation is too long for this model."
            .. " Remove earlier messages or start a new conversation."
        elseif current_provider:is_auth_error(msg) then
          local cred = current_provider:get_credential()
          secrets.invalidate(cred.kind, cred.service)
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
        notify.error(notify_msg)
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
        local config = config_facade.get(bufnr)

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
        local pricing_model_info = registry.get_model_info(config.provider, config.model)
        local pricing_info = pricing_model_info and pricing_model_info.pricing

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
            output_has_thoughts = provider_capabilities ~= nil and provider_capabilities.output_has_thoughts,
            cache_read_input_tokens = buffer_state.inflight_usage.cache_read_input_tokens,
            cache_creation_input_tokens = buffer_state.inflight_usage.cache_creation_input_tokens,
            cache_read_price = pricing_info.cache_read,
            cache_write_price = pricing_info.cache_write,
          })

          -- Use the just-created Request for the usage bar
          latest_request = session:get_latest_request()
          usage.show(bufnr, latest_request)
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
            hooks.dispatch("request:finished", { bufnr = bufnr, status = "errored" })
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
            notify.warn("Request completed but no response was received.")
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

          hooks.dispatch("request:finished", { bufnr = bufnr, status = "completed", request = latest_request })
        else
          -- cURL request failed (exit code ~= 0)
          -- Buffer is already set to modifiable = true
          ui.cleanup_progress(bufnr)

          local error_msg
          if code == 6 then -- CURLE_COULDNT_RESOLVE_HOST
            error_msg = string.format("cURL could not resolve host (exit code %d). Check network or hostname.", code)
          elseif code == 7 then -- CURLE_COULDNT_CONNECT
            error_msg =
              string.format("cURL could not connect to host (exit code %d). Check network or if the host is up.", code)
          elseif code == 28 then -- cURL timeout error
            local timeout_value = effective_timeout -- Captured before async callback
            error_msg = string.format(
              "cURL request timed out (exit code %d). Timeout is %s seconds.",
              code,
              tostring(timeout_value)
            )
          else -- Other cURL errors
            error_msg = string.format("cURL request failed (exit code %d).", code)
          end

          if log.is_enabled() then
            error_msg = error_msg .. " See " .. log.get_path() .. " for details."
          end
          notify.error(error_msg)

          editing.auto_write(bufnr) -- Auto-write if enabled, even on error
          ui.update_ui(bufnr) -- Update UI to remove any artifacts
          hooks.dispatch("request:finished", { bufnr = bufnr, status = "errored" })
        end
      end)
    end,
  }

  -- Headers and endpoint are already obtained above with API key validation

  hooks.dispatch("request:sending", { bufnr = bufnr })

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
    on_response_headers_fn = function(response_headers)
      current_provider:set_response_headers(response_headers)
    end,
    on_raw_json = function(raw_json_str)
      -- Store for diagnostics — will be compared after response completes
      local cfg = config_facade.get(bufnr)
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
bridge.register("build_prompt_and_provider", M.build_prompt_and_provider)

return M
