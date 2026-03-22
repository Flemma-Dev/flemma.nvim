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
---@class flemma.config
local M = {}

local nav = require("flemma.config.schema.navigation")
local proxy = require("flemma.config.proxy")
local store = require("flemma.config.store")

--- Layer priority constants.
M.LAYERS = store.LAYERS

---@type flemma.config.schema.Node?
local root_schema = nil

-- ---------------------------------------------------------------------------
-- Internal: schema helpers
-- ---------------------------------------------------------------------------

--- Return true when the given canonical path refers to a list field.
--- Recognises standalone ListNodes, OptionalNode(ListNode), ObjectNodes with
--- :allow_list(), and UnionNodes with a list branch.
--- Uses unwrap_leaf = true so OptionalNode delegates correctly to its inner node.
---@param path string Dot-delimited canonical path
---@return boolean
local function is_list_path(path)
  if not root_schema then
    return false
  end
  local node = nav.navigate_schema(root_schema, path, { unwrap_leaf = true })
  if not node then
    return false
  end
  return node:is_list() or node:has_list_part()
end

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
---@field errors string[]? Accumulator for validation errors (nil = abort-on-first-error)

--- Report a validation error: collect if in resilient mode, abort otherwise.
--- In resilient mode (ctx.errors non-nil), the error is appended and the caller
--- should continue processing siblings. In strict mode, returns nil+err for
--- the caller to propagate upward.
---@param ctx flemma.config.ApplyContext
---@param msg string Error message
---@return boolean? ok True when collected, nil when aborting
---@return string? err Error message when aborting
local function report_error(ctx, msg)
  if ctx.errors then
    table.insert(ctx.errors, msg)
    return true
  end
  return nil, msg
end

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
    return report_error(ctx, string.format("config.apply: unknown key '%s'", path))
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
            return report_error(
              ctx,
              string.format("config.apply: list item[%d] at '%s': %s", i, path, err or "invalid")
            )
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
      return report_error(ctx, string.format("config.apply: validation error at '%s': %s", path, err or "invalid"))
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
    return store.resolve(base_path, bufnr, { is_list = is_list_path(base_path) })
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
  store.init()
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
--- registration. Non-DISCOVER errors are collected and returned (not fatal).
---@param layer integer Target layer (e.g., M.LAYERS.SETUP)
---@param opts table Plain Lua table of config values
---@param apply_opts? { defer_discover?: boolean }
---@return boolean? ok True on success (including partial with errors), nil on hard failure
---@return string[]? errors Validation errors (nil if none)
---@return table[]? deferred Deferred writes (only when defer_discover = true and items were deferred)
function M.apply(layer, opts, apply_opts)
  assert(root_schema, "config.init() must be called before apply()")
  local defer = apply_opts and apply_opts.defer_discover
  ---@type flemma.config.ApplyContext
  local ctx = { schema = root_schema, layer = layer, bufnr = nil, deferred = defer and {} or nil, errors = {} }
  local ok, err = apply_recursive(ctx, "", opts)
  if not ok then
    -- Hard failure (programming error, e.g. non-table root value)
    return nil, { err }
  end
  local errors = #ctx.errors > 0 and ctx.errors or nil
  if ctx.deferred and #ctx.deferred > 0 then
    return true, errors, ctx.deferred
  end
  return true, errors
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
    vim.notify("Flemma: register_module_defaults failed for " .. base_path .. ": " .. err, vim.log.levels.WARN)
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
--- Use when consumers need `pairs()`, `vim.deepcopy()`, or plain table semantics.
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
  local value, source = store.resolve_with_source(path, bufnr, { is_list = is_list_path(path) })
  return { value = value, layer = source }
end

--- Walk the schema tree and resolve every leaf path from the store,
--- returning a flat list of entries with path, value, source, and depth.
--- ObjectNodes are recursed into; all other nodes produce leaf entries.
---@param schema flemma.config.schema.Node Schema node to walk
---@param base_path string Dot-delimited path prefix (empty for root)
---@param bufnr integer? Buffer number for per-buffer resolution
---@param depth integer Current nesting depth
---@param out { path: string, value: any, source: string?, depth: integer, is_object: boolean }[] Accumulator
local function dump_resolved_walk(schema, base_path, bufnr, depth, out)
  local unwrapped = nav.unwrap_optional(schema)
  if unwrapped:is_object() then
    if base_path ~= "" then
      table.insert(out, { path = base_path, value = nil, source = nil, depth = depth, is_object = true })
    end
    -- Sort keys for deterministic output (all_known_fields uses pairs())
    local sorted = {}
    for k, child in unwrapped:all_known_fields() do
      table.insert(sorted, { k = k, child = child })
    end
    table.sort(sorted, function(a, b)
      return a.k < b.k
    end)
    for _, entry in ipairs(sorted) do
      local child_path = base_path == "" and entry.k or (base_path .. "." .. entry.k)
      -- Root children stay at depth 0; nested children indent
      dump_resolved_walk(entry.child, child_path, bufnr, base_path == "" and depth or depth + 1, out)
    end
  else
    local value, source = store.resolve_with_source(base_path, bufnr, { is_list = is_list_path(base_path) })
    if value ~= nil then
      table.insert(out, { path = base_path, value = value, source = source, depth = depth, is_object = false })
    end
  end
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

--- Check whether a layer has a specific operation for the given path.
--- Useful for detecting frontmatter intent (e.g., "did the user explicitly
--- remove this tool from auto_approve?").
---@param layer integer
---@param bufnr? integer Required for FRONTMATTER
---@param op string Operation type ("set", "append", "remove", "prepend")
---@param path string Dot-delimited canonical path
---@param value? any If provided, also match the op's value
---@return boolean
function M.layer_has_op(layer, bufnr, op, path, value)
  return store.layer_has_op(layer, bufnr, op, path, value)
end

--- Return the full resolved config tree with source annotations.
--- Each entry has path, value, source layer indicator, depth, and whether
--- it is an object header (intermediate node).
---@param bufnr? integer Buffer number for per-buffer resolution
---@return { path: string, value: any, source: string?, depth: integer, is_object: boolean }[]
function M.dump_resolved(bufnr)
  assert(root_schema, "config.init() must be called before dump_resolved()")
  local out = {}
  dump_resolved_walk(root_schema, "", bufnr, 0, out)
  return out
end

-- ---------------------------------------------------------------------------
-- Finalization
-- ---------------------------------------------------------------------------

--- Walk the schema tree and re-run coerce transforms on ops in the store.
--- For each node with a coerce function, matching ops are transformed with
--- a populated ctx. When the hook returns a table for a non-set list op
--- (append/remove/prepend), the single op is expanded into multiple ops.
---
--- When bufnr is provided, only that buffer's frontmatter ops are transformed
--- (used by finalize with bufnr for frontmatter). When nil, all buffers are
--- transformed (used by finalize at setup time).
---@param schema flemma.config.schema.Node Schema node to walk
---@param base_path string Current dot-delimited path
---@param ctx flemma.config.CoerceContext
---@param bufnr integer? Scope transforms to this buffer's frontmatter; nil for all
local function coerce_walk(schema, base_path, ctx, bufnr)
  local unwrapped = nav.unwrap_optional(schema)

  if unwrapped:has_coerce() then
    local coerce_fn = unwrapped:get_coerce() --[[@as fun(value: any, ctx: flemma.config.CoerceContext?): any]]
    local is_list = unwrapped:is_list() or unwrapped:has_list_part()
    store.transform_ops(base_path, coerce_fn, ctx, bufnr, { is_list = is_list })
  end

  if unwrapped:is_object() then
    for k, child in unwrapped:all_known_fields() do
      local child_path = base_path == "" and k or (base_path .. "." .. k)
      coerce_walk(child, child_path, ctx, bufnr)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Deferred validation
-- ---------------------------------------------------------------------------

--- A single deferred validation failure, passed to the reporter callback.
---@class flemma.config.ValidationFailure
---@field path string Dot-delimited config path
---@field value any The value that failed validation
---@field message string Human-readable error description

--- Find the deferred validator for a given op path.
--- For scalar paths, returns the node's own validator.
--- For list-capable paths, returns the item schema's validator.
---@param path string Dot-delimited canonical path
---@return (fun(value: any, ctx: flemma.config.CoerceContext): boolean, string?)?
local function find_validator_for_path(path)
  ---@cast root_schema flemma.config.schema.Node
  local node = nav.navigate_schema(root_schema, path, { unwrap_leaf = true })
  if not node then
    return nil
  end
  -- Direct validator on the node itself (scalar fields)
  if node:has_deferred_validator() then
    return node:get_deferred_validator()
  end
  -- List item validator (ObjectNode with allow_list, or ListNode)
  local item_schema = nil
  if node:has_list_part() then
    item_schema = node:get_list_item_schema()
  elseif node:is_list() then
    item_schema = node:get_item_schema()
  end
  if item_schema then
    local item_unwrapped = nav.unwrap_optional(item_schema)
    if item_unwrapped:has_deferred_validator() then
      return item_unwrapped:get_deferred_validator()
    end
  end
  return nil
end

--- Validate all ops in a layer by running deferred validators on each op value.
--- Validates what the user actually wrote (including removes), not the resolved state.
---@param layer integer Layer to validate
---@param ctx flemma.config.CoerceContext
---@param bufnr integer? Buffer number (required for FRONTMATTER)
---@param failures flemma.config.ValidationFailure[] Accumulator
local function validate_ops(layer, ctx, bufnr, failures)
  local ops = store.dump_layer(layer, bufnr)
  for _, entry in ipairs(ops) do
    local validator = find_validator_for_path(entry.path)
    if validator then
      -- For set ops with a table value, validate each item individually
      if entry.op == "set" and type(entry.value) == "table" then
        for _, item in ipairs(entry.value) do
          local ok, message = validator(item, ctx)
          if not ok then
            table.insert(failures, {
              path = entry.path,
              value = item,
              message = message or ("validation failed for '%s'"):format(tostring(item)),
            })
          end
        end
      else
        local ok, message = validator(entry.value, ctx)
        if not ok then
          table.insert(failures, {
            path = entry.path,
            value = entry.value,
            message = message or ("validation failed for '%s'"):format(tostring(entry.value)),
          })
        end
      end
    end
  end
end

--- Finalize a config layer: replay deferred writes, re-run coerce transforms,
--- and run deferred semantic validators.
---
--- For setup (L20): call once after module registration. Deferred DISCOVER
--- writes are replayed and coerce transforms re-run with a populated ctx.
---
--- For frontmatter (L40): call after frontmatter code executes. Coerce
--- transforms expand preset references; validators catch typos.
---
--- When bufnr is provided, coerce and validation are scoped to that buffer's
--- ops. When nil, all ops across all buffers are processed.
---@param layer integer Target layer
---@param deferred? table[] Deferred writes from apply() pass 1
---@param bufnr? integer Buffer scope for coerce/validation; nil for global
---@return { path: string, error: string }[]? deferred_failures Deferred entries that failed, or nil
---@return flemma.config.ValidationFailure[] validation_failures Semantic validation failures (empty when none)
function M.finalize(layer, deferred, bufnr)
  assert(root_schema, "config.init() must be called before finalize()")

  -- Pass 2: replay deferred writes (DISCOVER should resolve now)
  local deferred_failures = nil
  if deferred and #deferred > 0 then
    deferred_failures = M.apply_deferred(layer, deferred)
  end

  -- Re-run coerce transforms with populated ctx
  local ctx = store.make_coerce_context(bufnr, is_list_path)
  coerce_walk(root_schema, "", ctx, bufnr)

  -- Run deferred semantic validators (post-coerce)
  local validation_failures = {} ---@type flemma.config.ValidationFailure[]
  validate_ops(layer, ctx, bufnr, validation_failures)

  return deferred_failures, validation_failures
end

-- ---------------------------------------------------------------------------
-- Frontmatter lifecycle
-- ---------------------------------------------------------------------------

--- Prepare the frontmatter layer for evaluation.
--- Clears the buffer's L40 ops and returns a write proxy that frontmatter
--- code can use as `flemma.opt`. After frontmatter execution, call
--- `finalize(FRONTMATTER, nil, bufnr)` to run coerce + validation.
---@param bufnr integer Buffer number
---@return table writer Write proxy for the frontmatter layer
function M.prepare_frontmatter(bufnr)
  assert(root_schema, "config.init() must be called before prepare_frontmatter()")
  assert(bufnr ~= nil, "bufnr is required for prepare_frontmatter()")
  store.clear(M.LAYERS.FRONTMATTER, bufnr)
  return proxy.write_proxy(root_schema, bufnr, M.LAYERS.FRONTMATTER)
end

--- Release a buffer's frontmatter operations from memory.
--- Called during buffer cleanup to prevent orphaned entries from
--- accumulating across long sessions with many buffers.
---@param bufnr integer Buffer number
function M.cleanup_buffer(bufnr)
  store.purge_buffer(bufnr)
end

return M
