--- AST module barrel
--- Re-exports nodes (types + constructors) and query (traversal helpers).
--- require("flemma.ast") returns the full API.
---@class flemma.Ast : flemma.ast.Nodes, flemma.ast.Query
local nodes = require("flemma.ast.nodes")
local query = require("flemma.ast.query")

---@type flemma.Ast
local M = vim.tbl_extend("error", {}, nodes, query)

return M
