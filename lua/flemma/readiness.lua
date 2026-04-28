--- Suspense + boundary registry for async/blocking work in the request pipeline.
---
--- Mirrors the shape of flemma.preprocessor.context: leaf code raises a Suspense
--- via error(Suspense.new(...)) when it would block. Orchestrators
--- (core.send_to_provider, usage.prefetch.fire_fetch) wrap their pipeline in
--- pcall, check is_suspense(err), subscribe to the boundary that the suspense
--- carries, and retry the entire pipeline on completion.
---
--- Boundaries are keyed (e.g. "secrets:vertex:access_token") and shared: two
--- consumers raising suspense on the same key both subscribe to one in-flight
--- runner. The boundary self-removes from the registry when its runner calls
--- done(), so a fresh attempt after completion creates a new one.
---@class flemma.Readiness
local M = {}

--------------------------------------------------------------------------------
-- Subscription
--------------------------------------------------------------------------------

--- One subscriber attached to a Boundary. Cancellation is cooperative:
--- :cancel() sets the cancelled flag; the boundary's completion path checks
--- the flag before invoking on_complete.
---@class flemma.readiness.Subscription
---@field cancelled boolean
---@field on_complete fun(result: any)
local Subscription = {}
Subscription.__index = Subscription

---@param on_complete fun(result: any)
---@return flemma.readiness.Subscription
function Subscription.new(on_complete)
  return setmetatable({
    cancelled = false,
    on_complete = on_complete,
  }, Subscription)
end

function Subscription:cancel()
  self.cancelled = true
end

M.Subscription = Subscription

--------------------------------------------------------------------------------
-- Boundary
--------------------------------------------------------------------------------

--- One unit of in-flight async work, identified by a string key. Concurrent
--- consumers that raise a suspense for the same key share one Boundary via the
--- registry; each gets its own Subscription.
---@class flemma.readiness.Boundary
---@field key string
---@field _status "running"|"done"
---@field _result any
---@field _subscribers flemma.readiness.Subscription[]
local Boundary = {}
Boundary.__index = Boundary

---@param key string
---@return flemma.readiness.Boundary
function Boundary._new(key)
  return setmetatable({
    key = key,
    _status = "running",
    _result = nil,
    _subscribers = {},
  }, Boundary)
end

---@param on_complete fun(result: any)
---@return flemma.readiness.Subscription
function Boundary:subscribe(on_complete)
  local sub = Subscription.new(on_complete)
  if self._status == "done" then
    vim.schedule(function()
      if not sub.cancelled then
        sub.on_complete(self._result)
      end
    end)
  else
    table.insert(self._subscribers, sub)
  end
  return sub
end

---@param result any
function Boundary:_complete(result)
  self._status = "done"
  self._result = result
  local subs = self._subscribers
  self._subscribers = {}
  for _, sub in ipairs(subs) do
    if not sub.cancelled then
      sub.on_complete(result)
    end
  end
end

M.Boundary = Boundary

--------------------------------------------------------------------------------
-- Suspense — mirrors flemma.preprocessor.context.Confirmation
--------------------------------------------------------------------------------

---@class flemma.readiness.Suspense
---@field message string
---@field boundary flemma.readiness.Boundary
---@field _is_suspense boolean
local Suspense = {}
Suspense.__index = Suspense

---@param message string Human-readable description of what is being awaited
---@param boundary flemma.readiness.Boundary
---@return flemma.readiness.Suspense
function Suspense.new(message, boundary)
  return setmetatable({
    message = message,
    boundary = boundary,
    _is_suspense = true,
  }, Suspense)
end

M.Suspense = Suspense

---@param value any
---@return boolean
function M.is_suspense(value)
  if type(value) ~= "table" then
    return false
  end
  return value._is_suspense == true
end

--------------------------------------------------------------------------------
-- Boundary registry — keyed dedup of in-flight work
--------------------------------------------------------------------------------

---@type table<string, flemma.readiness.Boundary>
local boundaries = {}

---@param key string
---@param runner fun(done: fun(result: any))
---@return flemma.readiness.Boundary
function M.get_or_create_boundary(key, runner)
  local existing = boundaries[key]
  if existing then
    return existing
  end

  local boundary = Boundary._new(key)
  boundaries[key] = boundary

  vim.schedule(function()
    local function done(result)
      if boundaries[key] ~= boundary then
        return
      end
      boundaries[key] = nil
      boundary:_complete(result)
    end

    local ok, err = pcall(runner, done)
    if not ok then
      done({
        ok = false,
        diagnostics = {
          { resolver = "readiness", message = "runner panic: " .. tostring(err) },
        },
      })
    end
  end)

  return boundary
end

function M._reset_for_tests()
  boundaries = {}
end

return M
