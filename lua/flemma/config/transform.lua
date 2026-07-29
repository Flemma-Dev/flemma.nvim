--- Write-transform expansion for the config store.
---
--- Runs a schema node's `:transform` hook, collecting decomposed writes
--- through a flemma.schema.TransformContext whose paths resolve RELATIVE to
--- the parent object of the transformed field (schema nodes are
--- position-independent; absolute paths would leak nested writes into global
--- config). `expand()` hands each collected op to the calling write site's own
--- applier under the expansion flag, so outputs are terminal — a write
--- produced by a transform is never re-transformed.
---
--- This is an internal module. The public API lives in flemma.config.
---@class flemma.config.Transform
local M = {}

local messages = require("flemma.messages")
local readiness = require("flemma.readiness")
local store = require("flemma.config.store")

--- Re-entrancy flag: true while transform ops are being applied, so write
--- sites skip `has_transform()` and record outputs terminally.
local expanding = false

---@class flemma.config.transform.Op
---@field path string Absolute dot-delimited config path
---@field value any Decomposed value (vim.NIL marks an explicit clear)

--- Build the context handed to a `:transform` hook, collecting ops into `ops`.
--- Mirrors store.make_coerce_context(): the transform context is the coerce
--- context plus `set`, so coerce functions — which receive the plain coerce
--- context — cannot emit by construction.
---@param base string Parent path of the transformed field ("" at root)
---@param bufnr integer?
---@param ops flemma.config.transform.Op[]
---@return flemma.schema.TransformContext
local function make_transform_context(base, bufnr, ops)
  ---@param path string
  ---@return string
  local function join(path)
    if base == "" then
      return path
    end
    return base .. "." .. path
  end
  ---@type flemma.schema.TransformContext
  return {
    -- Buffer-aware read — a value written earlier in the same frontmatter
    -- evaluation is visible, unlike the global-only coerce context.
    get = function(path)
      return store.resolve(join(path), bufnr, {})
    end,
    set = function(path, value)
      ops[#ops + 1] = { path = join(path), value = value }
    end,
  }
end

--- Whether transform ops are currently being applied. Write sites check this
--- before consulting `has_transform()` so outputs are terminal (cycle-safe).
---@return boolean
function M.is_expanding()
  return expanding
end

--- Run a node's transform for a write at `canonical`, returning the collected
--- ops with absolute paths. Does not touch the store.
---@param leaf flemma.schema.Node Node carrying the transform (wrappers delegate)
---@param canonical string Canonical dot-delimited path of the field being written
---@param value any The raw written value
---@param bufnr integer?
---@return flemma.config.transform.Op[]
function M.run(leaf, canonical, value, bufnr)
  local base = canonical:match("^(.+)%.[^.]+$") or ""
  local ops = {}
  leaf:apply_transform(value, make_transform_context(base, bufnr, ops))
  return ops
end

--- Expand a transformed write: run the node's transform and hand every
--- collected op to `apply` under the expansion flag. vim.NIL op values are
--- converted to real nil at the apply boundary (explicit clear).
---
--- Expansion is not atomic: a failing op leaves earlier ops applied, per the
--- calling site's failure semantics — transforms emit their riskiest ops first
--- (see registry.model_transform) so a failure applies as little as possible.
---
--- The pcall exists to restore the flag and contextualize op failures with the
--- original written value; suspense sentinels are re-raised unchanged so
--- readiness boundaries keep working through expansion (lint-pcall-rethrow
--- discipline).
---@param leaf flemma.schema.Node Node carrying the transform (wrappers delegate)
---@param canonical string Canonical dot-delimited path of the field being written
---@param value any The raw written value
---@param bufnr integer?
---@param apply fun(path: string, value: any) Site-specific op applier (may raise)
---@return true|nil ok, string|nil err Contextualized failure message on nil
function M.expand(leaf, canonical, value, bufnr, apply)
  local ops = M.run(leaf, canonical, value, bufnr)
  local previous = expanding
  expanding = true
  local ok, err = pcall(function()
    for _, op in ipairs(ops) do
      local op_value = op.value
      if op_value == vim.NIL then
        op_value = nil
      end
      apply(op.path, op_value)
    end
  end)
  expanding = previous
  if ok then
    return true
  end
  if readiness.is_suspense(err) then
    error(err, 0)
  end
  local detail = type(err) == "table" and err.error or err
  return nil,
    tostring(messages["ui.config.transform_expand_failed"]{
      value = tostring(value),
      detail = tostring(detail),
    })
end

return M
