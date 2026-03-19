--- Layer store for the unified configuration system.
---
--- Holds a per-layer operations log and resolves configuration values by
--- replaying those operations. Layers 10-30 are global (shared across all
--- buffers); layer 40 is per-buffer (frontmatter). Resolution algorithms
--- differ between scalars (top-down, first set wins) and lists (bottom-up,
--- accumulate set/append/remove/prepend).
---
--- This is an internal module. The public API lives in flemma.config.
---@class flemma.config.store
local M = {}

local nav = require("flemma.config.schema.navigation")

--- Layer priority constants.
---@type { DEFAULTS: integer, SETUP: integer, RUNTIME: integer, FRONTMATTER: integer }
M.LAYERS = {
  DEFAULTS = 10,
  SETUP = 20,
  RUNTIME = 30,
  FRONTMATTER = 40,
}

---@type table<integer, string>
local LAYER_NAMES = {
  [M.LAYERS.DEFAULTS] = "D",
  [M.LAYERS.SETUP] = "S",
  [M.LAYERS.RUNTIME] = "R",
  [M.LAYERS.FRONTMATTER] = "F",
}

--- Global layer numbers in ascending order (bottom-up traversal order).
---@type integer[]
local GLOBAL_LAYER_NUMS = { M.LAYERS.DEFAULTS, M.LAYERS.SETUP, M.LAYERS.RUNTIME }

-- ---------------------------------------------------------------------------
-- Private state (module-level singleton, reset by init())
-- ---------------------------------------------------------------------------

---@type flemma.config.schema.Node?
local schema_root = nil

--- Per-layer operations log for global layers.
--- Each entry: { op: string, path: string, value: any }
---@type table<integer, table[]>
local global_ops = {
  [M.LAYERS.DEFAULTS] = {},
  [M.LAYERS.SETUP] = {},
  [M.LAYERS.RUNTIME] = {},
}

--- Per-buffer operations log for the frontmatter layer (layer 40).
--- Keyed by bufnr.
---@type table<integer, table[]>
local buffer_ops = {}

-- ---------------------------------------------------------------------------
-- Schema navigation
-- ---------------------------------------------------------------------------

--- Return true if the given canonical path refers to a list field in the schema.
--- Uses unwrap_leaf = true so the returned node's is_list() reflects the concrete type.
---@param path string Dot-delimited canonical path
---@return boolean
local function is_list_path(path)
  if not schema_root then
    return false
  end
  local node = nav.navigate_schema(schema_root, path, { unwrap_leaf = true })
  if not node then
    return false
  end
  return node:is_list()
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

--- Initialize (or reset) the store with a root schema node.
--- Must be called before recording or resolving operations.
---@param root_schema flemma.config.schema.Node Root schema node for the config tree
function M.init(root_schema)
  schema_root = root_schema
  global_ops = {
    [M.LAYERS.DEFAULTS] = {},
    [M.LAYERS.SETUP] = {},
    [M.LAYERS.RUNTIME] = {},
  }
  buffer_ops = {}
end

-- ---------------------------------------------------------------------------
-- Recording operations
-- ---------------------------------------------------------------------------

--- Record a configuration operation on the given layer.
--- For FRONTMATTER (layer 40), bufnr identifies which buffer's layer to write.
--- For global layers (10/20/30), bufnr is ignored.
---@param layer integer One of M.LAYERS values
---@param bufnr integer? Buffer number (required for FRONTMATTER)
---@param op "set"|"append"|"remove"|"prepend" Operation type
---@param path string Dot-delimited canonical path (aliases already resolved)
---@param value any Value for the operation
function M.record(layer, bufnr, op, path, value)
  assert(op == "set" or op == "append" or op == "remove" or op == "prepend", "invalid op: " .. tostring(op))
  if layer == M.LAYERS.FRONTMATTER then
    assert(bufnr ~= nil, "bufnr is required for FRONTMATTER layer")
    if not buffer_ops[bufnr] then
      buffer_ops[bufnr] = {}
    end
    table.insert(buffer_ops[bufnr], { op = op, path = path, value = value })
  else
    if not global_ops[layer] then
      global_ops[layer] = {}
    end
    table.insert(global_ops[layer], { op = op, path = path, value = value })
  end
end

-- ---------------------------------------------------------------------------
-- Resolution helpers
-- ---------------------------------------------------------------------------

--- Return all ops in an ops array that match the given path, in order.
---@param ops_array table[]
---@param path string
---@return table[]
local function ops_for_path(ops_array, path)
  local result = {}
  for _, entry in ipairs(ops_array or {}) do
    if entry.path == path then
      table.insert(result, entry)
    end
  end
  return result
end

--- Build an ordered list of (layer_num, ops_array) pairs in ascending order
--- (L10 → L20 → L30 → L40). Omits the buffer layer when bufnr is nil.
---@param bufnr integer?
---@return { num: integer, ops: table[] }[]
local function ordered_layers(bufnr)
  local result = {}
  for _, num in ipairs(GLOBAL_LAYER_NUMS) do
    table.insert(result, { num = num, ops = global_ops[num] or {} })
  end
  if bufnr ~= nil then
    table.insert(result, { num = M.LAYERS.FRONTMATTER, ops = buffer_ops[bufnr] or {} })
  end
  return result
end

--- Add a layer indicator to the contributing list if not already present.
---@param contributing string[]
---@param indicator string
local function add_contributor(contributing, indicator)
  for _, existing in ipairs(contributing) do
    if existing == indicator then
      return
    end
  end
  table.insert(contributing, indicator)
end

--- Resolve a scalar path: walk layers top-down (highest priority first).
--- The first layer with a `set` op for this path wins.
---@param path string
---@param bufnr integer?
---@return any value, string? source Layer indicator e.g. "D", "S", "R", "F"
local function resolve_scalar(path, bufnr)
  local layers = ordered_layers(bufnr)
  for i = #layers, 1, -1 do
    local layer = layers[i]
    local path_ops = ops_for_path(layer.ops, path)
    -- Last write within a layer wins (iterate in reverse)
    for j = #path_ops, 1, -1 do
      if path_ops[j].op == "set" then
        return path_ops[j].value, LAYER_NAMES[layer.num]
      end
    end
  end
  return nil, nil
end

--- Resolve a list path: walk layers bottom-up, accumulating operations.
--- `set` resets the accumulator (and contributing layers).
--- `append`/`prepend` add items with dedup-and-move semantics.
--- `remove` removes items (no-op if absent).
---@param path string
---@param bufnr integer?
---@return any[]? value, string? source Layer indicator(s) e.g. "D", "S+F"
local function resolve_list(path, bufnr)
  ---@type any[]?
  local acc = nil
  ---@type string[]
  local contributing = {}

  local layers = ordered_layers(bufnr)
  for _, layer in ipairs(layers) do
    local path_ops = ops_for_path(layer.ops, path)
    for _, entry in ipairs(path_ops) do
      if entry.op == "set" then
        acc = vim.deepcopy(entry.value)
        -- This set "takes ownership" — layers before it no longer contribute.
        contributing = { LAYER_NAMES[layer.num] }
      elseif entry.op == "append" then
        if acc == nil then
          acc = {}
        end
        -- Dedup: if already present, move to end
        for i, item in ipairs(acc) do
          if item == entry.value then
            table.remove(acc, i)
            break
          end
        end
        table.insert(acc, entry.value)
        add_contributor(contributing, LAYER_NAMES[layer.num])
      elseif entry.op == "prepend" then
        if acc == nil then
          acc = {}
        end
        -- Dedup: if already present, move to front
        for i, item in ipairs(acc) do
          if item == entry.value then
            table.remove(acc, i)
            break
          end
        end
        table.insert(acc, 1, entry.value)
        add_contributor(contributing, LAYER_NAMES[layer.num])
      elseif entry.op == "remove" then
        if acc then
          for i, item in ipairs(acc) do
            if item == entry.value then
              table.remove(acc, i)
              -- Only attribute this layer when the remove actually changed the list.
              add_contributor(contributing, LAYER_NAMES[layer.num])
              break
            end
          end
        end
      end
    end
  end

  local source = #contributing > 0 and table.concat(contributing, "+") or nil
  return acc, source
end

-- ---------------------------------------------------------------------------
-- Public resolution API
-- ---------------------------------------------------------------------------

--- Resolve the value at the given canonical path for the given buffer.
--- Uses scalar resolution (top-down) for non-list paths and list resolution
--- (bottom-up accumulation) for list paths.
---@param path string Dot-delimited canonical path
---@param bufnr integer? Buffer number for per-buffer resolution; nil for global-only
---@return any
function M.resolve(path, bufnr)
  if is_list_path(path) then
    local value = resolve_list(path, bufnr)
    return value
  else
    local value = resolve_scalar(path, bufnr)
    return value
  end
end

--- Resolve the value and its source layer indicator at the given canonical path.
--- Source is a layer indicator string: "D", "S", "R", "F" for single-layer
--- resolution, or "X+Y" for list paths with ops across multiple layers.
---@param path string Dot-delimited canonical path
---@param bufnr integer? Buffer number; nil for global-only resolution
---@return any value, string? source
function M.resolve_with_source(path, bufnr)
  if is_list_path(path) then
    return resolve_list(path, bufnr)
  else
    return resolve_scalar(path, bufnr)
  end
end

-- ---------------------------------------------------------------------------
-- Layer management
-- ---------------------------------------------------------------------------

--- Clear all recorded operations for the given layer.
--- For FRONTMATTER (layer 40), clears only the specified buffer's ops.
--- For global layers (10/20/30), bufnr is ignored.
---@param layer integer One of M.LAYERS values
---@param bufnr integer? Required for FRONTMATTER; ignored for global layers
function M.clear(layer, bufnr)
  if layer == M.LAYERS.FRONTMATTER then
    assert(bufnr ~= nil, "bufnr is required for FRONTMATTER layer")
    buffer_ops[bufnr] = {}
  else
    global_ops[layer] = {}
  end
end

--- Return a deep copy of the raw operations log for the given layer.
---@param layer integer
---@param bufnr integer? Required for FRONTMATTER
---@return table[]
function M.dump_layer(layer, bufnr)
  if layer == M.LAYERS.FRONTMATTER then
    assert(bufnr ~= nil, "bufnr is required for FRONTMATTER layer")
    return vim.deepcopy(buffer_ops[bufnr] or {})
  else
    return vim.deepcopy(global_ops[layer] or {})
  end
end

return M
