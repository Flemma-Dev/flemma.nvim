--- Public API for the unified configuration system.
---
--- Provides the top-level entry points for initializing, reading, writing,
--- and introspecting configuration. All structural access goes through proxies;
--- all operations go through the layer store.
---
--- During the config overhaul, `lua/flemma/config.lua` (legacy) shadows
--- `lua/flemma/config/init.lua`. This module lives at `flemma.config.facade`
--- until the legacy file is deleted, then becomes `flemma.config` (init.lua).
---
--- Usage:
---   local config = require("flemma.config.facade")
---   config.init(schema)
---   config.apply(config.LAYERS.SETUP, user_opts)
---   local cfg = config.get(bufnr)
---@class flemma.config.facade
local M = {}

local nav = require("flemma.config.schema.navigation")
local proxy = require("flemma.config.proxy")
local store = require("flemma.config.store")

--- Layer priority constants.
M.LAYERS = store.LAYERS

---@type flemma.config.schema.Node?
local root_schema = nil

-- ---------------------------------------------------------------------------
-- Internal: recursive table application
-- ---------------------------------------------------------------------------

--- Recursively walk a plain Lua table and record set ops on the target layer.
--- Object nodes are walked into; lists and scalars become single set ops.
--- Alias keys at each object level are resolved to canonical paths.
---@param schema flemma.config.schema.Node Root schema for navigation
---@param path string Current dot-delimited canonical path (empty for root)
---@param value any The value at this path
---@param layer integer Target layer
---@param bufnr integer? Buffer number (required for FRONTMATTER)
---@return boolean? ok True on success, nil on failure
---@return string? err Error message on failure
local function apply_recursive(schema, path, value, layer, bufnr)
  if path == "" then
    if type(value) ~= "table" then
      return nil, "config.apply: root value must be a table"
    end
    local obj_node = nav.unwrap_optional(schema)
    for k, v in pairs(value) do
      local alias_target = obj_node:resolve_alias(k)
      local child_path = alias_target or k
      local ok, err = apply_recursive(schema, child_path, v, layer, bufnr)
      if not ok then
        return nil, err
      end
    end
    return true
  end

  local leaf = nav.navigate_schema(schema, path, { unwrap_leaf = true })
  if not leaf then
    return nil, string.format("config.apply: unknown key '%s'", path)
  end

  if leaf:is_object() and type(value) == "table" then
    for k, v in pairs(value) do
      local alias_target = leaf:resolve_alias(k)
      local canonical_key = alias_target or k
      local child_path = path .. "." .. canonical_key
      local ok, err = apply_recursive(schema, child_path, v, layer, bufnr)
      if not ok then
        return nil, err
      end
    end
  else
    local valid, err = leaf:validate_value(value)
    if not valid then
      return nil, string.format("config.apply: validation error at '%s': %s", path, err or "invalid")
    end
    store.record(layer, bufnr, "set", path, value)
  end
  return true
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
    local ok, err = apply_recursive(schema, "", defaults, M.LAYERS.DEFAULTS, nil)
    if not ok then
      error("config.init: failed to materialize defaults: " .. err)
    end
  end
end

--- Apply a plain Lua table as set operations on the given layer.
--- Recursively walks the table: object-typed fields are walked into,
--- lists and scalars become individual set ops. Alias keys are resolved
--- at each level. All values are validated against the schema.
---@param layer integer Target layer (e.g., M.LAYERS.SETUP)
---@param opts table Plain Lua table of config values
---@param _apply_opts? { defer_discover?: boolean } Reserved for two-pass boot (not yet implemented)
---@return boolean? ok True on success, nil on failure
---@return string? err Error message on failure
function M.apply(layer, opts, _apply_opts)
  assert(root_schema, "config.init() must be called before apply()")
  return apply_recursive(root_schema, "", opts, layer, nil)
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

return M
