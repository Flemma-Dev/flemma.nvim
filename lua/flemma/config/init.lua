--- Public API for the unified configuration system.
---
--- Provides the top-level entry points for initializing, reading, writing,
--- and introspecting configuration. All structural access goes through proxies;
--- all operations go through the layer store.
---
--- Usage:
---   local config = require("flemma.config")
---   config.init(schema)
---   config.apply(config.LAYERS.SETUP, user_opts)
---   local cfg = config.get(bufnr)
---@class flemma.config.Facade
local M = {}

local nav = require("flemma.config.schema.navigation")
local proxy = require("flemma.config.proxy")
local store = require("flemma.config.store")

--- Layer priority constants.
M.LAYERS = store.LAYERS

---@type flemma.config.schema.Node?
local root_schema = nil

-- ---------------------------------------------------------------------------
-- Internal: path helpers
-- ---------------------------------------------------------------------------

--- Split a dot-delimited path into parent and leaf.
--- "tools.bash" → "tools", "bash"
--- "provider" → "", "provider"
---@param path string
---@return string parent Empty string for top-level keys
---@return string leaf
local function path_parent(path)
  local parent, leaf = path:match("^(.+)%.([^.]+)$")
  if parent then
    return parent, leaf
  end
  return "", path
end

-- ---------------------------------------------------------------------------
-- Internal: recursive table application
-- ---------------------------------------------------------------------------

--- Stable context threaded through apply_recursive calls.
--- Created once per apply/init/apply_deferred invocation.
---@class flemma.config.ApplyContext
---@field schema flemma.config.schema.Node Root schema for navigation
---@field layer integer Target layer
---@field bufnr integer? Buffer number (required for FRONTMATTER)
---@field deferred table[]? Accumulator for deferred writes (nil = normal mode)

--- Recursively walk a plain Lua table and record set ops on the target layer.
--- Object nodes are walked into; lists and scalars become single set ops.
--- Alias keys at each object level are resolved to canonical paths.
---
--- When `ctx.deferred` is non-nil (defer_discover mode), writes to unknown keys
--- on objects with DISCOVER callbacks are accumulated in the deferred list
--- instead of failing. The DISCOVER callback is NOT invoked — the key is
--- assumed to be unresolvable until modules are registered.
---@param ctx flemma.config.ApplyContext
---@param path string Current dot-delimited canonical path (empty for root)
---@param value any The value at this path
---@return boolean? ok True on success, nil on failure
---@return string? err Error message on failure
local function apply_recursive(ctx, path, value)
  if path == "" then
    if type(value) ~= "table" then
      return nil, "config.apply: root value must be a table"
    end
    local obj_node = nav.unwrap_optional(ctx.schema)
    for k, v in pairs(value) do
      local alias_target = obj_node:resolve_alias(k)
      local child_path = alias_target or k
      local ok, err = apply_recursive(ctx, child_path, v)
      if not ok then
        return nil, err
      end
    end
    return true
  end

  local leaf = nav.navigate_schema(ctx.schema, path, { unwrap_leaf = true })
  if not leaf then
    -- In defer_discover mode, check if the parent object has a DISCOVER
    -- callback. If so, defer this write for pass 2.
    if ctx.deferred then
      local parent = path_parent(path)
      local parent_node
      if parent == "" then
        parent_node = nav.unwrap_optional(ctx.schema)
      else
        parent_node = nav.navigate_schema(ctx.schema, parent, { unwrap_leaf = true })
      end
      if parent_node and parent_node:has_discover() then
        table.insert(ctx.deferred, { path = path, value = value })
        return true
      end
    end
    return nil, string.format("config.apply: unknown key '%s'", path)
  end

  if leaf:is_object() and type(value) == "table" then
    -- Hybrid objects with allow_list: sequential table → list set.
    -- Non-sequential tables fall through to normal object field walking.
    -- Note: coerce is NOT run here — it is deferred to finalize(), which
    -- re-runs coerce on all stored ops after modules/presets are registered.
    local unwrapped_leaf = nav.unwrap_optional(leaf)
    if unwrapped_leaf:has_list_part() and vim.islist(value) then
      -- Validate each item against the list item schema.
      local list_item_schema = unwrapped_leaf:get_list_item_schema()
      if list_item_schema then
        for i, item in ipairs(value) do
          local ok, err = list_item_schema:validate_value(item)
          if not ok then
            return nil, string.format("config.apply: list item[%d] at '%s': %s", i, path, err or "invalid")
          end
        end
      end
      store.record(ctx.layer, ctx.bufnr, "set", path, value)
    else
      for k, v in pairs(value) do
        local alias_target = leaf:resolve_alias(k)
        local canonical_key = alias_target or k
        local child_path = path .. "." .. canonical_key
        local ok, err = apply_recursive(ctx, child_path, v)
        if not ok then
          return nil, err
        end
      end
    end
  else
    local valid, err = leaf:validate_value(value)
    if not valid then
      return nil, string.format("config.apply: validation error at '%s': %s", path, err or "invalid")
    end
    store.record(ctx.layer, ctx.bufnr, "set", path, value)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Internal: materialization
-- ---------------------------------------------------------------------------

--- Walk the schema tree and resolve every path from the store into a plain table.
--- ObjectNodes are recursed into; all other nodes are resolved as leaf values.
---@param schema flemma.config.schema.Node Schema node to walk
---@param base_path string Dot-delimited path prefix (empty for root)
---@param bufnr integer? Buffer number for per-buffer resolution
---@return any
local function materialize_resolved(schema, base_path, bufnr)
  local unwrapped = nav.unwrap_optional(schema)
  if unwrapped:is_object() then
    local result = {}
    for k, child in unwrapped:all_known_fields() do
      local child_path = base_path == "" and k or (base_path .. "." .. k)
      local value = materialize_resolved(child, child_path, bufnr)
      if value ~= nil then
        result[k] = value
      end
    end
    -- Always return a table for objects, even when empty. Consumers expect
    -- intermediate objects to exist (e.g., config.parameters.thinking without
    -- nil-checking config.parameters). Matches vim.tbl_deep_extend behavior.
    return result
  else
    return store.resolve(base_path, bufnr)
  end
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

--- Initialize the config system with a root schema.
--- Stores the schema reference, resets the layer store, and materializes
--- schema defaults into the DEFAULTS layer.
---@param schema flemma.config.schema.Node Root schema node
function M.init(schema)
  root_schema = schema
  store.init(schema)
  local defaults = schema:materialize()
  if defaults then
    -- Defaults come from the schema itself — failure here is a schema bug.
    ---@type flemma.config.ApplyContext
    local ctx = { schema = schema, layer = M.LAYERS.DEFAULTS, bufnr = nil, deferred = nil }
    local ok, err = apply_recursive(ctx, "", defaults)
    if not ok then
      error("config.init: failed to materialize defaults: " .. err)
    end
  end
end

--- Apply a plain Lua table as set operations on the given layer.
--- Recursively walks the table: object-typed fields are walked into,
--- lists and scalars become individual set ops. Alias keys are resolved
--- at each level. All values are validated against the schema.
---
--- When `apply_opts.defer_discover` is true, writes to unknown keys on
--- objects with DISCOVER callbacks are deferred instead of failing. The
--- returned deferred list is replayed via `apply_deferred()` after module
--- registration. Non-DISCOVER errors are still fatal in pass 1.
---@param layer integer Target layer (e.g., M.LAYERS.SETUP)
---@param opts table Plain Lua table of config values
---@param apply_opts? { defer_discover?: boolean }
---@return boolean? ok True on success, nil on failure
---@return string? err Error message on failure
---@return table[]? deferred Deferred writes (only when defer_discover = true and items were deferred)
function M.apply(layer, opts, apply_opts)
  assert(root_schema, "config.init() must be called before apply()")
  local defer = apply_opts and apply_opts.defer_discover
  ---@type flemma.config.ApplyContext
  local ctx = { schema = root_schema, layer = layer, bufnr = nil, deferred = defer and {} or nil }
  local ok, err = apply_recursive(ctx, "", opts)
  if not ok then
    return nil, err
  end
  if ctx.deferred and #ctx.deferred > 0 then
    return true, nil, ctx.deferred
  end
  return true
end

--- Record a single operation on the DEFAULTS layer (L10).
--- Used by registries to populate default values that aren't part of the
--- schema's static materialization (e.g., appending tool names to the tools list).
---@param op "set"|"append"|"remove"|"prepend" Operation type
---@param path string Dot-delimited canonical path
---@param value any Value for the operation
function M.record_default(op, path, value)
  assert(root_schema, "config.init() must be called before record_default()")
  store.record(M.LAYERS.DEFAULTS, nil, op, path, value)
end

--- Materialize a discovered module's schema defaults into the DEFAULTS layer.
--- Called by registries (providers, tools, sandbox backends) after module
--- registration so that DISCOVER-resolved schemas contribute their defaults
--- to L10.
---@param parent_path string Dot-delimited path to the parent object (e.g., "parameters", "tools", "sandbox.backends")
---@param name string Module name (the DISCOVER key, e.g., "anthropic", "bash", "bwrap")
---@param config_schema flemma.config.schema.Node Module's config schema
function M.register_module_defaults(parent_path, name, config_schema)
  assert(root_schema, "config.init() must be called before register_module_defaults()")
  local defaults = config_schema:materialize()
  if not defaults then
    return
  end
  local base_path = parent_path .. "." .. name
  ---@type flemma.config.ApplyContext
  local ctx = { schema = root_schema, layer = M.LAYERS.DEFAULTS, bufnr = nil, deferred = nil }
  local ok, err = apply_recursive(ctx, base_path, defaults)
  if not ok then
    error("config.register_module_defaults: failed for " .. base_path .. ": " .. err)
  end
end

--- Replay deferred writes from a previous `apply()` call.
--- Invoked after module registration so DISCOVER callbacks can resolve.
--- Failures in pass 2 are genuine — the config key doesn't exist.
---@param layer integer Target layer (same layer as the original apply)
---@param deferred table[] Deferred writes from `apply()`
---@return { path: string, error: string }[]? failures Entries that still failed, or nil on success
function M.apply_deferred(layer, deferred)
  assert(root_schema, "config.init() must be called before apply_deferred()")
  ---@type flemma.config.ApplyContext
  local ctx = { schema = root_schema, layer = layer, bufnr = nil, deferred = nil }
  ---@type { path: string, error: string }[]
  local failures = {}
  for _, entry in ipairs(deferred) do
    local ok, err = apply_recursive(ctx, entry.path, entry.value)
    if not ok then
      table.insert(failures, { path = entry.path, error = err or ("unknown error at " .. entry.path) })
    end
  end
  if #failures > 0 then
    return failures
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Read / Write
-- ---------------------------------------------------------------------------

--- Return a read-only proxy resolving through all layers.
--- When bufnr is provided, includes the buffer's frontmatter layer.
---@param bufnr? integer Buffer number for per-buffer resolution
---@return table
function M.get(bufnr)
  assert(root_schema, "config.init() must be called before get()")
  return proxy.read_proxy(root_schema, bufnr)
end

--- Return a write proxy targeting the given layer.
--- The returned proxy validates all writes against the schema.
--- Call `writer[symbols.CLEAR]()` to clear the layer (returns self for chaining).
---@param bufnr? integer Buffer number (required for FRONTMATTER)
---@param layer integer Target layer
---@return table
function M.writer(bufnr, layer)
  assert(root_schema, "config.init() must be called before writer()")
  return proxy.write_proxy(root_schema, bufnr, layer)
end

-- ---------------------------------------------------------------------------
-- Lenses
-- ---------------------------------------------------------------------------

--- Return a frozen lens rooted at the given path(s).
--- A single string path is a single-path lens.
--- A table of paths is a composed lens with path-first priority.
---@param bufnr? integer Buffer number
---@param path string|string[] Sub-path or ordered list of sub-paths (most specific first)
---@return table
function M.lens(bufnr, path)
  assert(root_schema, "config.init() must be called before lens()")
  return proxy.lens(root_schema, bufnr, path)
end

-- ---------------------------------------------------------------------------
-- Materialization
-- ---------------------------------------------------------------------------

--- Materialize the current resolved config into a plain Lua table.
--- Walks the schema tree (static fields + DISCOVER-cached fields) and resolves
--- every path from the store. Returns a deep copy safe for external mutation.
---
--- Used as a bridge: feeds the old state.get_config() system from the new store
--- during the transition period.
---@param bufnr? integer Buffer number for per-buffer resolution
---@return table
function M.materialize(bufnr)
  assert(root_schema, "config.init() must be called before materialize()")
  return vim.deepcopy(materialize_resolved(root_schema, "", bufnr) or {})
end

-- ---------------------------------------------------------------------------
-- Introspection
-- ---------------------------------------------------------------------------

--- Resolve a value with its source layer indicator.
--- Returns a table with `value` and `layer` fields.
--- Layer is a string like "D", "S", "R", "F", or "S+F" for multi-layer lists.
---@param bufnr? integer Buffer number
---@param path string Dot-delimited canonical path
---@return { value: any, layer: string? }
function M.inspect(bufnr, path)
  assert(root_schema, "config.init() must be called before inspect()")
  local value, source = store.resolve_with_source(path, bufnr)
  return { value = value, layer = source }
end

--- Return a deep copy of raw operations for the given layer.
---@param layer integer
---@param bufnr? integer Required for FRONTMATTER
---@return table[]
function M.dump_layer(layer, bufnr)
  return store.dump_layer(layer, bufnr)
end

--- Check whether a layer has a "set" operation for the given path.
--- Useful for detecting explicit policy replacement (e.g., frontmatter
--- explicitly assigned tools.auto_approve).
---@param layer integer
---@param bufnr? integer Required for FRONTMATTER
---@param path string Dot-delimited canonical path
---@return boolean
function M.layer_has_set(layer, bufnr, path)
  return store.layer_has_set(layer, bufnr, path)
end

-- ---------------------------------------------------------------------------
-- Finalization
-- ---------------------------------------------------------------------------

--- Walk the schema tree and re-run coerce transforms on all ops in all layers.
--- For each node with a coerce function, every op on that path across all layers
--- is transformed with a populated ctx. When the hook returns a table for a
--- non-set list op (append/remove/prepend), the single op is expanded into
--- multiple ops.
---@param schema flemma.config.schema.Node Schema node to walk
---@param base_path string Current dot-delimited path
---@param ctx flemma.config.CoerceContext
local function coerce_walk(schema, base_path, ctx)
  local unwrapped = nav.unwrap_optional(schema)

  if unwrapped:has_coerce() then
    local coerce_fn = unwrapped:get_coerce() --[[@as fun(value: any, ctx: flemma.config.CoerceContext?): any]]
    store.transform_ops(base_path, coerce_fn, ctx)
  end

  if unwrapped:is_object() then
    for k, child in unwrapped:all_known_fields() do
      local child_path = base_path == "" and k or (base_path .. "." .. k)
      coerce_walk(child, child_path, ctx)
    end
  end
end

--- Finalize the config system after setup is complete.
--- Applies deferred writes, then re-runs coerce transforms on all stored ops
--- with a populated context. Call once at the end of setup(), after module
--- registration.
---
--- Coerce functions that depend on ctx (e.g., preset expansion) received nil
--- ctx during initial writes via config.apply(). Finalize re-runs them with
--- a real ctx so deferred references are expanded retroactively.
---@param layer integer Target layer for deferred replay
---@param deferred? table[] Deferred writes from apply() pass 1
---@return { path: string, error: string }[]? failures Deferred entries that failed, or nil
function M.finalize(layer, deferred)
  assert(root_schema, "config.init() must be called before finalize()")

  -- Pass 2: replay deferred writes (DISCOVER should resolve now)
  local failures = nil
  if deferred and #deferred > 0 then
    failures = M.apply_deferred(layer, deferred)
  end

  -- Re-run coerce transforms with populated ctx
  local ctx = store.make_coerce_context()
  coerce_walk(root_schema, "", ctx)

  return failures
end

return M
