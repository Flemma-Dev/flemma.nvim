--- Tool name encoding for the wire (LLM API) boundary.
---
--- Flemma uses `.` as a human-readable namespace separator in tool names
--- (e.g., `slack.channels_list`). LLM APIs restrict tool names to
--- `[a-zA-Z0-9_-]+`, so dots are encoded to a wire separator before
--- sending and decoded back when receiving.
---@class flemma.utilities.Tools
local M = {}

local string_utils = require("flemma.utilities.string")

--- Wire separator used by LLM APIs.
---@type string
M.WIRE_SEPARATOR = "__"

--- Internal separator used in Flemma tool names.
---@type string
M.INTERNAL_SEPARATOR = "."

---Encode a tool name for the wire (LLM API): replace internal separator with `__`.
---Names without the separator pass through unchanged.
---@param name string
---@return string
function M.encode_tool_name(name)
  return (name:gsub(string_utils.escape_pattern(M.INTERNAL_SEPARATOR), M.WIRE_SEPARATOR))
end

---Decode a tool name from the wire (LLM API): replace `__` with `.`.
---Names without `__` pass through unchanged.
---@param name string
---@return string
function M.decode_tool_name(name)
  return (name:gsub(M.WIRE_SEPARATOR, M.INTERNAL_SEPARATOR))
end

return M
