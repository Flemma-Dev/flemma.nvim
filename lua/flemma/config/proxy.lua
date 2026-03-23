--- Proxy metatables for the unified configuration system.
---
--- Provides read proxies, write proxies, list proxies, and frozen lenses.
---
---   Read proxy  (`read_proxy`):  resolve config values through all store layers.
---   Write proxy (`write_proxy`): record ops to a specific layer with schema validation.
---   List proxy:                  returned by write proxy for list fields; exposes mutation ops.
---   Hybrid proxy:                write proxy for ObjectNodes with :allow_list(); supports
---                                both sub-key navigation and list ops (append/remove/prepend).
---   Frozen lens (`lens`):        read-only proxy rooted at a config sub-path.
---
--- This is an internal module. The public API lives in flemma.config.
---@class flemma.config.proxy
local M = {}

local nav = require("flemma.schema.navigation")
local store = require("flemma.config.store")
local symbols = require("flemma.symbols")

--- Build an is_list classifier function for the given root schema.
--- Returns true when the path refers to a list-capable field (ListNode,
--- OptionalNode(ListNode), ObjectNode with allow_list, or UnionNode with list branch).
---@param root_schema flemma.schema.Node
---@return fun(path: string): boolean
local function make_is_list_fn(root_schema)
  return function(path)
    local node = nav.navigate_schema(root_schema, path, { unwrap_leaf = true })
    if not node then
      return false
    end
    return node:is_list() or node:has_list_part()
  end
end

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
---@param obj_node flemma.schema.Node Schema node at the current proxy level
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
---@field _item_schema flemma.schema.Node Schema for each list item
---@field _coerce_fn? fun(value: any, ctx: flemma.schema.CoerceContext?): any Per-item coerce function
---@field _root_schema flemma.schema.Node Root schema for coerce context list classification
local ListProxy = {}
ListProxy.__index = ListProxy

--- Coerce an item and record one or more ops of the given type.
--- If coerce expands a single item into a table, each expanded item becomes
--- a separate op (e.g., remove("$default") → remove("bash") + remove("ls")).
--- Coerce functions that return a table MUST return a sequential array —
--- non-sequential tables are silently truncated by ipairs.
--- Validates each expanded item against the item schema (except for remove).
---@param self flemma.config.ListProxy
---@param op "append"|"remove"|"prepend"
---@param item any
---@param skip_validation? boolean True for remove (no-op if absent)
local function record_list_op(self, op, item, skip_validation)
  if self._coerce_fn then
    item = self._coerce_fn(item, store.make_coerce_context(self._bufnr, make_is_list_fn(self._root_schema)))
  end
  if type(item) == "table" then
    for _, expanded in ipairs(item) do
      if not skip_validation then
        local ok, err = self._item_schema:validate_value(expanded)
        if not ok then
          error({
            type = "config",
            error = string.format("list %s error at '%s': %s", op, self._path, err or "invalid"),
          })
        end
      end
      store.record(self._layer, self._bufnr, op, self._path, expanded)
    end
  else
    if not skip_validation then
      local ok, err = self._item_schema:validate_value(item)
      if not ok then
        error({ type = "config", error = string.format("list %s error at '%s': %s", op, self._path, err or "invalid") })
      end
    end
    store.record(self._layer, self._bufnr, op, self._path, item)
  end
end

--- Coerce, validate, and record an append op.
---@param item any
---@return flemma.config.ListProxy self
function ListProxy:append(item)
  record_list_op(self, "append", item)
  return self
end

--- Coerce and record a remove op (no item validation — no-op if absent).
---@param item any
---@return flemma.config.ListProxy self
function ListProxy:remove(item)
  record_list_op(self, "remove", item, true)
  return self
end

--- Coerce, validate, and record a prepend op.
---@param item any
---@return flemma.config.ListProxy self
function ListProxy:prepend(item)
  record_list_op(self, "prepend", item)
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
---@param item_schema flemma.schema.Node
---@param coerce_fn? fun(value: any, ctx: flemma.schema.CoerceContext?): any
---@param root_schema flemma.schema.Node
---@return flemma.config.ListProxy
local function make_list_proxy(path, layer, bufnr, item_schema, coerce_fn, root_schema)
  return setmetatable({
    _path = path,
    _layer = layer,
    _bufnr = bufnr,
    _item_schema = item_schema,
    _coerce_fn = coerce_fn,
    _root_schema = root_schema,
  }, ListProxy)
end

-- ---------------------------------------------------------------------------
-- Read / Write Proxy factory
-- ---------------------------------------------------------------------------

--- Known list method names. Hybrid proxies expose these as bound methods
--- when the key is not a schema field or alias.
---@type table<string, boolean>
local LIST_METHODS = { append = true, remove = true, prepend = true }

--- Check whether a value is a write proxy or ListProxy returned from an
--- operator chain. Such values are sentinels — the ops were already recorded
--- by the operator, so assignment back to the parent proxy is a no-op.
---@param value any
---@return boolean
local function is_op_chain_sentinel(value)
  local mt = getmetatable(value)
  if mt == nil then
    return false
  end
  -- ListProxy from pure list fields
  if mt == ListProxy then
    return true
  end
  -- Write proxy returned from hybrid operator chains (__add/__sub/__pow)
  if mt._is_write_proxy then
    return true
  end
  return false
end

--- Validate each item in a list table against the given item schema.
--- Returns true on success, false + error on the first invalid item.
---@param items any[] Sequential table of items
---@param item_schema flemma.schema.Node Schema for each item
---@param path string Canonical path (for error messages)
---@return boolean ok
---@return string? err
local function validate_list_items(items, item_schema, path)
  for i, item in ipairs(items) do
    local ok, err = item_schema:validate_value(item)
    if not ok then
      return false, string.format("config list set error at '%s' item[%d]: %s", path, i, err or "invalid")
    end
  end
  return true
end

--- Internal factory: create a read or write proxy.
---
--- `layer = nil`  → read-only proxy; any write attempt errors.
--- `layer = <n>`  → write proxy; records ops to that layer with schema validation.
---
--- For ObjectNodes with `:allow_list()`, write proxies become hybrid: they support
--- both sub-key navigation (object behavior) and list ops (append/remove/prepend +
--- operators). List set is triggered by assigning a sequential table.
---
--- The `base_path` and `current_schema` describe the proxy's root in the config tree.
--- The root-level proxy has `base_path = ""` and `current_schema = root_schema`.
---@param root_schema flemma.schema.Node Root schema for full-tree navigation
---@param bufnr integer? Buffer number used for store resolution
---@param layer integer? Target write layer (nil = read-only)
---@param base_path string Dot-delimited base path of this proxy (empty = config root)
---@param current_schema flemma.schema.Node Schema at base_path
---@return table proxy
local function make_proxy(root_schema, bufnr, layer, base_path, current_schema)
  local proxy = {}

  local unwrapped_current = nav.unwrap_optional(current_schema)
  local is_hybrid = layer ~= nil and unwrapped_current:has_list_part()

  local mt = {
    -- Used by is_op_chain_sentinel to detect operator chain returns.
    _is_write_proxy = (layer ~= nil),

    __index = function(_, key)
      if key == symbols.CLEAR then
        assert(layer ~= nil, "symbols.CLEAR called on a read-only proxy")
        return function()
          store.clear(layer, bufnr)
          return proxy
        end
      end

      if type(key) ~= "string" then
        return nil
      end

      local obj_node = nav.unwrap_optional(current_schema)
      local canonical = canonical_path_for(obj_node, base_path, key)

      local leaf = nav.navigate_schema(root_schema, canonical)
      if leaf == nil then
        if is_hybrid and LIST_METHODS[key] then
          -- is_hybrid guarantees layer ~= nil.
          local write_layer = layer --[[@as integer]]
          local item_schema = unwrapped_current:get_list_item_schema() --[[@as flemma.schema.Node]]
          local coerce_fn = unwrapped_current:has_coerce() and unwrapped_current:get_coerce() or nil
          local list_proxy = make_list_proxy(base_path, write_layer, bufnr, item_schema, coerce_fn, root_schema)
          local skip_validation = (key == "remove")
          return function(self_or_item, maybe_item)
            local item
            if maybe_item ~= nil then
              item = maybe_item
            else
              item = self_or_item
            end
            record_list_op(list_proxy, key, item, skip_validation)
            return proxy
          end
        end
        error({ type = "config", error = string.format("unknown key '%s'", canonical) })
      end

      -- ObjectNode → return a sub-proxy for further navigation.
      if leaf:is_object() then
        return make_proxy(root_schema, bufnr, layer, canonical, leaf)
      end

      -- List-capable field on a write proxy → return a ListProxy for mutation ops.
      -- get_item_schema() returns non-nil for ListNode, OptionalNode(ListNode),
      -- and UnionNode with a list branch — generalizing the is_list() check.
      -- Pass the leaf's coerce function so list ops expand per-item at write time.
      local item_schema = leaf:get_item_schema()
      if item_schema and layer ~= nil then
        local coerce_fn = leaf:has_coerce() and leaf:get_coerce() or nil
        return make_list_proxy(canonical, layer, bufnr, item_schema, coerce_fn, root_schema)
      end

      -- Leaf scalar (or list on a read proxy) → resolve from store.
      local is_list = leaf:is_list() or leaf:has_list_part()
      return store.resolve(canonical, bufnr, { is_list = is_list })
    end,

    __newindex = function(_, key, value)
      if layer == nil then
        error({
          type = "config",
          error = string.format("write not permitted on read-only proxy (attempted key '%s')", tostring(key)),
        })
      end

      if type(key) ~= "string" then
        error({
          type = "config",
          error = string.format("non-string key '%s' is not a valid config path", tostring(key)),
        })
      end

      -- Alias resolution (same logic as __index).
      local obj_node = nav.unwrap_optional(current_schema)
      local canonical = canonical_path_for(obj_node, base_path, key)

      -- Navigate schema to the target field.
      local leaf = nav.navigate_schema(root_schema, canonical)
      if leaf == nil then
        error({ type = "config", error = string.format("unknown key '%s'", canonical) })
      end

      -- Operator chains (+ - ^) already recorded their ops via the ListProxy
      -- or hybrid proxy and return the proxy itself. When assigned back
      -- (e.g. `w.f = w.f + item`), the value is a sentinel: ops are done.
      if is_op_chain_sentinel(value) then
        return
      end

      -- Apply write-time coercion before validation (e.g., boolean → {enabled=bool}).
      -- Coerce runs before the object check because it may transform a non-table
      -- value (e.g., boolean) into a table suitable for object field assignment.
      -- Context enables coerce functions to resolve deferred references (e.g.,
      -- preset names) by reading other config values from the store.
      local ctx = store.make_coerce_context(bufnr, make_is_list_fn(root_schema))
      local unwrapped_leaf = nav.unwrap_optional(leaf)

      -- List-typed fields with coerce: expand per-item so that preset references
      -- like "$default" are resolved into individual tool names at write time.
      -- This applies to pure ListNodes and hybrid ObjectNodes with allow_list().
      local is_list_set = false
      if leaf:has_coerce() and type(value) == "table" then
        if unwrapped_leaf:is_list() or unwrapped_leaf:has_list_part() then
          local expanded = {}
          for _, item in ipairs(value) do
            local coerced = leaf:apply_coerce(item, ctx)
            if type(coerced) == "table" then
              vim.list_extend(expanded, coerced)
            else
              table.insert(expanded, coerced)
            end
          end
          value = expanded
          is_list_set = true
        end
      end
      if not is_list_set then
        value = leaf:apply_coerce(value, ctx)
      end

      -- Object nodes: handle allow_list (hybrid) and plain object assignment.
      if leaf:is_object() then
        -- Hybrid objects with allow_list: sequential table → list set.
        -- Non-sequential tables fall through to normal object behavior.
        if unwrapped_leaf:has_list_part() and type(value) == "table" and vim.islist(value) then
          local list_item_schema = unwrapped_leaf:get_list_item_schema() --[[@as flemma.schema.Node]]
          local ok, err = validate_list_items(value, list_item_schema, canonical)
          if not ok then
            error({ type = "config", error = err })
          end
          store.record(layer, bufnr, "set", canonical, value)
          return
        end

        -- Normal object assignment: recursively set each sub-field via a
        -- sub-proxy (which handles per-field validation and aliases).
        if type(value) == "table" then
          local sub_proxy = make_proxy(root_schema, bufnr, layer, canonical, leaf)
          for k, v in pairs(value) do
            sub_proxy[k] = v
          end
          return
        end
        error({
          type = "config",
          error = string.format(
            "cannot assign to object field '%s' -- navigate into the field and write individual keys",
            canonical
          ),
        })
      end

      -- Validate the coerced value against the schema.
      local ok, err = leaf:validate_value(value)
      if not ok then
        error({ type = "config", error = string.format("write error at '%s': %s", canonical, err or "invalid") })
      end

      -- Record the set op on the target layer.
      store.record(layer, bufnr, "set", canonical, value)
    end,
    -- Guard against accidental pairs() on proxies (use materialize() instead).
    -- Effective in Lua 5.2+ runtimes; harmless no-op under LuaJIT 5.1 semantics.
    __pairs = function()
      error({ type = "config", error = "use config.materialize() instead of pairs() on a config proxy" })
    end,
  }

  -- Hybrid: operator overloads route through record_list_op for coerce support.
  -- is_hybrid guarantees layer ~= nil; cast once for all closures.
  if is_hybrid then
    local write_layer = layer --[[@as integer]]
    local item_schema = unwrapped_current:get_list_item_schema() --[[@as flemma.schema.Node]]
    local coerce_fn = unwrapped_current:has_coerce() and unwrapped_current:get_coerce() or nil
    local list_proxy = make_list_proxy(base_path, write_layer, bufnr, item_schema, coerce_fn, root_schema)

    mt.__add = function(_, item)
      record_list_op(list_proxy, "append", item)
      return proxy
    end

    mt.__sub = function(_, item)
      record_list_op(list_proxy, "remove", item, true)
      return proxy
    end

    mt.__pow = function(_, item)
      record_list_op(list_proxy, "prepend", item)
      return proxy
    end
  end

  return setmetatable(proxy, mt)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Create a read-only proxy at the config root.
--- Reads resolve through all store layers for the given buffer.
---@param root_schema flemma.schema.Node
---@param bufnr integer?
---@return table
function M.read_proxy(root_schema, bufnr)
  return make_proxy(root_schema, bufnr, nil, "", root_schema)
end

--- Create a write proxy at the config root targeting the given layer.
--- Writes record ops to the specified layer with schema validation.
--- Exposes `clear()` to reset the layer (returns self for chaining).
---@param root_schema flemma.schema.Node
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
---@param root_schema flemma.schema.Node
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
              local is_list = leaf:is_list() or leaf:has_list_part()
              local value = store.resolve(canonical, bufnr, { is_list = is_list })
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
    __pairs = function()
      error("config: use config.materialize() instead of pairs() on a config lens")
    end,
  })
  return lens_proxy
end

return M
