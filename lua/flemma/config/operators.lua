--- Operator-aware config application for JSON frontmatter.
---
--- Walks a decoded JSON table, interpreting $-prefixed keys as operations
--- ($set, $append, $remove, $prepend) and regular keys as child navigation.
--- Plain values and arrays default to "set".
---
--- This is an internal module. The public API lives in flemma.config.
---@class flemma.config.operators
local M = {}

local nav = require("flemma.config.schema.navigation")
local store = require("flemma.config.store")

--- Valid operator keys and their store operation names.
---@type table<string, "set"|"append"|"remove"|"prepend">
local OPERATORS = {
  ["$set"] = "set",
  ["$append"] = "append",
  ["$remove"] = "remove",
  ["$prepend"] = "prepend",
}

--- Record a list operation from a JSON operator value.
--- Handles both single items and arrays of items.
---@param layer integer Target layer
---@param bufnr integer? Buffer number
---@param op "append"|"remove"|"prepend" Store operation
---@param path string Canonical path
---@param value any Single item or array of items
---@param item_schema flemma.config.schema.Node? Item schema for validation
---@param failures flemma.config.ValidationFailure[] Error accumulator
local function record_list_op(layer, bufnr, op, path, value, item_schema, failures)
  local skip_validation = (op == "remove")
  local items = (type(value) == "table" and vim.islist(value)) and value or { value }
  for _, item in ipairs(items) do
    if item_schema and not skip_validation then
      local ok, err = item_schema:validate_value(item)
      if not ok then
        table.insert(failures, { path = path, value = item, message = err or "invalid" })
        goto continue
      end
    end
    store.record(layer, bufnr, op, path, item)
    ::continue::
  end
end

--- Schema-guided recursive walk with operator dispatch.
--- At each node, $-prefixed keys are dispatched as operations on the current
--- schema node, while regular keys navigate into child fields. Plain values
--- and arrays default to "set".
---@param schema flemma.config.schema.Node Root schema for navigation
---@param path string Current dot-delimited canonical path (empty for root)
---@param value any The decoded JSON value at this path
---@param layer integer Target layer
---@param bufnr integer? Buffer number
---@param failures flemma.config.ValidationFailure[] Error accumulator
local function walk(schema, path, value, layer, bufnr, failures)
  local node
  if path == "" then
    node = schema
  else
    node = nav.navigate_schema(schema, path, { unwrap_leaf = true })
  end

  if not node then
    table.insert(failures, { path = path, value = value, message = string.format("unknown config key '%s'", path) })
    return
  end

  local unwrapped = nav.unwrap_optional(node)

  -- Non-table value: try coerce for object nodes (e.g., autopilot: false →
  -- { enabled = false }), then fall through to scalar set.
  if type(value) ~= "table" then
    if unwrapped:is_object() and unwrapped:has_coerce() then
      local coerced = unwrapped:apply_coerce(value)
      if type(coerced) == "table" then
        walk(schema, path, coerced, layer, bufnr, failures)
        return
      end
    end
    local ok, err = node:validate_value(value)
    if not ok then
      table.insert(failures, { path = path, value = value, message = err or "invalid" })
      return
    end
    store.record(layer, bufnr, "set", path, value)
    return
  end

  -- Sequential table on list-capable node: list set
  if vim.islist(value) then
    if unwrapped:is_list() or unwrapped:has_list_part() then
      local item_schema = unwrapped:get_list_item_schema() or unwrapped:get_item_schema()
      if item_schema then
        for i, item in ipairs(value) do
          local ok, err = item_schema:validate_value(item)
          if not ok then
            table.insert(failures, {
              path = path,
              value = item,
              message = string.format("item[%d]: %s", i, err or "invalid"),
            })
            return
          end
        end
      end
      store.record(layer, bufnr, "set", path, value)
    else
      table.insert(failures, {
        path = path,
        value = value,
        message = string.format("'%s' does not accept array values", path),
      })
    end
    return
  end

  -- Non-sequential table: split into operators ($-prefixed) and regular keys
  ---@type table<string, any>
  local ops = {}
  ---@type table<string, any>
  local regular = {}
  for k, v in pairs(value) do
    if type(k) == "string" and k:sub(1, 1) == "$" then
      ops[k] = v
    else
      regular[k] = v
    end
  end

  -- Dispatch operators (operate on the current node)
  for op_key, op_value in pairs(ops) do
    local store_op = OPERATORS[op_key]
    if not store_op then
      table.insert(failures, {
        path = path ~= "" and path or "<root>",
        value = op_value,
        message = string.format("unknown operator '%s'", op_key),
      })
    elseif store_op == "set" then
      -- $set is a passthrough: treat op_value as a direct assignment at this path
      walk(schema, path, op_value, layer, bufnr, failures)
    else
      -- $append/$remove/$prepend: requires a list-capable node
      if not (unwrapped:is_list() or unwrapped:has_list_part()) then
        table.insert(failures, {
          path = path ~= "" and path or "<root>",
          value = op_value,
          message = string.format("'%s' requires a list-capable field", op_key),
        })
      else
        local item_schema = unwrapped:get_list_item_schema() or unwrapped:get_item_schema()
        local list_op = store_op --[[@as "append"|"remove"|"prepend"]]
        record_list_op(layer, bufnr, list_op, path, op_value, item_schema, failures)
      end
    end
  end

  -- Navigate regular keys into child schema nodes
  if next(regular) then
    if unwrapped:is_object() or path == "" then
      for k, v in pairs(regular) do
        local alias_target = unwrapped:resolve_alias(k)
        local canonical_key = alias_target or k
        local child_path = path == "" and canonical_key or (path .. "." .. canonical_key)
        walk(schema, child_path, v, layer, bufnr, failures)
      end
    else
      local first_key = next(regular)
      table.insert(failures, {
        path = path,
        value = value,
        message = string.format("cannot navigate into non-object field with key '%s'", first_key),
      })
    end
  end
end

--- Apply a table with MongoDB-style operators to the config store.
---
--- Walks a decoded JSON table, interpreting $-prefixed keys as operations and
--- regular keys as child navigation. Plain values and arrays default to "set".
---
--- Operators:
---   $set     — explicit set (same as plain value)
---   $append  — append items to a list field
---   $remove  — remove items from a list field
---   $prepend — prepend items to a list field
---
--- Coerce transforms are NOT run here — call `finalize()` after this to apply
--- coerce + deferred validation (matches the `config.apply()` convention).
---@param schema flemma.config.schema.Node Root schema for navigation
---@param layer integer Target layer (e.g., store.LAYERS.FRONTMATTER)
---@param bufnr integer? Buffer number (required for FRONTMATTER)
---@param data table The operator-annotated config table (contents of the "flemma" key)
---@return flemma.config.ValidationFailure[] failures Validation/application errors (empty when none)
function M.apply(schema, layer, bufnr, data)
  local failures = {} ---@type flemma.config.ValidationFailure[]
  walk(schema, "", data, layer, bufnr, failures)
  return failures
end

return M
