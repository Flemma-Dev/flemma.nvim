--- AST module barrel
--- Re-exports nodes (types + constructors) and query (traversal helpers).
--- require("flemma.ast") returns the full API.
---
--- NOTE: dump is exported lazily via metatable to break the circular dependency:
--- ast barrel imports dump, dump imports parser, parser imports ast barrel.
---@class flemma.Ast : flemma.ast.Nodes, flemma.ast.Query
---@field dump flemma.ast.Dump
local nodes = require("flemma.ast.nodes")
local query = require("flemma.ast.query")

---@type flemma.Ast
local M = vim.tbl_extend("error", {}, nodes, query)

-- Lazy export of dump module via metatable __index to break circular dependency.
-- dump is not required at top level; instead, it's loaded on first access via M.dump.
local dump_cache = nil
setmetatable(M, {
  __index = function(_, key)
    if key == "dump" then
      if not dump_cache then
        dump_cache = require("flemma.ast.dump")
      end
      return dump_cache
    end
    return nil
  end,
})

return M
