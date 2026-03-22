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
-- Initialization
-- ---------------------------------------------------------------------------

--- Initialize (or reset) the store. Clears all layer ops.
--- Must be called before recording or resolving operations.
--- The store is schema-free: callers pass is_list explicitly to resolve/transform.
function M.init()
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
--- NOTE: This is a linear scan over all ops. At typical Flemma config sizes
--- (tens of ops per layer) this is fine. If profiling shows resolution on a
--- hot path, consider indexing ops by path (ops_by_path[path]) for O(1) lookup.
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
--- Uses list resolution (bottom-up accumulation) when opts.is_list is true,
--- scalar resolution (top-down, first set wins) otherwise.
--- The caller is responsible for determining is_list from the schema.
---@param path string Dot-delimited canonical path
---@param bufnr integer? Buffer number for per-buffer resolution; nil for global-only
---@param opts? { is_list: boolean } Resolution options; is_list defaults to false
---@return any
function M.resolve(path, bufnr, opts)
  local is_list = opts ~= nil and opts.is_list == true
  if is_list then
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
--- The caller is responsible for determining is_list from the schema.
---@param path string Dot-delimited canonical path
---@param bufnr integer? Buffer number; nil for global-only resolution
---@param opts? { is_list: boolean } Resolution options; is_list defaults to false
---@return any value, string? source
function M.resolve_with_source(path, bufnr, opts)
  local is_list = opts ~= nil and opts.is_list == true
  if is_list then
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

-- ---------------------------------------------------------------------------
-- Transform
-- ---------------------------------------------------------------------------

--- Transform all ops at the given path across all layers using a coerce function.
--- For "set" ops on lists: the value (a table) is passed to fn; result replaces it.
--- For "append"/"remove"/"prepend" ops: the single item is passed to fn.
---   If fn returns a table, the single op is expanded into multiple ops of the same type.
---   If fn returns a non-table value, the op value is replaced.
--- For "set" ops on scalars: value is passed to fn, result replaces it.
---
--- The function is called as fn(value, ctx) where ctx is a coerce context.
---@param path string Dot-delimited canonical path
---@param fn fun(value: any, ctx: any): any Coerce transform function
---@param ctx any Coerce context passed through to fn
---@param bufnr integer? When non-nil, only transform that buffer's frontmatter ops; when nil, transform all buffers
---@param opts? { is_list: boolean } Transform options; is_list defaults to false
function M.transform_ops(path, fn, ctx, bufnr, opts)
  -- is_list drives how set ops are handled: list paths do per-item transformation
  -- (each element passed to fn independently); scalar paths pass the whole value.
  local path_is_list = opts ~= nil and opts.is_list == true

  local all_ops = {}
  for _, num in ipairs(GLOBAL_LAYER_NUMS) do
    table.insert(all_ops, global_ops[num] or {})
  end
  if bufnr ~= nil then
    table.insert(all_ops, buffer_ops[bufnr] or {})
  else
    for _, buf_ops in pairs(buffer_ops) do
      table.insert(all_ops, buf_ops)
    end
  end

  for _, ops_array in ipairs(all_ops) do
    local i = 1
    while i <= #ops_array do
      local entry = ops_array[i]
      if entry.path == path then
        if entry.op == "set" then
          -- List paths: transform each item independently (enables per-item preset expansion).
          -- Scalar paths: transform the whole value as a single unit.
          if path_is_list and type(entry.value) == "table" then
            local new_list = {}
            for _, item in ipairs(entry.value) do
              local result = fn(item, ctx)
              if type(result) == "table" then
                for _, expanded in ipairs(result) do
                  table.insert(new_list, expanded)
                end
              else
                table.insert(new_list, result)
              end
            end
            entry.value = new_list
          else
            entry.value = fn(entry.value, ctx)
          end
          i = i + 1
        elseif entry.op == "append" or entry.op == "remove" or entry.op == "prepend" then
          local result = fn(entry.value, ctx)
          if type(result) == "table" then
            -- Expand: replace single op with multiple ops of the same type
            table.remove(ops_array, i)
            for j, expanded in ipairs(result) do
              table.insert(ops_array, i + j - 1, { op = entry.op, path = path, value = expanded })
            end
            i = i + #result
          else
            entry.value = result
            i = i + 1
          end
        else
          i = i + 1
        end
      else
        i = i + 1
      end
    end
  end
end

--- Check whether the given layer has a "set" operation for the given path.
--- Useful for detecting whether a higher layer explicitly replaced a value
--- (e.g., frontmatter explicitly assigned auto_approve).
---@param layer integer
---@param bufnr integer? Required for FRONTMATTER
---@param path string Dot-delimited canonical path
---@return boolean
function M.layer_has_set(layer, bufnr, path)
  local ops_array
  if layer == M.LAYERS.FRONTMATTER then
    assert(bufnr ~= nil, "bufnr is required for FRONTMATTER layer")
    ops_array = buffer_ops[bufnr]
  else
    ops_array = global_ops[layer]
  end
  for _, entry in ipairs(ops_array or {}) do
    if entry.op == "set" and entry.path == path then
      return true
    end
  end
  return false
end

--- Check whether the given layer has a specific operation for the given path and value.
--- Useful for detecting frontmatter intent (e.g., "did the user explicitly remove
--- this tool from auto_approve?").
---@param layer integer
---@param bufnr integer? Required for FRONTMATTER
---@param op string Operation type to check for ("set", "append", "remove", "prepend")
---@param path string Dot-delimited canonical path
---@param value? any If provided, also match the op's value (for item-level checks)
---@return boolean
function M.layer_has_op(layer, bufnr, op, path, value)
  local ops_array
  if layer == M.LAYERS.FRONTMATTER then
    assert(bufnr ~= nil, "bufnr is required for FRONTMATTER layer")
    ops_array = buffer_ops[bufnr]
  else
    ops_array = global_ops[layer]
  end
  for _, entry in ipairs(ops_array or {}) do
    if entry.op == op and entry.path == path then
      if value == nil or entry.value == value then
        return true
      end
    end
  end
  return false
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

-- ---------------------------------------------------------------------------
-- Coerce context
-- ---------------------------------------------------------------------------

--- Build a coerce context for value transformers.
--- When bufnr is provided, resolution includes that buffer's frontmatter layer.
--- is_list_fn is called per path to determine list vs scalar resolution semantics;
--- when nil, all paths resolve as scalar (safe for contexts without schema access).
--- Used by the write proxy (at write time), finalize (at setup time), and
--- coerce_frontmatter (per-buffer, after frontmatter evaluation).
---@param bufnr integer? Buffer number for per-buffer resolution; nil for global-only
---@param is_list_fn? fun(path: string): boolean Per-path list classifier from the schema
---@return flemma.config.CoerceContext
function M.make_coerce_context(bufnr, is_list_fn)
  ---@type flemma.config.CoerceContext
  return {
    get = function(path)
      local is_list = is_list_fn and is_list_fn(path) or false
      return M.resolve(path, bufnr, { is_list = is_list })
    end,
  }
end

return M
