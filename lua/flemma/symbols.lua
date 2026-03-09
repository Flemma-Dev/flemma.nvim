--- Well-known symbols for cross-module metadata tagging
---
--- Provides unique table keys (analogous to JavaScript's Symbol) for tagging
--- objects with metadata that survives serialization boundaries. Using table
--- references as keys guarantees no collision with string-keyed user data.
---
--- Usage:
---   local symbols = require("flemma.symbols")
---   obj[symbols.SOURCE_PATH] = "/path/to/file"
---   local path = obj[symbols.SOURCE_PATH]  -- retrieve later
---@class flemma.Symbols
local M = {}

--- The resolved file path that produced this value.
--- Set on emittable include parts so consumers (e.g., navigation, LSP) can
--- trace an evaluated result back to its originating file.
---@type table
M.SOURCE_PATH = {}

return M
