--- Shared registry utilities
--- Provides the canonical type contract and name validation shared by all registries.
--- NOT a base class — each registry remains self-contained. This module provides
--- DRY utilities and a type annotation that documents the expected API surface.
---@class flemma.utilities.Registry
local M = {}

local loader = require("flemma.loader")

--- Canonical registry contract.
--- Every registry in Flemma should implement this interface. The type parameter T
--- represents the stored value type (e.g., ToolDefinition, BackendEntry).
--- Domain-specific methods (get_capabilities, is_executable, etc.) live on the
--- individual registry modules — this contract covers only the shared CRUD surface.
---@class flemma.Registry
---@field register fun(name: string, definition: any) Store a named entry
---@field unregister fun(name: string): boolean Remove an entry by name; returns true if found
---@field get fun(name: string): any Retrieve an entry by name, or nil
---@field get_all fun(): any Get all entries (returns a copy)
---@field has fun(name: string): boolean Check if an entry exists
---@field clear fun() Remove all entries
---@field count fun(): integer Get the number of entries

--- Validate a registry entry name: must not contain dots (which indicate module paths).
--- Throws with a descriptive error on failure.
---@param name string The name to validate
---@param registry_label string Human-readable label for error messages (e.g., "tool", "sandbox backend")
function M.validate_name(name, registry_label)
  if loader.is_module_path(name) then
    error(
      string.format("flemma: %s name '%s' must not contain dots (dots indicate module paths)", registry_label, name),
      3
    )
  end
end

return M
