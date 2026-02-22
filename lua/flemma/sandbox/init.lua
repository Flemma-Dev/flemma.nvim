--- Sandbox policy layer
--- Resolves config, expands path variables, normalizes paths, delegates to backend.
--- Tools consume this module's public API — never talk to backends directly.
---@class flemma.Sandbox
local M = {}

local state = require("flemma.state")

-- ---------------------------------------------------------------------------
-- Backend registry (mirrors tools/approval.lua pattern)
-- ---------------------------------------------------------------------------

--- Definition passed to register()
---@class flemma.sandbox.BackendDefinition
---@field available fun(backend_config: table): boolean, string|nil
---@field wrap fun(policy: flemma.config.SandboxPolicy, backend_config: table, inner_cmd: string[]): string[]|nil, string|nil
---@field priority? integer Higher values are preferred during auto-detection (default: 50)
---@field description? string Human-readable description

--- Internal registry entry (name added by register())
---@class flemma.sandbox.BackendEntry
---@field name string Unique backend name
---@field available fun(backend_config: table): boolean, string|nil
---@field wrap fun(policy: flemma.config.SandboxPolicy, backend_config: table, inner_cmd: string[]): string[]|nil, string|nil
---@field priority integer Higher values are preferred during auto-detection
---@field description? string Human-readable description

local DEFAULT_PRIORITY = 50

---@type flemma.sandbox.BackendEntry[]
local backends = {}

---@type boolean
local registry_sorted = true

---@type integer
local registry_generation = 0

--- Ensure the backend list is sorted by priority descending, name as tie-breaker.
local function ensure_sorted()
  if registry_sorted then
    return
  end
  table.sort(backends, function(a, b)
    if a.priority == b.priority then
      return a.name < b.name
    end
    return a.priority > b.priority
  end)
  registry_sorted = true
end

---Register a sandbox backend.
---If a backend with the same name already exists, it is replaced.
---@param name string Unique backend name
---@param definition flemma.sandbox.BackendDefinition
function M.register(name, definition)
  local loader = require("flemma.loader")
  if loader.is_module_path(name) then
    error(
      string.format("flemma: sandbox backend name '%s' must not contain dots (dots indicate module paths)", name),
      2
    )
  end
  for i, entry in ipairs(backends) do
    if entry.name == name then
      table.remove(backends, i)
      break
    end
  end

  table.insert(backends, {
    name = name,
    available = definition.available,
    wrap = definition.wrap,
    priority = definition.priority or DEFAULT_PRIORITY,
    description = definition.description,
  })
  registry_sorted = false
  registry_generation = registry_generation + 1
end

---Unregister a backend by name.
---@param name string
---@return boolean removed True if a backend was found and removed
function M.unregister(name)
  for i, entry in ipairs(backends) do
    if entry.name == name then
      table.remove(backends, i)
      registry_generation = registry_generation + 1
      return true
    end
  end
  return false
end

---Get a backend entry by name.
---@param name string
---@return flemma.sandbox.BackendEntry|nil
function M.get(name)
  for _, entry in ipairs(backends) do
    if entry.name == name then
      return entry
    end
  end
  return nil
end

---Get all registered backends, sorted by priority (highest first).
---@return flemma.sandbox.BackendEntry[]
function M.get_all()
  ensure_sorted()
  return vim.deepcopy(backends)
end

---Clear all registered backends.
function M.clear()
  backends = {}
  registry_sorted = true
  registry_generation = registry_generation + 1
end

---Get the count of registered backends.
---@return integer
function M.count()
  return #backends
end

---Register a sandbox backend from a module path.
---Validates existence immediately, loads and registers immediately.
---@param module_path string Lua module path (must contain a dot)
function M.register_module(module_path)
  local loader = require("flemma.loader")
  loader.assert_exists(module_path)
  local mod = loader.load(module_path)
  if type(mod.available) ~= "function" or type(mod.wrap) ~= "function" then
    error(
      string.format(
        "flemma: module '%s' must export 'available' and 'wrap' functions (expected sandbox backend)",
        module_path
      ),
      2
    )
  end
  -- Derive backend name from module metadata or last path segment
  local name = mod.name or module_path:match("([^.]+)$")
  M.register(name, mod)
end

-- ---------------------------------------------------------------------------
-- Cached auto-detection
-- ---------------------------------------------------------------------------

---@class flemma.sandbox.DetectionCache
---@field backend_name string|false string = detected name, false = none found
---@field diagnostic string|nil
---@field generation integer Registry generation at detection time
---@field backends_config table Backends config used for detection

---@type flemma.sandbox.DetectionCache|nil
local detection_cache = nil

--- Auto-detect the best available backend by priority.
--- Iterates all registered backends (highest priority first), calls available()
--- on each with its per-backend config, returns the first that succeeds.
---@param backends_config table<string, table>
---@return string|nil backend_name, string|nil diagnostic
local function detect_backend(backends_config)
  ensure_sorted()

  local tried = {}
  for _, entry in ipairs(backends) do
    local backend_config = backends_config[entry.name] or {}
    local ok, err = entry.available(backend_config)
    if ok then
      return entry.name, nil
    end
    table.insert(tried, string.format("%s: %s", entry.name, err or "unavailable"))
  end

  local diagnostic = "No sandbox backend available"
  if #tried > 0 then
    diagnostic = diagnostic .. " (" .. table.concat(tried, "; ") .. ")"
  end
  return nil, diagnostic
end

--- Whether a backend value triggers auto-detection ("auto" or "required").
---@param backend? string
---@return boolean
local function is_autodetect(backend)
  return backend == "auto" or backend == "required"
end

--- Resolve which backend to use from a sandbox config.
--- When backend is "auto" or "required", uses cached auto-detection.
--- When an explicit name, looks up by name directly.
---@param cfg flemma.config.SandboxConfig
---@return flemma.sandbox.BackendEntry|nil entry, string|nil error
local function resolve_backend(cfg)
  local backend_name = cfg.backend

  if not is_autodetect(backend_name) then
    -- Explicit backend — look up directly, trust the user
    if not backend_name then
      return nil, "No sandbox backend configured"
    end
    -- If it's a module path, load and register it first
    local loader = require("flemma.loader")
    if loader.is_module_path(backend_name) then
      local load_ok, load_err = pcall(M.register_module, backend_name)
      if not load_ok then
        return nil, tostring(load_err)
      end
      local mod = require(backend_name)
      backend_name = mod.name or backend_name:match("([^.]+)$")
    end
    local entry = M.get(backend_name)
    if not entry then
      return nil, "Unknown sandbox backend: " .. backend_name
    end
    return entry, nil
  end

  -- Auto-detect with cache
  local backends_config = cfg.backends or {}

  if
    detection_cache
    and detection_cache.generation == registry_generation
    and vim.deep_equal(detection_cache.backends_config, backends_config)
  then
    if detection_cache.backend_name == false then
      return nil, detection_cache.diagnostic
    end
    local entry = M.get(detection_cache.backend_name)
    if entry then
      return entry, nil
    end
    -- Cache hit but entry gone (shouldn't happen — generation would have changed)
  end

  -- Run detection
  local detected, diagnostic = detect_backend(backends_config)

  detection_cache = {
    backend_name = detected or false,
    diagnostic = diagnostic,
    generation = registry_generation,
    backends_config = vim.deepcopy(backends_config),
  }

  if not detected then
    return nil, diagnostic
  end

  return M.get(detected), nil
end

-- ---------------------------------------------------------------------------
-- Built-in backend registration
-- ---------------------------------------------------------------------------

---Register built-in sandbox backends.
---Called during plugin setup in init.lua.
function M.setup()
  local bwrap = require("flemma.sandbox.backends.bwrap")
  if not M.get("bwrap") then
    M.register("bwrap", {
      available = bwrap.available,
      wrap = bwrap.wrap,
      priority = 100,
      description = "Bubblewrap (Linux)",
    })
  end

  -- Validate module-path backend early (fail fast at startup)
  local loader = require("flemma.loader")
  local config = state.get_config()
  if config.sandbox and config.sandbox.backend and loader.is_module_path(config.sandbox.backend) then
    loader.assert_exists(config.sandbox.backend)
  end
end

-- ---------------------------------------------------------------------------
-- Runtime override
-- ---------------------------------------------------------------------------

--- Runtime override (session-level, set via :Flemma sandbox:enable/disable)
---@type boolean|nil nil = no override, defer to config
local runtime_override = nil

--- Known path variables and their resolvers.
--- Each resolver receives (bufnr) and returns an absolute path or nil.
---@type table<string, fun(bufnr: integer): string|nil>
local path_variables = {
  ["$CWD"] = function(_bufnr)
    return vim.fn.getcwd()
  end,
  ["$FLEMMA_BUFFER_PATH"] = function(bufnr)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname == "" then
      return nil
    end
    return vim.fn.fnamemodify(bufname, ":p:h")
  end,
}

--- Normalize a path to absolute, resolving symlinks
---@param path string
---@return string
local function normalize(path)
  return vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))
end

--- Expand path variables and normalize all paths in a policy.
--- Returns a new policy with only absolute, deduplicated rw_paths.
---@param policy flemma.config.SandboxPolicy
---@param bufnr integer
---@return flemma.config.SandboxPolicy resolved
local function resolve_policy(policy, bufnr)
  local resolved = vim.deepcopy(policy)
  local seen = {}
  local expanded = {}

  for _, path in ipairs(resolved.rw_paths or {}) do
    local abs
    local resolver = path_variables[path]
    if resolver then
      abs = resolver(bufnr)
      if not abs then
        -- Variable resolved to nil (e.g., unnamed buffer for $FLEMMA_BUFFER_PATH)
        goto continue
      end
      abs = normalize(abs)
    elseif path:match("^%$") then
      -- Unknown variable
      vim.schedule(function()
        vim.notify("Flemma sandbox: unknown path variable '" .. path .. "', skipping", vim.log.levels.WARN)
      end)
      goto continue
    else
      abs = normalize(path)
    end

    if not seen[abs] then
      seen[abs] = true
      table.insert(expanded, abs)
    end

    ::continue::
  end

  resolved.rw_paths = expanded
  return resolved
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Resolve the effective sandbox config (global + per-buffer overrides + runtime override)
---@param opts? flemma.opt.FrontmatterOpts
---@return flemma.config.SandboxConfig
function M.resolve_config(opts)
  local config = state.get_config()
  local base = vim.deepcopy(config.sandbox or {})

  if opts and opts.sandbox then
    base = vim.tbl_deep_extend("force", base, opts.sandbox)
  end

  -- Runtime override wins over everything
  if runtime_override ~= nil then
    base.enabled = runtime_override
  end

  return base
end

--- Is sandboxing currently enabled?
---@param opts? flemma.opt.FrontmatterOpts
---@return boolean
function M.is_enabled(opts)
  return M.resolve_config(opts).enabled == true
end

--- Get the resolved policy (with path variables expanded)
---@param bufnr integer
---@param opts? flemma.opt.FrontmatterOpts
---@return flemma.config.SandboxPolicy
function M.get_policy(bufnr, opts)
  local cfg = M.resolve_config(opts)
  return resolve_policy(cfg.policy or {}, bufnr)
end

--- Validate that a suitable backend is available.
--- When backend is "auto", tries to detect one. When explicit, checks that specific backend.
--- Returns true immediately when sandboxing is disabled.
---@param opts? flemma.opt.FrontmatterOpts
---@return boolean ok, string|nil error
function M.validate_backend(opts)
  local cfg = M.resolve_config(opts)
  if not cfg.enabled then
    return true, nil
  end

  local entry, resolve_err = resolve_backend(cfg)
  if not entry then
    return false, resolve_err
  end

  local backend_config = (cfg.backends or {})[entry.name] or {}
  return entry.available(backend_config)
end

--- Wrap a command array with sandbox enforcement.
--- Returns the original command unchanged if sandboxing is disabled.
--- In auto mode, gracefully degrades to unsandboxed when no backend is available
--- (a backend may be registered later, at which point wrapping activates).
---@param inner_cmd string[]
---@param bufnr integer
---@param opts? flemma.opt.FrontmatterOpts
---@return string[]|nil wrapped_cmd, string|nil error
function M.wrap_command(inner_cmd, bufnr, opts)
  local cfg = M.resolve_config(opts)
  if not cfg.enabled then
    return inner_cmd, nil
  end

  local entry, resolve_err = resolve_backend(cfg)
  if not entry then
    if is_autodetect(cfg.backend) then
      -- Auto/required mode: no backend available yet — run unsandboxed.
      -- A backend may be registered later; cache will invalidate on register().
      return inner_cmd, nil
    end
    -- Explicit backend: user asked for it, fail if unavailable.
    return nil, resolve_err
  end

  local resolved = resolve_policy(cfg.policy or {}, bufnr)
  local backend_config = (cfg.backends or {})[entry.name] or {}
  return entry.wrap(resolved, backend_config, inner_cmd)
end

--- Check whether a path would be writable under the current policy.
--- For use by Lua-level tools (read/write/edit) in a future phase.
---@param path string
---@param bufnr integer
---@param opts? flemma.opt.FrontmatterOpts
---@return boolean
function M.is_path_writable(path, bufnr, opts)
  local cfg = M.resolve_config(opts)
  if not cfg.enabled then
    return true
  end

  local resolved = resolve_policy(cfg.policy or {}, bufnr)
  local abs_path = normalize(path)

  for _, rw in ipairs(resolved.rw_paths) do
    if vim.startswith(abs_path, rw .. "/") or abs_path == rw then
      return true
    end
  end

  return false
end

--- Detect the best available backend (public API for status/commands).
---@param opts? flemma.opt.FrontmatterOpts
---@return string|nil backend_name, string|nil diagnostic
function M.detect_available_backend(opts)
  local cfg = M.resolve_config(opts)
  return detect_backend(cfg.backends or {})
end

--- Set the runtime sandbox override (applies to all buffers)
---@param enabled boolean
function M.set_enabled(enabled)
  runtime_override = enabled
end

--- Clear the runtime override (revert to config-driven behavior)
function M.reset_enabled()
  runtime_override = nil
end

--- Get the runtime override value (for status display)
---@return boolean|nil nil means no override
function M.get_override()
  return runtime_override
end

return M
