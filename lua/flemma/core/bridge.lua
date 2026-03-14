--- Bridge for core functions called by modules that cannot require
--- core directly due to circular dependencies.
---
--- INTERNAL: This module exists solely to break circular dependencies between
--- core.lua and modules that core requires at the top level (autopilot,
--- executor, ui). These modules need to call core functions but cannot require
--- core directly without creating a circular dependency.
---
--- DO NOT use this module from other code. Require flemma.core directly
--- instead — this bridge is only for modules that would create a circular
--- dependency with core.
---
--- Registered by: flemma.core (at module init, after all functions are defined)
--- Called by: flemma.autopilot, flemma.tools.executor, flemma.ui
---@class flemma.core.Bridge
local M = {}

---@type table<string, function>
local handlers = {}

---Register a core bridge function. Only called by flemma.core.
---@param name string Function name ("send_or_execute", "cancel_request", "update_ui")
---@param fn function The core function to dispatch to
function M.register(name, fn)
  handlers[name] = fn
end

---Dispatch send_or_execute. Prefer requiring flemma.core directly
---unless that would create a circular dependency.
---@param opts { bufnr: integer }
function M.send_or_execute(opts)
  assert(handlers.send_or_execute, "core.bridge: send_or_execute not registered (core not loaded?)")
  handlers.send_or_execute(opts)
end

---Dispatch cancel_request. Prefer requiring flemma.core directly
---unless that would create a circular dependency.
---@param opts? { bufnr: integer }
function M.cancel_request(opts)
  assert(handlers.cancel_request, "core.bridge: cancel_request not registered (core not loaded?)")
  handlers.cancel_request(opts)
end

---Dispatch update_ui. Prefer requiring flemma.core directly
---unless that would create a circular dependency.
---@param bufnr integer
function M.update_ui(bufnr)
  assert(handlers.update_ui, "core.bridge: update_ui not registered (core not loaded?)")
  handlers.update_ui(bufnr)
end

return M
