--- Collects runtime status data from all Flemma subsystems
--- Used by :Flemma status to display current configuration and state
---@class flemma.Status
local M = {}

local state = require("flemma.state")
local config_manager = require("flemma.core.config.manager")
local autopilot = require("flemma.autopilot")
local sandbox = require("flemma.sandbox")
local tools_registry = require("flemma.tools.registry")

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
      base_merged = merged_with_frontmatter
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

---Collect tools section data
---@return { enabled: string[], disabled: string[] }
local function collect_tools()
  local all_tools = tools_registry.get_all({ include_disabled = true })

  local enabled = {}
  local disabled = {}

  for name, definition in pairs(all_tools) do
    if definition.enabled ~= false then
      table.insert(enabled, name)
    else
      table.insert(disabled, name)
    end
  end

  table.sort(enabled)
  table.sort(disabled)

  return {
    enabled = enabled,
    disabled = disabled,
  }
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
    tools = collect_tools(),
    buffer = {
      is_chat = is_chat,
      bufnr = bufnr,
    },
  }
end

return M
