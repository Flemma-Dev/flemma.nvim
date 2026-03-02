--- Shared role name mapping utilities
--- Centralizes the conversion between buffer-format role names ("You", "Assistant", "System")
--- and internal config keys ("user", "assistant", "system"), plus highlight group name construction.
---@class flemma.Roles
local M = {}

--- Buffer-format role name constants
M.YOU = "You"
M.ASSISTANT = "Assistant"
M.SYSTEM = "System"

---@type table<string, string>
local ROLE_KEYS = {
  You = "user",
  Assistant = "assistant",
  System = "system",
}

--- Map a buffer-format role name to its config/internal key.
--- "You" → "user", "Assistant" → "assistant", "System" → "system"
---@param role string Buffer-format role name
---@return string
function M.to_key(role)
  return ROLE_KEYS[role] or string.lower(role)
end

--- Check if a role represents a user message.
---@param role string Buffer-format role name
---@return boolean
function M.is_user(role)
  return role == "You"
end

--- Capitalize a config key for use in highlight group name construction.
--- "user" → "User", "assistant" → "Assistant"
---@param key string
---@return string
function M.capitalize(key)
  return key:sub(1, 1):upper() .. key:sub(2)
end

--- Build a highlight group name from a prefix and a buffer-format role name.
--- ("FlemmaRole", "You") → "FlemmaRoleUser"
--- ("FlemmaLine", "Assistant") → "FlemmaLineAssistant"
---@param prefix string Highlight group prefix (e.g., "FlemmaRole", "FlemmaLine")
---@param role string Buffer-format role name
---@return string
function M.highlight_group(prefix, role)
  return prefix .. M.capitalize(M.to_key(role))
end

return M
