--- Collects runtime status data from all Flemma subsystems
--- Used by :Flemma status to display current configuration and state
---@class flemma.Status
local M = {}

local state = require("flemma.state")
local config_manager = require("flemma.core.config.manager")
local autopilot = require("flemma.autopilot")
local sandbox = require("flemma.sandbox")
local tools_registry = require("flemma.tools.registry")

---@class flemma.status.ShowOptions
---@field verbose? boolean Include full config dump
---@field jump_to? string Section header to jump cursor to
---@field source_bufnr? integer Buffer to collect status from (defaults to current)

---@class flemma.status.Data
---@field provider { name: string, model: string|nil, initialized: boolean }
---@field parameters { merged: table<string, any>, frontmatter_overrides: table<string, any>|nil }
---@field autopilot { enabled: boolean, buffer_state: string, max_turns: integer, frontmatter_override: boolean|nil }
---@field sandbox { enabled: boolean, config_enabled: boolean, runtime_override: boolean|nil, backend: string|nil, backend_mode: string|nil, backend_available: boolean, backend_error: string|nil }
---@field tools { enabled: string[], disabled: string[] }
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
---@param opts flemma.opt.ResolvedOpts|nil
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
---@param opts flemma.opt.ResolvedOpts|nil
---@return { enabled: boolean, buffer_state: string, max_turns: integer, frontmatter_override: boolean|nil }
local function collect_autopilot(bufnr, config, opts)
  local autopilot_config = config.tools and config.tools.autopilot
  local max_turns = (autopilot_config and autopilot_config.max_turns) or 100

  local frontmatter_override = nil
  if opts and opts.autopilot ~= nil then
    frontmatter_override = opts.autopilot
  end

  return {
    enabled = autopilot.is_enabled(bufnr),
    buffer_state = autopilot.get_state(bufnr),
    max_turns = max_turns,
    frontmatter_override = frontmatter_override,
  }
end

---Collect sandbox section data
---@param opts flemma.opt.ResolvedOpts|nil
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

---Collect tools section data, respecting per-buffer frontmatter overrides
---@param opts flemma.opt.ResolvedOpts|nil
---@return { enabled: string[], disabled: string[] }
local function collect_tools(opts)
  local all_tools = tools_registry.get_all({ include_disabled = true })

  local enabled = {}
  local disabled = {}

  if opts and opts.tools then
    -- Frontmatter overrides the tool list: opts.tools is the list of enabled names
    local enabled_set = {}
    for _, name in ipairs(opts.tools) do
      enabled_set[name] = true
    end
    for name, _ in pairs(all_tools) do
      if enabled_set[name] then
        table.insert(enabled, name)
      else
        table.insert(disabled, name)
      end
    end
  else
    -- No frontmatter override: use global registry state
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
  }
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
    add("  " .. key .. ": " .. format_value(value))
    if data.parameters.frontmatter_overrides and data.parameters.frontmatter_overrides[key] ~= nil then
      add("  ⚑ frontmatter override: " .. key .. " = " .. format_value(data.parameters.frontmatter_overrides[key]))
    end
  end
  add("")

  -- Autopilot section
  add("Autopilot")
  local autopilot_status = data.autopilot.enabled and "enabled" or "disabled"
  add("  status: " .. autopilot_status .. " (" .. data.autopilot.buffer_state .. ")")
  add("  max_turns: " .. tostring(data.autopilot.max_turns))
  if data.autopilot.frontmatter_override ~= nil then
    add("  ⚑ frontmatter override: autopilot = " .. tostring(data.autopilot.frontmatter_override))
  end
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
    add("  ✓ " .. table.concat(data.tools.enabled, ", "))
  end
  if disabled_count > 0 then
    add("  ✗ " .. table.concat(data.tools.disabled, ", "))
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
      opts = processor.resolve_buffer_opts(bufnr)
    end
  end

  return {
    provider = collect_provider(config),
    parameters = collect_parameters(config, opts),
    autopilot = collect_autopilot(bufnr, config, opts),
    sandbox = collect_sandbox(opts),
    tools = collect_tools(opts),
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
