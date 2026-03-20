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

--- The originating buffer number.
--- Set on eval environments so that buffer-specific operations (e.g.,
--- personality environment caching) resolve against the correct buffer
--- rather than falling back to nvim_get_current_buf(). Threaded as an
--- explicit parameter through pipeline → processor → eval, not stored
--- on Context (which is a portable document identity, not a runtime handle).
---@type table
M.BUFFER_NUMBER = {}

--- User-defined variables from frontmatter execution.
--- Carried on Context objects; merged into the eval environment as top-level
--- keys so expressions can reference them directly.
---@type table
M.VARIABLES = {}

--- Generic diagnostics collector for eval-phase producers.
--- Initialized as an empty array on eval environments by the processor before
--- evaluation. Any code running in the eval environment (include(), expressions)
--- can push diagnostic tables into it. The processor drains the array after
--- evaluation and merges entries into the result diagnostics.
---@type table
M.DIAGNOSTICS = {}

--- Include binary mode flag.
--- Used as a table key in include() opts to request binary (raw bytes) mode.
--- Exposed in the template environment via `symbols.BINARY` so template code
--- can write `include('file.png', { [symbols.BINARY] = true })`.
---@type table
M.INCLUDE_BINARY = {}

--- Include MIME override.
--- Used as a table key in include() opts to override auto-detected MIME type.
--- Exposed in the template environment via `symbols.MIME` so template code
--- can write `include('data.bin', { [symbols.BINARY] = true, [symbols.MIME] = 'text/csv' })`.
---@type table
M.INCLUDE_MIME = {}

--- Schema alias map.
--- Used as a table key in s.object() fields to define alias redirections.
--- Alias values are strings referencing canonical paths (may contain dots).
--- Resolution order: real field > alias > DISCOVER callback > validation error.
---@type table
M.ALIASES = {}

--- Lazy schema resolver callback.
--- Used as a table key in s.object() fields to define a discovery callback
--- for unknown keys. The callback receives the key and returns a schema node
--- (cached after first resolution) or nil (triggers validation error).
--- Eliminates passthrough mode — every write is validated, even for dynamically
--- registered providers and tools.
---@type table
M.DISCOVER = {}

--- Clear operation on write proxies.
--- Used as the key for the clear method on config write proxies, avoiding any
--- collision with string-keyed config field names.
---@type table
M.CLEAR = {}

--- Deep-copy a table while preserving symbol key identity.
---
--- vim.deepcopy copies table *keys* by value, creating new table references
--- for keys that are tables. Since symbols ARE table references used as keys,
--- vim.deepcopy would produce a copy where symbol lookups silently fail —
--- the data is there under a different (cloned) key, but symbols.X won't find it.
---
--- This function iterates the source and copies each entry using the original
--- key reference. Table values are deep-copied via vim.deepcopy to prevent
--- aliasing; primitive values are copied directly.
---@param source table The table to clone
---@return table clone A deep copy with symbol key identity preserved
function M.deepcopy(source)
  local clone = {}
  for k, v in pairs(source) do
    if type(v) == "table" then
      clone[k] = vim.deepcopy(v)
    else
      clone[k] = v
    end
  end
  return clone
end

return M
