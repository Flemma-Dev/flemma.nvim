--- Collects runtime status data from all Flemma subsystems
--- Used by :Flemma status to display current configuration and state
---@class flemma.Status
local M = {}

local config_facade = require("flemma.config")
local normalize = require("flemma.provider.normalize")
local autopilot = require("flemma.autopilot")
local sandbox = require("flemma.sandbox")
local str = require("flemma.utilities.string")
local tools_module = require("flemma.tools")
local tools_approval = require("flemma.tools.approval")
local registry = require("flemma.provider.registry")

local MARKER_FRONTMATTER = "✲"
local MARKER_SANDBOX = "⊡"

---@class flemma.status.ShowOptions
---@field verbose? boolean Include layer ops and resolved config tree
---@field jump_to? string Section header to jump cursor to
---@field bufnr? integer Buffer to collect status from (defaults to current)

---@class flemma.status.Data
---@field provider { name: string, model: string|nil, initialized: boolean, model_info: flemma.models.ModelInfo|nil, source: string|nil, model_source: string|nil }
---@field parameters { merged: table<string, any>, sources: table<string, string>, resolved_max_tokens: integer|nil }
---@field autopilot { enabled: boolean, config_enabled: boolean, buffer_state: string, max_turns: integer }
---@field sandbox { enabled: boolean, config_enabled: boolean, runtime_override: boolean|nil, backend: string|nil, backend_mode: string|nil, backend_available: boolean, backend_error: string|nil, policy: flemma.config.SandboxPolicy }
---@field tools { enabled: string[], disabled: string[], booting: boolean, frontmatter_items: table<string, true>|nil, max_concurrent: integer, source: string|nil }
---@field approval { source: string|nil, approved: string[], denied: string[], pending: string[], require_approval_disabled: boolean, frontmatter_items: table<string, true>|nil, sandbox_items: table<string, true>|nil }
---@field buffer { is_chat: boolean, bufnr: integer }
---@field introspection? { layer_ops: { label: string, name: string, ops: table[] }[], resolved: { path: string, value: any, source: string?, depth: integer, is_object: boolean }[] }

-- ---------------------------------------------------------------------------
-- Collectors
-- ---------------------------------------------------------------------------

---Collect provider section data
---@param config flemma.Config
---@param bufnr integer
---@return { name: string, model: string|nil, initialized: boolean, model_info: flemma.models.ModelInfo|nil, source: string|nil, model_source: string|nil }
local function collect_provider(config, bufnr)
  local model_info = config.model and registry.get_model_info(config.provider, config.model) or nil
  local provider_info = config_facade.inspect(bufnr, "provider")
  local model_info_src = config_facade.inspect(bufnr, "model")
  return {
    name = config.provider,
    model = config.model,
    initialized = config.provider ~= nil and config.provider ~= "",
    model_info = model_info,
    source = provider_info and provider_info.layer or nil,
    model_source = model_info_src and model_info_src.layer or nil,
  }
end

---Collect parameters section data with per-key source tracking.
---@param config flemma.Config
---@param bufnr integer
---@return { merged: table<string, any>, sources: table<string, string>, resolved_max_tokens: integer|nil }
local function collect_parameters(config, bufnr)
  local base_merged = normalize.flatten_parameters(config.provider, config)

  -- Build source map for each flattened parameter key.
  -- Provider-specific path takes precedence over general path (same as flatten).
  local sources = {}
  local provider_name = config.provider
  for key, _ in pairs(base_merged) do
    if key == "model" then
      local info = config_facade.inspect(bufnr, "model")
      if info and info.layer then
        sources[key] = info.layer
      end
    else
      -- Check provider-specific path first
      local specific = config_facade.inspect(bufnr, "parameters." .. provider_name .. "." .. key)
      if specific and specific.value ~= nil then
        sources[key] = specific.layer
      else
        local general = config_facade.inspect(bufnr, "parameters." .. key)
        if general and general.layer then
          sources[key] = general.layer
        end
      end
    end
  end

  -- Resolve max_tokens on a copy to show the resolved integer alongside the original
  local resolved_max_tokens = nil
  if type(base_merged.max_tokens) == "string" then
    local resolve_copy = { max_tokens = base_merged.max_tokens }
    normalize.resolve_max_tokens(config.provider, config.model or "", resolve_copy)
    resolved_max_tokens = resolve_copy.max_tokens
  end

  return {
    merged = base_merged,
    sources = sources,
    resolved_max_tokens = resolved_max_tokens,
  }
end

---Collect autopilot section data
---@param bufnr integer
---@param config flemma.Config
---@return { enabled: boolean, config_enabled: boolean, buffer_state: string, max_turns: integer }
local function collect_autopilot(bufnr, config)
  local autopilot_config = config.tools and config.tools.autopilot
  local max_turns = (autopilot_config and autopilot_config.max_turns) or 100

  -- Base config value (ignoring frontmatter): mirrors autopilot.is_enabled() without the opts check
  local config_enabled = autopilot_config and (autopilot_config.enabled == nil or autopilot_config.enabled == true)
    or false

  return {
    enabled = autopilot.is_enabled(bufnr),
    config_enabled = config_enabled,
    buffer_state = autopilot.get_state(bufnr),
    max_turns = max_turns,
  }
end

---Collect sandbox section data
---@param bufnr integer
---@return { enabled: boolean, config_enabled: boolean, runtime_override: boolean|nil, backend: string|nil, backend_mode: string|nil, backend_available: boolean, backend_error: string|nil, policy: flemma.config.SandboxPolicy }
local function collect_sandbox(bufnr)
  local sandbox_config = sandbox.resolve_config(bufnr)
  local runtime_override = sandbox.get_override()

  local backend_name, backend_error = sandbox.detect_available_backend(bufnr)
  local backend_available, validate_error = sandbox.validate_backend(bufnr)

  local policy = sandbox.get_policy(bufnr)

  return {
    enabled = sandbox.is_enabled(bufnr),
    config_enabled = sandbox_config.enabled == true,
    runtime_override = runtime_override,
    backend = backend_name,
    backend_mode = sandbox_config.backend,
    backend_available = backend_available,
    backend_error = backend_error or validate_error,
    policy = policy,
  }
end

---Collect tools section data, using the config store for source tracking.
---When frontmatter changes the tool list, items that differ from the base
---config are tracked in frontmatter_items for annotation.
---@param bufnr integer
---@return { enabled: string[], disabled: string[], booting: boolean, frontmatter_items: table<string, true>|nil, max_concurrent: integer, source: string|nil }
local function collect_tools(bufnr)
  local all_tools = tools_module.get_all({ include_disabled = true })

  -- Get the tools list source from the config store
  local tools_info = config_facade.inspect(bufnr, "tools")
  local tools_list = tools_info and tools_info.value
  local tools_source = tools_info and tools_info.layer
  local frontmatter_modified = tools_source and tools_source:find("F") ~= nil

  local enabled = {}
  local disabled = {}
  local frontmatter_items = {}

  if frontmatter_modified and type(tools_list) == "table" and #tools_list > 0 then
    -- Frontmatter modified the tools list — filter by it and detect diffs
    local allowed_set = {}
    for _, name in ipairs(tools_list) do
      allowed_set[name] = true
    end

    -- Get the base tool list (without frontmatter) for diff detection
    local base_info = config_facade.inspect(nil, "tools")
    local base_set = {}
    if base_info and type(base_info.value) == "table" then
      for _, name in ipairs(base_info.value) do
        base_set[name] = true
      end
    else
      for name, definition in pairs(all_tools) do
        if definition.enabled ~= false then
          base_set[name] = true
        end
      end
    end

    for name, _ in pairs(all_tools) do
      if allowed_set[name] then
        table.insert(enabled, name)
        if not base_set[name] then
          frontmatter_items[name] = true
        end
      else
        table.insert(disabled, name)
        if base_set[name] then
          frontmatter_items[name] = true
        end
      end
    end
  else
    -- No frontmatter modification — use registry enabled status
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

  local mc_info = config_facade.inspect(bufnr, "tools.max_concurrent")
  local max_concurrent = (mc_info and mc_info.value) or 2

  return {
    enabled = enabled,
    disabled = disabled,
    booting = not tools_module.is_ready(),
    frontmatter_items = next(frontmatter_items) and frontmatter_items or nil,
    max_concurrent = max_concurrent,
    source = tools_source,
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
---@param bufnr integer
---@return "approved"|"denied"|"pending" bucket
---@return string source Resolver name that made the decision
local function resolve_tool_approval(tool_name, bufnr)
  local result, source = tools_approval.resolve_with_source(tool_name, {}, { bufnr = bufnr, tool_id = "" })
  return RESULT_TO_BUCKET[result] or "pending", source
end

---Collect tool approval section data by running each tool through the approval
---resolver chain — the same code path used at tool-execution time.
---@param config flemma.Config Materialized config (from collect)
---@param bufnr integer Buffer number for resolver context
---@param enabled_tools string[] Sorted list of enabled tool names
---@return { source: string|nil, approved: string[], denied: string[], pending: string[], require_approval_disabled: boolean, frontmatter_items: table<string, true>|nil, sandbox_items: table<string, true>|nil }
local function collect_approval(config, bufnr, enabled_tools)
  local tools_config = config.tools
  local require_approval_disabled = tools_config and tools_config.require_approval == false or false

  -- Build source string from the effective auto_approve policy
  local effective_policy = tools_config and tools_config.auto_approve
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
  local sandbox_items = {}

  for _, name in ipairs(enabled_tools) do
    local bucket, resolver_source = resolve_tool_approval(name, bufnr)
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
  end

  -- Detect frontmatter-modified approval by checking if auto_approve source includes F
  local aa_info = config_facade.inspect(bufnr, "tools.auto_approve")
  local has_frontmatter = aa_info and aa_info.layer and aa_info.layer:find("F") ~= nil

  ---@type table<string, true>|nil
  local frontmatter_items = nil
  if has_frontmatter then
    -- Mark all non-sandbox approved tools as frontmatter-influenced
    -- (exact per-tool diff would require resolving without frontmatter layer)
    frontmatter_items = {}
    for _, name in ipairs(approved) do
      if not sandbox_items[name] then
        frontmatter_items[name] = true
      end
    end
    if not next(frontmatter_items) then
      frontmatter_items = nil
    end
  end

  return {
    source = source,
    approved = approved,
    denied = denied,
    pending = pending,
    require_approval_disabled = require_approval_disabled,
    frontmatter_items = frontmatter_items,
    sandbox_items = next(sandbox_items) and sandbox_items or nil,
  }
end

---Collect introspection data for the verbose view.
---Returns raw layer ops and the resolved config tree with source annotations.
---@param bufnr integer
---@return { layer_ops: { label: string, name: string, ops: table[] }[], resolved: { path: string, value: any, source: string?, depth: integer, is_object: boolean }[] }
local function collect_introspection(bufnr)
  local LAYERS = config_facade.LAYERS
  local layer_ops = {}

  ---@type { label: string, num: integer, name: string }[]
  local layer_info = {
    { label = "D", num = LAYERS.DEFAULTS, name = "defaults" },
    { label = "S", num = LAYERS.SETUP, name = "setup" },
    { label = "R", num = LAYERS.RUNTIME, name = "runtime" },
    { label = "F", num = LAYERS.FRONTMATTER, name = "frontmatter" },
  }

  for _, info in ipairs(layer_info) do
    local ops
    if info.num == LAYERS.FRONTMATTER then
      ops = config_facade.dump_layer(info.num, bufnr)
    else
      ops = config_facade.dump_layer(info.num)
    end
    table.insert(layer_ops, {
      label = info.label,
      name = info.name,
      ops = ops,
    })
  end

  local resolved = config_facade.dump_resolved(bufnr)

  return {
    layer_ops = layer_ops,
    resolved = resolved,
  }
end

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

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

---Format a scalar or table value as a compact display string
---@param value any
---@return string
local function format_value(value)
  if type(value) == "table" then
    return vim.inspect(value, { newline = " ", indent = "" })
  end
  return tostring(value)
end

---Right-pad a string to the given display width.
---Uses strdisplaywidth to handle multi-byte characters correctly.
---@param text string
---@param width integer
---@return string
local function pad(text, width)
  local display_width = vim.fn.strdisplaywidth(text)
  if display_width >= width then
    return text
  end
  return text .. string.rep(" ", width - display_width)
end

---Format a value line with an optional layer indicator right-aligned.
---@param label string Left-hand label (e.g., "  thinking:")
---@param value_str string Formatted value
---@param source string|nil Layer indicator (e.g., "D", "S+F")
---@return string
local function format_sourced_line(label, value_str, source)
  if not source then
    return label .. " " .. value_str
  end
  local content = label .. " " .. value_str
  return pad(content, 40) .. " " .. source
end

---Format status data into display lines for a scratch buffer
---@param data flemma.status.Data
---@param verbose boolean Whether to include layer ops and resolved config tree
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
  add(format_sourced_line("  name:", data.provider.name, data.provider.source))
  add(format_sourced_line("  model:", data.provider.model or "(none)", data.provider.model_source))
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
    local value_str = format_value(value)
    if key == "max_tokens" and data.parameters.resolved_max_tokens then
      value_str = value_str .. " → " .. tostring(data.parameters.resolved_max_tokens)
    end
    local source = data.parameters.sources and data.parameters.sources[key] or nil
    add(format_sourced_line("  " .. key .. ":", value_str, source))
  end
  add("")

  -- Autopilot section
  add("Autopilot")
  local autopilot_status = data.autopilot.enabled and "enabled" or "disabled"
  add("  status: " .. autopilot_status .. " (" .. data.autopilot.buffer_state .. ")")
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
  local tools_header = "Tools (" .. enabled_count .. " enabled, " .. disabled_count .. " disabled)"
  if data.tools.source then
    tools_header = pad(tools_header, 40) .. " " .. data.tools.source
  end
  add(tools_header)
  if data.tools.booting then
    add("  ⏳ loading async tool sources…")
  end
  local mc_label = data.tools.max_concurrent == 0 and "unlimited" or tostring(data.tools.max_concurrent)
  add("  max_concurrent: " .. mc_label)
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
  local has_frontmatter_marker = data.tools.frontmatter_items or data.approval.frontmatter_items
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

  -- Verbose: layer ops + resolved config tree
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

    local intro = data.introspection
    if intro then
      add("")
      add("Layer Ops")
      add(string.rep("─", 40))
      for _, layer in ipairs(intro.layer_ops) do
        local op_count = #layer.ops
        local suffix = ""
        if layer.label == "D" then
          suffix = " (schema materialized)"
        end
        add("[" .. layer.label .. "] " .. pad(layer.name, 15) .. "(" .. op_count .. " ops" .. suffix .. ")")
        -- Show non-default layer ops (skip defaults — too noisy)
        if layer.label ~= "D" then
          for _, op_entry in ipairs(layer.ops) do
            local value_display = format_value(op_entry.value)
            add("  " .. pad(op_entry.op, 8) .. " " .. pad(op_entry.path, 30) .. "-> " .. value_display)
          end
        end
      end

      add("")
      add("Resolved Config Tree")
      add(string.rep("─", 40))
      for _, entry in ipairs(intro.resolved) do
        local indent = string.rep("  ", entry.depth)
        if entry.is_object then
          local leaf = entry.path:match("[^.]+$") or entry.path
          add(indent .. leaf)
        else
          local leaf = entry.path:match("[^.]+$") or entry.path
          local value_display = format_value(entry.value)
          add(format_sourced_line(indent .. pad(leaf, 20 - entry.depth * 2), value_display, entry.source))
        end
      end
    else
      -- Fallback: plain config dump when introspection is not available
      add("")
      add("Config (full)")
      add(string.rep("─", 40))
      add("")
      local config_text = vim.inspect(config_facade.materialize(data.buffer.bufnr))
      for line in config_text:gmatch("[^\n]+") do
        add(line)
      end
    end
  end

  return lines
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---Collect all runtime status data for a buffer
---@param bufnr integer Buffer number (0 for current)
---@return flemma.status.Data
function M.collect(bufnr)
  -- Evaluate frontmatter for chat buffers FIRST — writes to config store's
  -- FRONTMATTER layer. This must happen before materialize() so the
  -- materialized config includes frontmatter overrides.
  local is_chat = vim.api.nvim_buf_is_valid(bufnr) and bufnr > 0 and vim.bo[bufnr].filetype == "chat"
  if is_chat then
    local ok, processor = pcall(require, "flemma.processor")
    if ok then
      processor.evaluate_buffer_frontmatter(bufnr)
    end
  end

  -- Materialize after frontmatter evaluation so all layers are included.
  -- materialize() is needed because flatten_parameters uses pairs().
  -- resolve_preset() expands $-prefixed model references to concrete values.
  local config = normalize.resolve_preset(config_facade.materialize(bufnr))

  local tools_data = collect_tools(bufnr)

  return {
    provider = collect_provider(config, bufnr),
    parameters = collect_parameters(config, bufnr),
    autopilot = collect_autopilot(bufnr, config),
    sandbox = collect_sandbox(bufnr),
    tools = tools_data,
    approval = collect_approval(config, bufnr, tools_data.enabled),
    buffer = {
      is_chat = is_chat,
      bufnr = bufnr,
    },
  }
end

---Collect all runtime status data for a buffer including introspection for verbose view.
---@param bufnr integer Buffer number (0 for current)
---@return flemma.status.Data
function M.collect_verbose(bufnr)
  local data = M.collect(bufnr)
  data.introspection = collect_introspection(bufnr)
  return data
end

---Open a vertical-split scratch buffer with formatted status output
---@param opts flemma.status.ShowOptions
function M.show(opts)
  local target_bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  -- When the current buffer is the status window itself (e.g. re-running
  -- :Flemma status while the cursor is already in the status split), retrieve
  -- the original chat buffer that was recorded when the window was opened.
  if vim.api.nvim_buf_is_valid(target_bufnr) and vim.bo[target_bufnr].filetype == "flemma-status" then
    local source = vim.b[target_bufnr].flemma_source_bufnr
    if source and vim.api.nvim_buf_is_valid(source) then
      target_bufnr = source
    end
  end

  local is_verbose = opts.verbose or false
  local data
  if is_verbose then
    data = M.collect_verbose(target_bufnr)
  else
    data = M.collect(target_bufnr)
  end
  local format_lines = M.format(data, is_verbose)

  -- Check if a status buffer already exists in the current tabpage
  local existing_win = nil
  local existing_bufnr = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "flemma-status" then
      existing_win = win
      existing_bufnr = buf
      break
    end
  end

  local buf
  if existing_win then
    vim.api.nvim_set_current_win(existing_win)
    buf = existing_bufnr --[[@as integer]]
  else
    vim.cmd("vnew")
    buf = vim.api.nvim_get_current_buf()
  end

  -- Set buffer options
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.b[buf].flemma_source_bufnr = target_bufnr

  -- Write content
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, format_lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "flemma-status"

  -- Enable conceal for strikethrough on overridden values
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].conceallevel = 2

  -- Map q to close
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })

  -- Jump to section if requested
  if opts.jump_to then
    local current_win = vim.api.nvim_get_current_win()
    for index, line in ipairs(format_lines) do
      if line:find(opts.jump_to, 1, true) == 1 then
        vim.api.nvim_win_set_cursor(current_win, { index, 0 })
        break
      end
    end
  end
end

return M
