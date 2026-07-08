--- Write-transform expansion for the config store.
---
--- Runs a schema node's `:transform` hook, collecting explicit ops through a
--- TransformContext whose paths resolve RELATIVE to the parent object of the
--- transformed field (schema nodes are position-independent; absolute paths
--- would leak nested writes into global config). Write sites (proxy,
--- config.apply, JSON operators) apply the returned ops through their own
--- recursion under `guard()`, which prevents re-transformation of outputs.
---
--- This is an internal module. The public API lives in flemma.config.
---@class flemma.config.Transform
local M = {}

local readiness = require("flemma.readiness")
local store = require("flemma.config.store")

--- Re-entrancy flag: true while transform ops are being applied, so write
--- sites skip `has_transform()` and record outputs terminally.
local expanding = false

---@class flemma.config.transform.Op
---@field op "$set"|"$append"|"$prepend"|"$remove"
---@field path string Absolute dot-delimited config path
---@field value any

--- Write-capable context handed to `:transform` hooks. Reads and writes both
--- resolve relative to the transformed field's parent object; there is no
--- root escape hatch by design.
---@class flemma.config.TransformContext
---@field private _base string Parent path of the transformed field ("" at root)
---@field private _bufnr integer?
---@field _ops flemma.config.transform.Op[] Accessed by M.run() to read back collected ops after apply_transform
local TransformContext = {}
TransformContext.__index = TransformContext

---@param base string
---@param bufnr integer?
---@return flemma.config.TransformContext
function TransformContext.new(base, bufnr)
  return setmetatable({ _base = base, _bufnr = bufnr, _ops = {} }, TransformContext)
end

---@private
---@param path string
---@return string
function TransformContext:_join(path)
  if self._base == "" then
    return path
  end
  return self._base .. "." .. path
end

--- Resolve a config path (relative to the field's parent), buffer-aware —
--- a value written earlier in the same frontmatter evaluation is visible.
---@param path string
---@return any
function TransformContext:get(path)
  return store.resolve(self:_join(path), self._bufnr, {})
end

---@param path string
---@param value any
---@return flemma.config.TransformContext self
function TransformContext:set(path, value)
  self._ops[#self._ops + 1] = { op = "$set", path = self:_join(path), value = value }
  return self
end

---@param path string
---@param value any
---@return flemma.config.TransformContext self
function TransformContext:append(path, value)
  self._ops[#self._ops + 1] = { op = "$append", path = self:_join(path), value = value }
  return self
end

---@param path string
---@param value any
---@return flemma.config.TransformContext self
function TransformContext:prepend(path, value)
  self._ops[#self._ops + 1] = { op = "$prepend", path = self:_join(path), value = value }
  return self
end

---@param path string
---@param value any
---@return flemma.config.TransformContext self
function TransformContext:remove(path, value)
  self._ops[#self._ops + 1] = { op = "$remove", path = self:_join(path), value = value }
  return self
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
  local ctx = TransformContext.new(base, bufnr)
  leaf:apply_transform(value, ctx)
  return ctx._ops
end

--- Apply `fn` with the expansion flag set, restoring it on every exit path.
--- The pcall exists ONLY to restore the flag; every error — suspense sentinels
--- included — is re-raised unchanged (lint-pcall-rethrow discipline).
---@param fn fun()
function M.guard(fn)
  expanding = true
  local ok, err = pcall(fn)
  expanding = false
  if not ok then
    if readiness.is_suspense(err) then
      error(err, 0)
    end
    error(err, 0)
  end
end

return M
