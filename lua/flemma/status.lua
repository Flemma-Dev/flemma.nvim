--- Collects runtime status data from all Flemma subsystems
--- Used by :Flemma status to display current configuration and state
---@class flemma.Status
local M = {}

local state = require("flemma.state")
local config_manager = require("flemma.core.config.manager")
local autopilot = require("flemma.autopilot")
local sandbox = require("flemma.sandbox")
local tools_registry = require("flemma.tools.registry")
local tool_presets = require("flemma.tools.presets")

local MARKER_FRONTMATTER = "✲"

---@class flemma.status.ShowOptions
---@field verbose? boolean Include full config dump
---@field jump_to? string Section header to jump cursor to
---@field source_bufnr? integer Buffer to collect status from (defaults to current)

---@class flemma.status.Data
---@field provider { name: string, model: string|nil, initialized: boolean }
---@field parameters { merged: table<string, any>, frontmatter_overrides: table<string, any>|nil }
---@field autopilot { enabled: boolean, config_enabled: boolean, buffer_state: string, max_turns: integer, frontmatter_override: boolean|nil }
---@field sandbox { enabled: boolean, config_enabled: boolean, runtime_override: boolean|nil, backend: string|nil, backend_mode: string|nil, backend_available: boolean, backend_error: string|nil }
---@field tools { enabled: string[], disabled: string[], frontmatter_items: table<string, true>|nil }
---@field approval { source: string|nil, approved: string[], denied: string[], pending: string[], require_approval_disabled: boolean, frontmatter_items: table<string, true>|nil }
---@field buffer { is_chat: boolean, bufnr: integer }

---Collect provider section data
---@param config flemma.Config
---@return { name: string, model: string|nil, initialized: boolean }
local function collect_provider(config)
  local provider_instance = state.get_provider()
  return {
    name = config.provider,
    model = config.model,
    initialized = provider_instance ~= nil,
  }
end

---Collect parameters section data, including frontmatter overrides if present
---@param config flemma.Config
---@param opts flemma.opt.FrontmatterOpts|nil
---@return { merged: table<string, any>, frontmatter_overrides: table<string, any>|nil }
local function collect_parameters(config, opts)
  local base_merged = config_manager.merge_parameters(config.parameters or {}, config.provider)

  -- If we have frontmatter opts with parameter overrides, compute the diff
  local frontmatter_overrides = nil
  if opts then
    -- Build provider overrides from opts (same logic the pipeline uses)
    local provider_overrides = opts[config.provider]
    local effective_params = config.parameters or {}

    -- If frontmatter has general parameters, merge them into the base
    if opts.parameters then
      effective_params = vim.tbl_deep_extend("force", effective_params, opts.parameters)
    end

    local merged_with_frontmatter =
      config_manager.merge_parameters(effective_params, config.provider, provider_overrides)

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
---@param opts flemma.opt.FrontmatterOpts|nil
---@return { enabled: boolean, config_enabled: boolean, runtime_override: boolean|nil, backend: string|nil, backend_mode: string|nil, backend_available: boolean, backend_error: string|nil }
local function collect_sandbox(opts)
  local sandbox_config = sandbox.resolve_config(opts)
  local runtime_override = sandbox.get_override()

  local backend_name, backend_error = sandbox.detect_available_backend(opts)
  local backend_available, validate_error = sandbox.validate_backend(opts)

  return {
    enabled = sandbox.is_enabled(opts),
    config_enabled = sandbox_config.enabled == true,
    runtime_override = runtime_override,
    backend = backend_name,
    backend_mode = sandbox_config.backend,
    backend_available = backend_available,
    backend_error = backend_error or validate_error,
  }
end

---Collect tools section data, respecting per-buffer frontmatter overrides.
---When frontmatter changes the tool list, items that differ from config are tracked
---in frontmatter_items so the formatter can annotate them.
---@param opts flemma.opt.FrontmatterOpts|nil
---@return { enabled: string[], disabled: string[], frontmatter_items: table<string, true>|nil }
local function collect_tools(opts)
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

  return {
    enabled = enabled,
    disabled = disabled,
    frontmatter_items = next(frontmatter_items) and frontmatter_items or nil,
  }
end

---Expand an auto_approve policy (table form) into approve/deny sets.
---@param policy string[]|nil The auto_approve value
---@param exclusions table<string, true>|nil Exclusion set from ListOption :remove()
---@return table<string, true> approved_set
---@return table<string, true> denied_set
local function expand_approval_policy(policy, exclusions)
  local approved_set = {}
  local denied_set = {}

  if type(policy) ~= "table" then
    return approved_set, denied_set
  end

  for _, entry in
    ipairs(policy --[[@as string[] ]])
  do
    if vim.startswith(entry, "$") then
      local preset = tool_presets.get(entry)
      if preset then
        if preset.approve then
          for _, name in ipairs(preset.approve) do
            approved_set[name] = true
          end
        end
        if preset.deny then
          for _, name in ipairs(preset.deny) do
            denied_set[name] = true
          end
        end
      end
    else
      approved_set[entry] = true
    end
  end

  if exclusions then
    for name in pairs(exclusions) do
      approved_set[name] = nil
    end
  end

  for name in pairs(denied_set) do
    approved_set[name] = nil
  end

  return approved_set, denied_set
end

---Classify a tool name against approve/deny sets.
---@param name string
---@param approved_set table<string, true>
---@param denied_set table<string, true>
---@return "approved"|"denied"|"pending"
local function classify_tool(name, approved_set, denied_set)
  if denied_set[name] then
    return "denied"
  elseif approved_set[name] then
    return "approved"
  end
  return "pending"
end

---Collect tool approval section data by expanding presets and classifying each enabled tool.
---When frontmatter changes a tool's approval status, it is tracked in frontmatter_items.
---@param config flemma.Config
---@param opts flemma.opt.FrontmatterOpts|nil
---@param enabled_tools string[] Sorted list of enabled tool names
---@return { source: string|nil, approved: string[], denied: string[], pending: string[], require_approval_disabled: boolean, frontmatter_items: table<string, true>|nil }
local function collect_approval(config, opts, enabled_tools)
  local tools_config = config.tools
  local require_approval_disabled = tools_config and tools_config.require_approval == false or false

  -- Determine effective policy (frontmatter overrides config)
  local effective_policy = tools_config and tools_config.auto_approve
  local has_frontmatter = opts and opts.auto_approve ~= nil
  if has_frontmatter then
    effective_policy = opts --[[@as flemma.opt.FrontmatterOpts]].auto_approve
  end

  -- Build source string from the raw policy entries (before expansion)
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

  -- Function policies can't be statically expanded
  if type(effective_policy) == "function" or type(tools_config and tools_config.auto_approve) == "function" then
    return {
      source = source,
      approved = {},
      denied = {},
      pending = enabled_tools,
      require_approval_disabled = require_approval_disabled,
    }
  end

  -- Expand effective policy (with frontmatter exclusions)
  local exclusions = opts and opts.auto_approve_exclusions
  local approved_set, denied_set = expand_approval_policy(effective_policy --[[@as string[]|nil]], exclusions)

  -- Expand config-only baseline for diffing (no exclusions — those come from frontmatter)
  local config_policy = tools_config and tools_config.auto_approve
  local config_approved_set, config_denied_set = expand_approval_policy(config_policy --[[@as string[]|nil]], nil)

  -- Classify each enabled tool and track frontmatter diffs
  local approved = {}
  local denied = {}
  local pending = {}
  local frontmatter_items = {}

  for _, name in ipairs(enabled_tools) do
    local effective_class = classify_tool(name, approved_set, denied_set)
    if effective_class == "denied" then
      table.insert(denied, name)
    elseif effective_class == "approved" then
      table.insert(approved, name)
    else
      table.insert(pending, name)
    end

    if has_frontmatter then
      local config_class = classify_tool(name, config_approved_set, config_denied_set)
      if effective_class ~= config_class then
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
  }
end

---Format a list of names, appending the frontmatter emoji to items in the given set.
---@param names string[]
---@param frontmatter_items table<string, true>|nil
---@return string
local function format_name_list(names, frontmatter_items)
  if not frontmatter_items then
    return table.concat(names, ", ")
  end
  local parts = {}
  for _, name in ipairs(names) do
    if frontmatter_items[name] then
      table.insert(parts, name .. " " .. MARKER_FRONTMATTER)
    else
      table.insert(parts, name)
    end
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
    if data.parameters.frontmatter_overrides and data.parameters.frontmatter_overrides[key] ~= nil then
      add(
        "  "
          .. key
          .. ": ~~"
          .. format_value(value)
          .. "~~ "
          .. format_value(data.parameters.frontmatter_overrides[key])
          .. "  "
          .. MARKER_FRONTMATTER
      )
    else
      add("  " .. key .. ": " .. format_value(value))
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
        .. ")  "
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
  add("  backend available: " .. tostring(data.sandbox.backend_available))
  if data.sandbox.backend_error then
    add("  backend error: " .. data.sandbox.backend_error)
  end
  add("")

  -- Tools section
  local enabled_count = #data.tools.enabled
  local disabled_count = #data.tools.disabled
  add("Tools (" .. enabled_count .. " enabled, " .. disabled_count .. " disabled)")
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
    if #data.approval.approved > 0 then
      add("  ✓ auto-approve: " .. format_name_list(data.approval.approved, data.approval.frontmatter_items))
    end
    if #data.approval.denied > 0 then
      add("  ✗ deny: " .. format_name_list(data.approval.denied, data.approval.frontmatter_items))
    end
    if #data.approval.pending > 0 then
      add("  ⋯ require approval: " .. format_name_list(data.approval.pending, data.approval.frontmatter_items))
    end
  end

  -- Legend (only if frontmatter marker was used)
  local has_frontmatter_marker = data.parameters.frontmatter_overrides
    or data.autopilot.frontmatter_override ~= nil
    or data.tools.frontmatter_items
    or data.approval.frontmatter_items
  if has_frontmatter_marker then
    add("")
    add(MARKER_FRONTMATTER .. " = set by buffer frontmatter")
  end

  -- Verbose: full config dump
  if verbose then
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

  local tools_data = collect_tools(opts)

  return {
    provider = collect_provider(config),
    parameters = collect_parameters(config, opts),
    autopilot = collect_autopilot(bufnr, config, opts),
    sandbox = collect_sandbox(opts),
    tools = tools_data,
    approval = collect_approval(config, opts, tools_data.enabled),
    buffer = {
      is_chat = is_chat,
      bufnr = bufnr,
    },
  }
end

---Open a vertical-split scratch buffer with formatted status output
---@param opts flemma.status.ShowOptions
function M.show(opts)
  local source_bufnr = opts.source_bufnr or vim.api.nvim_get_current_buf()

  local data = M.collect(source_bufnr)
  local lines = M.format(data, opts.verbose or false)

  -- Check if a status buffer already exists in the current tabpage
  local existing_win = nil
  local existing_bufnr = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "flemma_status" then
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
  vim.bo[bufnr].filetype = "flemma_status"

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
