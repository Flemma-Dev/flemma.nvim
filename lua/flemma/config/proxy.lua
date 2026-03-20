--- Proxy metatables for the unified configuration system.
---
--- Provides read proxies, write proxies, list proxies, and frozen lenses.
---
---   Read proxy  (`read_proxy`):  resolve config values through all store layers.
---   Write proxy (`write_proxy`): record ops to a specific layer with schema validation.
---   List proxy:                  returned by write proxy for list fields; exposes mutation ops.
---   Frozen lens (`lens`):        read-only proxy rooted at a config sub-path.
---
--- This is an internal module. The public API lives in flemma.config.
---@class flemma.config.proxy
local M = {}

local nav = require("flemma.config.schema.navigation")
local store = require("flemma.config.store")
local symbols = require("flemma.symbols")

--- Append a key or sub-path to a base path.
---@param base string Empty string for root, or dot-delimited base path
---@param key string Key or dot-delimited sub-path to append
---@return string
local function join_path(base, key)
  if base == "" then
    return key
  end
  return base .. "." .. key
end

--- Resolve the canonical path for a key access at a given schema level and base path.
--- Alias keys at the current schema level redirect to their canonical sub-paths.
---@param obj_node flemma.config.schema.Node Schema node at the current proxy level
---@param base_path string Dot-delimited base path of the current proxy
---@param key string The key being accessed
---@return string canonical_path Full dot-delimited path from config root
local function canonical_path_for(obj_node, base_path, key)
  local alias_target = obj_node:resolve_alias(key)
  if alias_target then
    return join_path(base_path, alias_target)
  end
  return join_path(base_path, key)
end

-- ---------------------------------------------------------------------------
-- ListProxy
-- ---------------------------------------------------------------------------

---@class flemma.config.ListProxy
---@field _path string Canonical dot-delimited path of the list field
---@field _layer integer Target layer for write ops
---@field _bufnr integer? Buffer number
---@field _item_schema flemma.config.schema.Node Schema for each list item
local ListProxy = {}
ListProxy.__index = ListProxy

--- Validate an item and record an append op.
---@param item any
---@return flemma.config.ListProxy self
function ListProxy:append(item)
  local ok, err = self._item_schema:validate_value(item)
  if not ok then
    error(string.format("config list append error at '%s': %s", self._path, err or "invalid"))
  end
  store.record(self._layer, self._bufnr, "append", self._path, item)
  return self
end

--- Record a remove op (no-op if item is absent; no item validation needed).
---@param item any
---@return flemma.config.ListProxy self
function ListProxy:remove(item)
  store.record(self._layer, self._bufnr, "remove", self._path, item)
  return self
end

--- Validate an item and record a prepend op.
---@param item any
---@return flemma.config.ListProxy self
function ListProxy:prepend(item)
  local ok, err = self._item_schema:validate_value(item)
  if not ok then
    error(string.format("config list prepend error at '%s': %s", self._path, err or "invalid"))
  end
  store.record(self._layer, self._bufnr, "prepend", self._path, item)
  return self
end

--- `list + item` operator — append.
ListProxy.__add = function(self, item)
  return self:append(item)
end

--- `list - item` operator — remove.
ListProxy.__sub = function(self, item)
  return self:remove(item)
end

--- `list ^ item` operator — prepend.
ListProxy.__pow = function(self, item)
  return self:prepend(item)
end

---@param path string
---@param layer integer
---@param bufnr integer?
---@param item_schema flemma.config.schema.Node
---@return flemma.config.ListProxy
local function make_list_proxy(path, layer, bufnr, item_schema)
  return setmetatable({
    _path = path,
    _layer = layer,
    _bufnr = bufnr,
    _item_schema = item_schema,
  }, ListProxy)
end

-- ---------------------------------------------------------------------------
-- Read / Write Proxy factory
-- ---------------------------------------------------------------------------

--- Internal factory: create a read or write proxy.
---
--- `layer = nil`  → read-only proxy; any write attempt errors.
--- `layer = <n>`  → write proxy; records ops to that layer with schema validation.
---
--- The `base_path` and `current_schema` describe the proxy's root in the config tree.
--- The root-level proxy has `base_path = ""` and `current_schema = root_schema`.
---@param root_schema flemma.config.schema.Node Root schema for full-tree navigation
---@param bufnr integer? Buffer number used for store resolution
---@param layer integer? Target write layer (nil = read-only)
---@param base_path string Dot-delimited base path of this proxy (empty = config root)
---@param current_schema flemma.config.schema.Node Schema at base_path
---@return table proxy
local function make_proxy(root_schema, bufnr, layer, base_path, current_schema)
  local proxy = {}

  local mt = {
    __index = function(_, key)
      -- symbols.CLEAR: clear all ops on the target layer and return self.
      -- Only valid on write proxies — calling clear on a read proxy is a bug.
      if key == symbols.CLEAR then
        assert(layer ~= nil, "symbols.CLEAR called on a read-only proxy")
        return function()
          store.clear(layer, bufnr)
          return proxy
        end
      end

      -- Only string keys are valid config paths. Non-string keys (symbols,
      -- numeric indices, etc.) have no meaning in the config schema.
      if type(key) ~= "string" then
        return nil
      end

      -- Resolve alias and compute the full canonical path from config root.
      local obj_node = nav.unwrap_optional(current_schema)
      local canonical = canonical_path_for(obj_node, base_path, key)

      -- Navigate the root schema to the canonical path to determine the node type.
      local leaf = nav.navigate_schema(root_schema, canonical)
      if leaf == nil then
        error(string.format("config: unknown key '%s'", canonical))
      end

      -- ObjectNode → return a sub-proxy for further navigation.
      if leaf:is_object() then
        return make_proxy(root_schema, bufnr, layer, canonical, leaf)
      end

      -- List field on a write proxy → return a ListProxy for mutation ops.
      -- get_item_schema() is non-nil when is_list() is true (ListNode guarantees this).
      if leaf:is_list() and layer ~= nil then
        local item_schema = leaf:get_item_schema() --[[@as flemma.config.schema.Node]]
        return make_list_proxy(canonical, layer, bufnr, item_schema)
      end

      -- Leaf scalar (or list on a read proxy) → resolve from store.
      return store.resolve(canonical, bufnr)
    end,

    __newindex = function(_, key, value)
      if layer == nil then
        error(string.format("config: write not permitted on read-only proxy (attempted key '%s')", tostring(key)))
      end

      if type(key) ~= "string" then
        error(string.format("config: non-string key '%s' is not a valid config path", tostring(key)))
      end

      -- Alias resolution (same logic as __index).
      local obj_node = nav.unwrap_optional(current_schema)
      local canonical = canonical_path_for(obj_node, base_path, key)

      -- Navigate schema to the target field.
      local leaf = nav.navigate_schema(root_schema, canonical)
      if leaf == nil then
        error(string.format("config: unknown key '%s'", canonical))
      end

      -- Operator chains (+ - ^) already recorded their ops via the ListProxy and
      -- return the proxy itself. When assigned back (e.g. `w.f = w.f + item`),
      -- the ListProxy value is a sentinel: the ops are done, nothing to record.
      if getmetatable(value) == ListProxy then
        return
      end

      -- Apply write-time coercion before validation (e.g., boolean → {enabled=bool}).
      -- Coerce runs before the object check because it may transform a non-table
      -- value (e.g., boolean) into a table suitable for object field assignment.
      -- Context enables coerce functions to resolve deferred references (e.g.,
      -- preset names) by reading other config values from the store.
      local ctx = store.make_coerce_context()
      value = leaf:apply_coerce(value, ctx)

      -- Object nodes: if coerce produced a table, recursively set each sub-field
      -- via a sub-proxy (which handles per-field validation and aliases). If the
      -- value is NOT a table after coerce, it's a genuine type error.
      if leaf:is_object() then
        if type(value) == "table" then
          local sub_proxy = make_proxy(root_schema, bufnr, layer, canonical, leaf)
          for k, v in pairs(value) do
            sub_proxy[k] = v
          end
          return
        end
        error(
          string.format(
            "config: cannot assign to object field '%s' — navigate into the field and write individual keys",
            canonical
          )
        )
      end

      -- Validate the coerced value against the schema.
      local ok, err = leaf:validate_value(value)
      if not ok then
        error(string.format("config write error at '%s': %s", canonical, err or "invalid"))
      end

      -- Record the set op on the target layer.
      store.record(layer, bufnr, "set", canonical, value)
    end,
  }

  return setmetatable(proxy, mt)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Create a read-only proxy at the config root.
--- Reads resolve through all store layers for the given buffer.
---@param root_schema flemma.config.schema.Node
---@param bufnr integer?
---@return table
function M.read_proxy(root_schema, bufnr)
  return make_proxy(root_schema, bufnr, nil, "", root_schema)
end

--- Create a write proxy at the config root targeting the given layer.
--- Writes record ops to the specified layer with schema validation.
--- Exposes `clear()` to reset the layer (returns self for chaining).
---@param root_schema flemma.config.schema.Node
---@param bufnr integer?
---@param layer integer One of store.LAYERS values
---@return table
function M.write_proxy(root_schema, bufnr, layer)
  return make_proxy(root_schema, bufnr, layer, "", root_schema)
end

--- Create a frozen lens rooted at the given path(s).
--- A single string path is normalized to a single-element list.
--- Reads check each base path in order (most specific first) and return the
--- first non-nil value found. Object-typed keys return a new narrowed lens
--- for further navigation. Aliases are resolved at each path's schema level.
--- Writes are not permitted.
---@param root_schema flemma.config.schema.Node
---@param bufnr integer?
---@param paths string|string[] Single path or ordered list of paths (most specific first)
---@return table
function M.lens(root_schema, bufnr, paths)
  if type(paths) == "string" then
    paths = { paths }
  end

  for _, path in ipairs(paths) do
    if not nav.navigate_schema(root_schema, path) then
      error(string.format("config.lens: unknown path '%s'", path))
    end
  end

  local lens_proxy = {}
  setmetatable(lens_proxy, {
    __index = function(_, key)
      if type(key) ~= "string" then
        return nil
      end

      local object_paths = {}

      for _, base_path in ipairs(paths) do
        local base_schema = nav.navigate_schema(root_schema, base_path)
        if base_schema then
          local unwrapped = nav.unwrap_optional(base_schema)
          local alias_target = unwrapped:resolve_alias(key)
          local canonical_key = alias_target or key
          local canonical = join_path(base_path, canonical_key)

          local leaf = nav.navigate_schema(root_schema, canonical)
          if leaf then
            if leaf:is_object() then
              table.insert(object_paths, canonical)
            else
              local value = store.resolve(canonical, bufnr)
              if value ~= nil then
                return value
              end
            end
          end
        end
      end

      if #object_paths > 0 then
        return M.lens(root_schema, bufnr, object_paths)
      end

      return nil
    end,
    __newindex = function(_, key, _)
      error(string.format("config: write not permitted on lens (attempted key '%s')", key))
    end,
  })
  return lens_proxy
end

return M
