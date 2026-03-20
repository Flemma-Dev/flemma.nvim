--- Collects runtime status data from all Flemma subsystems
--- Used by :Flemma status to display current configuration and state
---@class flemma.Status
local M = {}

local state = require("flemma.state")
local config_manager = require("flemma.core.config.manager")
local autopilot = require("flemma.autopilot")
local sandbox = require("flemma.sandbox")
local str = require("flemma.utilities.string")
local tools_module = require("flemma.tools")
local tools_approval = require("flemma.tools.approval")
local tools_registry = require("flemma.tools.registry")
local registry = require("flemma.provider.registry")

local MARKER_FRONTMATTER = "✲"
local MARKER_SANDBOX = "⊡"

---@class flemma.status.ShowOptions
---@field verbose? boolean Include full config dump
---@field jump_to? string Section header to jump cursor to
---@field bufnr? integer Buffer to collect status from (defaults to current)

---@class flemma.status.Data
---@field provider { name: string, model: string|nil, initialized: boolean, model_info: flemma.models.ModelInfo|nil }
---@field parameters { merged: table<string, any>, frontmatter_overrides: table<string, any>|nil, resolved_max_tokens: integer|nil }
---@field autopilot { enabled: boolean, config_enabled: boolean, buffer_state: string, max_turns: integer, frontmatter_override: boolean|nil }
---@field sandbox { enabled: boolean, config_enabled: boolean, runtime_override: boolean|nil, backend: string|nil, backend_mode: string|nil, backend_available: boolean, backend_error: string|nil, policy: flemma.config.SandboxPolicy }
---@field tools { enabled: string[], disabled: string[], booting: boolean, frontmatter_items: table<string, true>|nil, max_concurrent: integer, max_concurrent_frontmatter: integer|nil }
---@field approval { source: string|nil, approved: string[], denied: string[], pending: string[], require_approval_disabled: boolean, frontmatter_items: table<string, true>|nil, sandbox_items: table<string, true>|nil }
---@field buffer { is_chat: boolean, bufnr: integer }

---Collect provider section data
---@param config flemma.Config
---@return { name: string, model: string|nil, initialized: boolean, model_info: flemma.models.ModelInfo|nil }
local function collect_provider(config)
  local provider_instance = state.get_provider()
  local model_info = config.model and registry.get_model_info(config.provider, config.model) or nil
  return {
    name = config.provider,
    model = config.model,
    initialized = provider_instance ~= nil,
    model_info = model_info,
  }
end

---Collect parameters section data, including frontmatter overrides if present
---@param config flemma.Config
---@param opts flemma.opt.FrontmatterOpts|nil
---@return { merged: table<string, any>, frontmatter_overrides: table<string, any>|nil, resolved_max_tokens: integer|nil }
local function collect_parameters(config, opts)
  -- Flatten parameters from the materialized config. This reads from the
  -- facade-resolved state, which includes all layers (DEFAULTS + SETUP + RUNTIME).
  local base_merged = config_manager.flatten_provider_params(config.provider, config)

  -- Resolve max_tokens on a copy to show the resolved integer alongside the original
  local resolved_max_tokens = nil
  if type(base_merged.max_tokens) == "string" then
    local resolve_copy = { max_tokens = base_merged.max_tokens }
    config_manager.resolve_max_tokens(config.provider, config.model or "", resolve_copy)
    resolved_max_tokens = resolve_copy.max_tokens
  end

  -- If we have frontmatter opts with parameter overrides, compute the diff
  -- by overlaying frontmatter values on top of base_merged (not the global config)
  -- so switch overrides don't produce spurious diffs.
  local frontmatter_overrides = nil
  if opts then
    local merged_with_frontmatter = {}
    for k, v in pairs(base_merged) do
      merged_with_frontmatter[k] = v
    end

    -- Apply general frontmatter parameter overrides
    if opts.parameters then
      for k, v in pairs(opts.parameters) do
        merged_with_frontmatter[k] = v
      end
    end

    -- Apply provider-specific frontmatter overrides
    local provider_overrides = opts[config.provider]
    if type(provider_overrides) == "table" then
      for k, v in pairs(provider_overrides) do
        merged_with_frontmatter[k] = v
      end
    end

    -- Diff the two to find overridden keys
    local overrides = {}
    for key, value in pairs(merged_with_frontmatter) do
      if base_merged[key] == nil or base_merged[key] ~= value then
        overrides[key] = value
      end
    end
    if next(overrides) then
      frontmatter_overrides = overrides
    end
  end

  return {
    merged = base_merged,
    frontmatter_overrides = frontmatter_overrides,
    resolved_max_tokens = resolved_max_tokens,
  }
end

---Collect autopilot section data
---@param bufnr integer
---@param config flemma.Config
---@param opts flemma.opt.FrontmatterOpts|nil
---@return { enabled: boolean, config_enabled: boolean, buffer_state: string, max_turns: integer, frontmatter_override: boolean|nil }
local function collect_autopilot(bufnr, config, opts)
  local autopilot_config = config.tools and config.tools.autopilot
  local max_turns = (autopilot_config and autopilot_config.max_turns) or 100

  -- Base config value (ignoring frontmatter): mirrors autopilot.is_enabled() without the opts check
  local config_enabled = autopilot_config and (autopilot_config.enabled == nil or autopilot_config.enabled == true)
    or false

  local frontmatter_override = nil
  if opts and opts.autopilot ~= nil then
    frontmatter_override = opts.autopilot
  end

  return {
    enabled = autopilot.is_enabled(bufnr),
    config_enabled = config_enabled,
    buffer_state = autopilot.get_state(bufnr),
    max_turns = max_turns,
    frontmatter_override = frontmatter_override,
  }
end

---Collect sandbox section data
---@param bufnr integer
---@param opts flemma.opt.FrontmatterOpts|nil
---@return { enabled: boolean, config_enabled: boolean, runtime_override: boolean|nil, backend: string|nil, backend_mode: string|nil, backend_available: boolean, backend_error: string|nil, policy: flemma.config.SandboxPolicy }
local function collect_sandbox(bufnr, opts)
  local sandbox_config = sandbox.resolve_config(opts)
  local runtime_override = sandbox.get_override()

  local backend_name, backend_error = sandbox.detect_available_backend(opts)
  local backend_available, validate_error = sandbox.validate_backend(opts)

  local policy = sandbox.get_policy(bufnr, opts)

  return {
    enabled = sandbox.is_enabled(opts),
    config_enabled = sandbox_config.enabled == true,
    runtime_override = runtime_override,
    backend = backend_name,
    backend_mode = sandbox_config.backend,
    backend_available = backend_available,
    backend_error = backend_error or validate_error,
    policy = policy,
  }
end

---Collect tools section data, respecting per-buffer frontmatter overrides.
---When frontmatter changes the tool list, items that differ from config are tracked
---in frontmatter_items so the formatter can annotate them.
---@param config flemma.Config
---@param opts flemma.opt.FrontmatterOpts|nil
---@return { enabled: string[], disabled: string[], frontmatter_items: table<string, true>|nil, max_concurrent: integer, max_concurrent_frontmatter: integer|nil }
local function collect_tools(config, opts)
  local all_tools = tools_registry.get_all({ include_disabled = true })

  -- Config-only baseline: which tools are enabled by default?
  local config_enabled_set = {}
  for name, definition in pairs(all_tools) do
    if definition.enabled ~= false then
      config_enabled_set[name] = true
    end
  end

  local enabled = {}
  local disabled = {}
  local frontmatter_items = {}

  if opts and opts.tools then
    local enabled_set = {}
    for _, name in ipairs(opts.tools) do
      enabled_set[name] = true
    end
    for name, _ in pairs(all_tools) do
      if enabled_set[name] then
        table.insert(enabled, name)
        if not config_enabled_set[name] then
          frontmatter_items[name] = true
        end
      else
        table.insert(disabled, name)
        if config_enabled_set[name] then
          frontmatter_items[name] = true
        end
      end
    end
  else
    for name, definition in pairs(all_tools) do
      if definition.enabled ~= false then
        table.insert(enabled, name)
      else
        table.insert(disabled, name)
      end
    end
  end

  table.sort(enabled)
  table.sort(disabled)

  -- max_concurrent: check frontmatter override, fall back to config
  local config_max_concurrent = (config.tools and config.tools.max_concurrent) or 2
  local max_concurrent_frontmatter = nil
  if opts and opts.max_concurrent ~= nil then
    max_concurrent_frontmatter = opts.max_concurrent
  end

  return {
    enabled = enabled,
    disabled = disabled,
    booting = not tools_module.is_ready(),
    frontmatter_items = next(frontmatter_items) and frontmatter_items or nil,
    max_concurrent = config_max_concurrent,
    max_concurrent_frontmatter = max_concurrent_frontmatter,
  }
end

---Map an ApprovalResult to the bucket key used by collect_approval.
local RESULT_TO_BUCKET = {
  approve = "approved",
  deny = "denied",
  require_approval = "pending",
}

---Resolve approval for a tool via the resolver chain, returning the bucket and source.
---@param tool_name string
---@param opts flemma.opt.FrontmatterOpts|nil
---@param bufnr integer
---@return "approved"|"denied"|"pending" bucket
---@return string source Resolver name that made the decision
local function resolve_tool_approval(tool_name, opts, bufnr)
  local result, source = tools_approval.resolve_with_source(tool_name, {}, { bufnr = bufnr, tool_id = "", opts = opts })
  return RESULT_TO_BUCKET[result] or "pending", source
end

---Collect tool approval section data by running each tool through the approval
---resolver chain — the same code path used at tool-execution time.
---When frontmatter changes a tool's approval status, it is tracked in frontmatter_items.
---@param config flemma.Config
---@param opts flemma.opt.FrontmatterOpts|nil
---@param enabled_tools string[] Sorted list of enabled tool names
---@param bufnr integer Buffer number for resolver context
---@return { source: string|nil, approved: string[], denied: string[], pending: string[], require_approval_disabled: boolean, frontmatter_items: table<string, true>|nil, sandbox_items: table<string, true>|nil }
local function collect_approval(config, opts, enabled_tools, bufnr)
  local tools_config = config.tools
  local require_approval_disabled = tools_config and tools_config.require_approval == false or false

  -- Build source string from the effective auto_approve policy
  local effective_policy = tools_config and tools_config.auto_approve
  if opts and opts.auto_approve ~= nil then
    effective_policy = opts.auto_approve
  end
  ---@type string|nil
  local source = nil
  if type(effective_policy) == "table" then
    source = table.concat(effective_policy --[[@as string[] ]], ", ")
    if source == "" then
      source = nil
    end
  elseif type(effective_policy) == "function" then
    source = "(function)"
  end

  -- Classify each tool through the resolver chain
  local approved = {}
  local denied = {}
  local pending = {}
  local frontmatter_items = {}
  local sandbox_items = {}
  local has_frontmatter = opts and opts.auto_approve ~= nil

  for _, name in ipairs(enabled_tools) do
    local bucket, resolver_source = resolve_tool_approval(name, opts, bufnr)
    if bucket == "denied" then
      table.insert(denied, name)
    elseif bucket == "approved" then
      table.insert(approved, name)
    else
      table.insert(pending, name)
    end

    -- Track sandbox-sourced approvals
    if resolver_source == "urn:flemma:approval:sandbox" then
      sandbox_items[name] = true
    end

    -- Track frontmatter diffs by re-resolving without opts
    if has_frontmatter then
      local config_bucket = resolve_tool_approval(name, nil, bufnr)
      if bucket ~= config_bucket then
        frontmatter_items[name] = true
      end
    end
  end

  return {
    source = source,
    approved = approved,
    denied = denied,
    pending = pending,
    require_approval_disabled = require_approval_disabled,
    frontmatter_items = next(frontmatter_items) and frontmatter_items or nil,
    sandbox_items = next(sandbox_items) and sandbox_items or nil,
  }
end

---Format a list of names, appending markers for frontmatter/sandbox items.
---@param names string[]
---@param frontmatter_items table<string, true>|nil
---@param sandbox_items table<string, true>|nil
---@return string
local function format_name_list(names, frontmatter_items, sandbox_items)
  if not frontmatter_items and not sandbox_items then
    return table.concat(names, ", ")
  end
  local parts = {}
  for _, name in ipairs(names) do
    local suffix = ""
    if frontmatter_items and frontmatter_items[name] then
      suffix = suffix .. " " .. MARKER_FRONTMATTER
    end
    if sandbox_items and sandbox_items[name] then
      suffix = suffix .. " " .. MARKER_SANDBOX
    end
    table.insert(parts, name .. suffix)
  end
  return table.concat(parts, ", ")
end

---Format a scalar or table value as a display string
---@param value any
---@return string
local function format_value(value)
  if type(value) == "table" then
    return vim.inspect(value, { newline = " ", indent = "" })
  end
  return tostring(value)
end

---Format status data into display lines for a scratch buffer
---@param data flemma.status.Data
---@param verbose boolean Whether to include the full config dump
---@return string[]
function M.format(data, verbose)
  local lines = {}

  ---Append a line to the output
  ---@param line string
  local function add(line)
    table.insert(lines, line)
  end

  -- Title
  add("Flemma Status")
  add(string.rep("═", 40))
  add("")

  -- Provider section
  add("Provider")
  add("  name: " .. data.provider.name)
  add("  model: " .. (data.provider.model or "(none)"))
  add("  initialized: " .. tostring(data.provider.initialized))
  local model_info = data.provider.model_info
  if model_info then
    if model_info.max_input_tokens or model_info.max_output_tokens then
      local parts = {}
      if model_info.max_input_tokens then
        table.insert(parts, str.format_tokens(model_info.max_input_tokens) .. " input")
      end
      if model_info.max_output_tokens then
        table.insert(parts, str.format_tokens(model_info.max_output_tokens) .. " output")
      end
      add("  context: " .. table.concat(parts, ", "))
    end
    local pricing = model_info.pricing
    local price_line = string.format("$%.2f/$%.2f", pricing.input, pricing.output)
    if pricing.cache_read or pricing.cache_write then
      local cache_parts = {}
      if pricing.cache_read then
        table.insert(cache_parts, string.format("$%.2f read", pricing.cache_read))
      end
      if pricing.cache_write then
        table.insert(cache_parts, string.format("$%.2f write", pricing.cache_write))
      end
      price_line = price_line .. " (cache: " .. table.concat(cache_parts, ", ") .. ")"
    end
    add("  pricing: " .. price_line)
    if model_info.thinking_budgets then
      local min = model_info.min_thinking_budget
      local max = model_info.max_thinking_budget
      if min and max then
        add("  thinking: " .. tostring(min) .. "–" .. tostring(max) .. " budget range")
      end
    elseif model_info.supports_reasoning_effort then
      add("  thinking: reasoning_effort (provider-managed)")
    end
  end
  add("")

  -- Parameters (merged) section
  add("Parameters (merged)")
  local sorted_keys = {}
  for key, _ in pairs(data.parameters.merged) do
    table.insert(sorted_keys, key)
  end
  table.sort(sorted_keys)
  for _, key in ipairs(sorted_keys) do
    local value = data.parameters.merged[key]
    local resolved_suffix = ""
    if key == "max_tokens" and data.parameters.resolved_max_tokens then
      resolved_suffix = " → " .. tostring(data.parameters.resolved_max_tokens)
    end
    if data.parameters.frontmatter_overrides and data.parameters.frontmatter_overrides[key] ~= nil then
      add(
        "  "
          .. key
          .. ": ~~"
          .. format_value(value)
          .. resolved_suffix
          .. "~~ "
          .. format_value(data.parameters.frontmatter_overrides[key])
          .. " "
          .. MARKER_FRONTMATTER
      )
    else
      add("  " .. key .. ": " .. format_value(value) .. resolved_suffix)
    end
  end
  add("")

  -- Autopilot section
  add("Autopilot")
  local autopilot_status = data.autopilot.enabled and "enabled" or "disabled"
  if data.autopilot.frontmatter_override ~= nil then
    local config_status = data.autopilot.config_enabled and "enabled" or "disabled"
    add(
      "  status: ~~"
        .. config_status
        .. "~~ "
        .. autopilot_status
        .. " ("
        .. data.autopilot.buffer_state
        .. ") "
        .. MARKER_FRONTMATTER
    )
  else
    add("  status: " .. autopilot_status .. " (" .. data.autopilot.buffer_state .. ")")
  end
  add("  max_turns: " .. tostring(data.autopilot.max_turns))
  add("")

  -- Sandbox section
  add("Sandbox")
  add("  status: " .. (data.sandbox.enabled and "enabled" or "disabled"))
  add("  config setting: " .. (data.sandbox.config_enabled and "enabled" or "disabled"))
  if data.sandbox.runtime_override ~= nil then
    add("  runtime override: " .. tostring(data.sandbox.runtime_override))
  end
  add(
    "  backend: "
      .. (data.sandbox.backend or "(none)")
      .. (data.sandbox.backend_mode and (" (" .. data.sandbox.backend_mode .. ")") or "")
  )
  add("    available: " .. tostring(data.sandbox.backend_available))
  if data.sandbox.backend_error then
    add("    error: " .. data.sandbox.backend_error)
  end
  add("  network: " .. (data.sandbox.policy.network == false and "blocked" or "allowed"))
  add("  privileged: " .. (data.sandbox.policy.allow_privileged == true and "allowed" or "dropped"))
  local rw_paths = data.sandbox.policy.rw_paths or {}
  if #rw_paths > 0 then
    add("  rw_paths (" .. #rw_paths .. "):")
    for _, path in ipairs(rw_paths) do
      add("    " .. path)
    end
  else
    add("  rw_paths: (none)")
  end
  add("")

  -- Tools section
  local enabled_count = #data.tools.enabled
  local disabled_count = #data.tools.disabled
  add("Tools (" .. enabled_count .. " enabled, " .. disabled_count .. " disabled)")
  if data.tools.booting then
    add("  ⏳ loading async tool sources…")
  end
  if data.tools.max_concurrent_frontmatter ~= nil then
    add(
      "  max_concurrent: ~~"
        .. tostring(data.tools.max_concurrent)
        .. "~~ "
        .. tostring(data.tools.max_concurrent_frontmatter)
        .. " "
        .. MARKER_FRONTMATTER
    )
  else
    local mc_label = data.tools.max_concurrent == 0 and "unlimited" or tostring(data.tools.max_concurrent)
    add("  max_concurrent: " .. mc_label)
  end
  if enabled_count > 0 then
    add("  ✓ " .. format_name_list(data.tools.enabled, data.tools.frontmatter_items))
  end
  if disabled_count > 0 then
    add("  ✗ " .. format_name_list(data.tools.disabled, data.tools.frontmatter_items))
  end
  add("")

  -- Approval section
  if data.approval.source then
    add("Approval (" .. data.approval.source .. ")")
  else
    add("Approval")
  end
  if data.approval.require_approval_disabled then
    add("  ✓ all tools auto-approved (require_approval = false)")
  else
    local sandbox_items = data.approval.sandbox_items
    if #data.approval.approved > 0 then
      add(
        "  ✓ auto-approve: "
          .. format_name_list(data.approval.approved, data.approval.frontmatter_items, sandbox_items)
      )
    end
    if #data.approval.denied > 0 then
      add("  ✗ deny: " .. format_name_list(data.approval.denied, data.approval.frontmatter_items, sandbox_items))
    end
    if #data.approval.pending > 0 then
      add(
        "  ⋯ require approval: "
          .. format_name_list(data.approval.pending, data.approval.frontmatter_items, sandbox_items)
      )
    end
  end

  -- Legend (only if annotation markers were used)
  local has_frontmatter_marker = data.parameters.frontmatter_overrides
    or data.autopilot.frontmatter_override ~= nil
    or data.tools.frontmatter_items
    or data.tools.max_concurrent_frontmatter ~= nil
    or data.approval.frontmatter_items
  local has_sandbox_marker = data.approval.sandbox_items ~= nil
  if has_frontmatter_marker or has_sandbox_marker then
    add("")
    if has_frontmatter_marker then
      add(MARKER_FRONTMATTER .. " set by buffer frontmatter")
    end
    if has_sandbox_marker then
      add(MARKER_SANDBOX .. " auto-approved via sandbox")
    end
  end

  -- Verbose: model info dump and full config dump
  if verbose then
    if model_info then
      add("")
      add("Model Info")
      add(string.rep("─", 40))
      add("")
      local info_text = vim.inspect(model_info)
      for line in info_text:gmatch("[^\n]+") do
        add(line)
      end
    end

    add("")
    add("Config (full)")
    add(string.rep("─", 40))
    add("")
    local config_text = vim.inspect(state.get_config())
    for line in config_text:gmatch("[^\n]+") do
      add(line)
    end
  end

  return lines
end

---Collect all runtime status data for a buffer
---@param bufnr integer Buffer number (0 for current)
---@return flemma.status.Data
function M.collect(bufnr)
  local config = state.get_config()

  -- Resolve per-buffer frontmatter opts only for chat buffers
  local is_chat = vim.api.nvim_buf_is_valid(bufnr) and bufnr > 0 and vim.bo[bufnr].filetype == "chat"
  local opts = nil
  if is_chat then
    local ok, processor = pcall(require, "flemma.processor")
    if ok then
      local fm_result = processor.evaluate_buffer_frontmatter(bufnr)
      opts = fm_result.context:get_opts()
    end
  end

  local tools_data = collect_tools(config, opts)

  return {
    provider = collect_provider(config),
    parameters = collect_parameters(config, opts),
    autopilot = collect_autopilot(bufnr, config, opts),
    sandbox = collect_sandbox(bufnr, opts),
    tools = tools_data,
    approval = collect_approval(config, opts, tools_data.enabled, bufnr),
    buffer = {
      is_chat = is_chat,
      bufnr = bufnr,
    },
  }
end

---Open a vertical-split scratch buffer with formatted status output
---@param opts flemma.status.ShowOptions
function M.show(opts)
  local target_bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  local data = M.collect(target_bufnr)
  local lines = M.format(data, opts.verbose or false)

  -- Check if a status buffer already exists in the current tabpage
  local existing_win = nil
  local existing_bufnr = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "flemma-status" then
      existing_win = win
      existing_bufnr = bufnr
      break
    end
  end

  local bufnr
  if existing_win then
    vim.api.nvim_set_current_win(existing_win)
    bufnr = existing_bufnr --[[@as integer]]
  else
    vim.cmd("vnew")
    bufnr = vim.api.nvim_get_current_buf()
  end

  -- Set buffer options
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false

  -- Write content
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "flemma-status"

  -- Enable conceal for strikethrough on overridden values
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].conceallevel = 2

  -- Map q to close
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, nowait = true })

  -- Jump to section if requested
  if opts.jump_to then
    local current_win = vim.api.nvim_get_current_win()
    for index, line in ipairs(lines) do
      if line:find(opts.jump_to, 1, true) == 1 then
        vim.api.nvim_win_set_cursor(current_win, { index, 0 })
        break
      end
    end
  end
end

return M
