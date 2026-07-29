--- Op-prefix parser for list-valued config fields.
---
--- Decomposes a mixed list of values into structured store operations.
--- Recognizes four single-character operator prefixes:
---
---   +value  → append
---   ^value  → prepend
---   !value  → remove
---   $name   → spread (resolve preset reference)
---
--- Operators are non-composable: +^bar, etc. are parse errors.
--- The $ prefix only matches lowercase names ($standard, not $HOME).
---
--- Execution rule: references ($name) are resolved first, producing
--- additional bare values and/or ops. Then, if any bare values exist,
--- a "set" is emitted. Finally, ops apply in declaration order.
--- Empty table {} means "set to empty list."
---@class flemma.config.listops
local M = {}

local bridge = require("flemma.bridge")
local log = require("flemma.logging")
local messages = require("flemma.messages")
local notify = require("flemma.notify")
local store = require("flemma.config.store")

---@type table<string, "append"|"prepend"|"remove">
local OP_PREFIXES = {
  ["+"] = "append",
  ["^"] = "prepend",
  ["!"] = "remove",
}

---@type table<string, boolean>
local ALL_PREFIX_CHARS = { ["+"] = true, ["^"] = true, ["!"] = true, ["$"] = true }

---@class flemma.config.listops.ParseResult
---@field set_items any[]? Bare values for a set op (nil when only ops/refs exist)
---@field ops { op: "append"|"prepend"|"remove", value: any }[] Ops in declaration order
---@field refs string[] $-prefixed preset references in declaration order

--- Parse a list of values into set candidates, ops, and references.
---@param items any List of values, possibly with operator prefixes
---@return flemma.config.listops.ParseResult
function M.parse(items)
  if type(items) ~= "table" then
    return { set_items = nil, ops = {}, refs = {} }
  end

  local set_items = {}
  local ops = {}
  local refs = {}

  for _, item in ipairs(items) do
    if type(item) == "string" and #item > 1 then
      local prefix = item:sub(1, 1)

      if prefix == "$" and item:sub(2, 2):match("[a-z]") then
        local second = item:sub(2, 2)
        if ALL_PREFIX_CHARS[second] then
          error(("cannot compose operator '$' with '%s' in '%s'"):format(second, item))
        end
        table.insert(refs, item)
      elseif OP_PREFIXES[prefix] then
        local value = item:sub(2)
        if #value > 0 and ALL_PREFIX_CHARS[value:sub(1, 1)] then
          error(("cannot compose operator '%s' with '%s' in '%s'"):format(prefix, value:sub(1, 1), item))
        end
        table.insert(ops, { op = OP_PREFIXES[prefix], value = value })
      else
        table.insert(set_items, item)
      end
    else
      table.insert(set_items, item)
    end
  end

  local has_bare = #set_items > 0
  local has_ops = #ops > 0
  local has_refs = #refs > 0
  local emit_set = has_bare or (not has_ops and not has_refs)

  return {
    set_items = emit_set and set_items or nil,
    ops = ops,
    refs = refs,
  }
end

--- Derive the preset field name from a config path.
--- Uses the last segment: "tools.auto_approve" → "auto_approve", "tools" → "tools".
--- Assumes preset field names don't collide across different parent paths.
---@param path string Dot-delimited canonical path
---@return string
local function field_name_from_path(path)
  local last = path:match("([^.]+)$")
  return last or path
end

--- Resolve $-prefixed preset references into their corresponding field values.
--- Each reference looks up the preset and returns the field matching field_name.
--- Unknown presets or presets without the field produce no values (silently skip).
--- Returns a second value: array of ref strings that did NOT resolve (unknown
--- preset or preset lacks the field), so callers can preserve them.
---@param refs string[] $-prefixed preset names
---@param field_name string Preset field to extract (e.g., "tools", "auto_approve")
---@return any[] resolved Concatenated raw values from all resolved presets
---@return string[] unresolved Refs that could not be resolved
function M.resolve_references(refs, field_name)
  local result = {}
  local unresolved = {}
  for _, ref in ipairs(refs) do
    local preset = bridge.get_preset(ref)
    if preset then
      local field_value = preset[field_name]
      if type(field_value) == "table" then
        log.debug(("listops: resolved %s.%s → %d values"):format(ref, field_name, #field_value))
        vim.list_extend(result, field_value)
      else
        log.debug(("listops: preset %s exists but has no '%s' field — silent skip"):format(ref, field_name))
      end
    else
      log.debug(("listops: preset %s not found — marking as unresolved"):format(ref))
      table.insert(unresolved, ref)
    end
  end
  return result, unresolved
end

--- Record parsed items (set + ops) to the store.
---@param parsed flemma.config.listops.ParseResult
---@param layer integer
---@param bufnr integer?
---@param path string
local function record_parsed(parsed, layer, bufnr, path)
  if parsed.set_items then
    store.record(layer, bufnr, "set", path, parsed.set_items)
  end
  for _, entry in ipairs(parsed.ops) do
    store.record(layer, bufnr, entry.op, path, entry.value)
  end
end

--- Parse a list with op prefixes, resolve $ references, and record the
--- resulting ops on the given store layer.
---
--- Resolution order:
--- 1. Parse items into bare values, ops, and references
--- 2. Resolve references → additional raw values (which may contain ops)
--- 3. Re-parse the combined values (bare + resolved) into final set + ops
--- 4. Record: set first (if any bare values), then ops in order
---@param layer integer Target layer (e.g., store.LAYERS.RUNTIME)
---@param bufnr integer? Buffer number (required for FRONTMATTER)
---@param path string Dot-delimited canonical path
---@param items any[] List of values, possibly with operator prefixes
function M.apply(layer, bufnr, path, items)
  local parsed = M.parse(items)

  if #parsed.refs > 0 then
    local field_name = field_name_from_path(path)
    local resolved, unresolved = M.resolve_references(parsed.refs, field_name)

    if #resolved == 0 and #unresolved == #parsed.refs then
      log.debug(("listops: all %d refs unresolved at '%s' — deferring to finalize"):format(#unresolved, path))
      if #parsed.ops == 0 then
        store.record(layer, bufnr, "set", path, items)
      else
        local deferred_set = {}
        if parsed.set_items then
          vim.list_extend(deferred_set, parsed.set_items)
        end
        vim.list_extend(deferred_set, unresolved)
        if #deferred_set > 0 then
          store.record(layer, bufnr, "set", path, deferred_set)
        end
        for _, entry in ipairs(parsed.ops) do
          store.record(layer, bufnr, entry.op, path, entry.value)
        end
      end
      return
    end

    if #resolved == 0 and #unresolved == 0 then
      log.debug(
        ("listops: all %d refs at '%s' resolved to nothing — emitting only bare values/ops"):format(
          #parsed.refs,
          path
        )
      )
      record_parsed(parsed, layer, bufnr, path)
      return
    end

    local from_refs = M.parse(resolved)

    local merged_set = {}
    if parsed.set_items then
      vim.list_extend(merged_set, parsed.set_items)
    end
    for _, ref in ipairs(unresolved) do
      table.insert(merged_set, ref)
      local suggestion = bridge.closest_match_preset(ref)
      if suggestion then
        notify.warn(messages["ui.provider.unknown_preset_suggestion"]{ preset = ref, suggestion = suggestion })
      else
        notify.warn(messages["ui.provider.unknown_preset"]{ preset = ref })
      end
    end
    if from_refs.set_items then
      vim.list_extend(merged_set, from_refs.set_items)
    end

    local merged_ops = {}
    vim.list_extend(merged_ops, parsed.ops)
    vim.list_extend(merged_ops, from_refs.ops)

    local has_bare = #merged_set > 0
    local has_ops = #merged_ops > 0

    if has_bare or not has_ops then
      store.record(layer, bufnr, "set", path, merged_set)
    end
    for _, entry in ipairs(merged_ops) do
      store.record(layer, bufnr, entry.op, path, entry.value)
    end
  else
    record_parsed(parsed, layer, bufnr, path)
  end
end

--- Check whether a list contains any op-prefixed items that need listops.
---@param items any[]
---@return boolean
local function has_ops(items)
  for _, item in ipairs(items) do
    if type(item) == "string" and #item > 1 then
      local ch = item:sub(1, 1)
      if ch == "+" or ch == "^" or ch == "!" then
        return true
      end
      if ch == "$" and item:sub(2, 2):match("[a-z]") then
        return true
      end
    end
  end
  return false
end

--- Shared routing predicate for the three user-facing write paths (proxy,
--- apply_recursive, operators). Checks "list-capable node + sequential table
--- with op-prefixed items?" and either applies listops (returning true) or
--- returns false to fall through to the original validate+set path.
--- Unprefixed lists are left to the caller so coerce and validation run normally.
---@param node flemma.schema.Node Unwrapped schema node at the target path
---@param value any The value being written
---@param layer integer Target layer
---@param bufnr integer? Buffer number
---@param path string Dot-delimited canonical path
---@return boolean handled True if listops consumed the write
function M.try_apply(node, value, layer, bufnr, path)
  if type(value) ~= "table" or not vim.islist(value) then
    return false
  end
  if not (node:is_list() or node:has_list_part()) then
    return false
  end
  if not has_ops(value) then
    return false
  end
  log.debug(("listops: try_apply intercepted list at '%s' with %d items"):format(path, #value))
  M.apply(layer, bufnr, path, value)
  return true
end

--- Check if a string value is a $-prefixed preset reference.
---@param value any
---@return boolean
local function is_ref(value)
  return type(value) == "string" and #value > 1 and value:sub(1, 1) == "$" and value:sub(2, 2):match("[a-z]") ~= nil
end

--- Expand deferred $-prefixed preset references in stored ops.
--- Called from finalize() after presets are registered. Uses dump-rebuild:
--- dumps the layer's ops, finds $-prefixed values in set op items, expands
--- each via presets.get() + parse(), builds a replacement ops array, then
--- clears and re-records.
---@param layer integer Layer to process
---@param bufnr integer? Buffer number (required for FRONTMATTER)
---@param list_paths string[] Paths that are list-capable (caller provides from schema)
function M.expand_deferred(layer, bufnr, list_paths)
  local path_set = {}
  for _, p in ipairs(list_paths) do
    path_set[p] = true
  end

  local ops = store.dump_layer(layer, bufnr)
  local changed = false

  local new_ops = {}
  for _, entry in ipairs(ops) do
    if not path_set[entry.path] then
      table.insert(new_ops, entry)
    elseif entry.op == "set" and type(entry.value) == "table" then
      local has_refs = false
      for _, item in ipairs(entry.value) do
        if is_ref(item) then
          has_refs = true
          break
        end
      end
      if not has_refs then
        table.insert(new_ops, entry)
      else
        local field_name = field_name_from_path(entry.path)
        local parsed = M.parse(entry.value)
        local resolved, unresolved_refs = M.resolve_references(parsed.refs, field_name)
        if #resolved == 0 and #unresolved_refs == #parsed.refs then
          table.insert(new_ops, entry)
          goto continue
        end
        changed = true
        local from_refs = M.parse(resolved)

        local merged_set = {}
        if parsed.set_items then
          vim.list_extend(merged_set, parsed.set_items)
        end
        for _, ref in ipairs(unresolved_refs) do
          table.insert(merged_set, ref)
          local suggestion = bridge.closest_match_preset(ref)
          local message = ("Unknown preset '%s'"):format(ref)
          if suggestion then
            message = message .. (" — did you mean '%s'?"):format(suggestion)
          end
          notify.warn(message)
        end
        if from_refs.set_items then
          vim.list_extend(merged_set, from_refs.set_items)
        end

        local merged_ops = {}
        vim.list_extend(merged_ops, parsed.ops)
        vim.list_extend(merged_ops, from_refs.ops)

        local has_bare = #merged_set > 0
        local has_ops_result = #merged_ops > 0

        if has_bare or not has_ops_result then
          table.insert(new_ops, { op = "set", path = entry.path, value = merged_set })
        end
        for _, op_entry in ipairs(merged_ops) do
          table.insert(new_ops, { op = op_entry.op, path = entry.path, value = op_entry.value })
        end
        ::continue::
      end
    elseif (entry.op == "append" or entry.op == "prepend" or entry.op == "remove") and is_ref(entry.value) then
      local field_name = field_name_from_path(entry.path)
      local resolved, unresolved_refs = M.resolve_references({ entry.value }, field_name)
      if #resolved == 0 and #unresolved_refs > 0 then
        table.insert(new_ops, entry)
      else
        changed = true
        local from_refs = M.parse(resolved)
        if from_refs.set_items then
          for _, item in ipairs(from_refs.set_items) do
            table.insert(new_ops, { op = entry.op, path = entry.path, value = item })
          end
        end
        for _, op_entry in ipairs(from_refs.ops) do
          table.insert(new_ops, { op = op_entry.op, path = entry.path, value = op_entry.value })
        end
      end
    else
      table.insert(new_ops, entry)
    end
  end

  if changed then
    log.debug(("listops: expand_deferred rebuilt layer %d — %d ops"):format(layer, #new_ops))
    store.clear(layer, bufnr)
    for _, entry in ipairs(new_ops) do
      store.record(layer, bufnr, entry.op, entry.path, entry.value)
    end
  else
    log.debug(("listops: expand_deferred found nothing to expand on layer %d"):format(layer))
  end
end

return M
