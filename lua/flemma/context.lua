--- Context creation utilities for Flemma
--- Provides unified context objects used by both @./file references and include() expressions

---@class flemma.ContextUtil
local M = {}

local path_util = require("flemma.utilities.path")
local symbols = require("flemma.symbols")

--- Context carries document identity: file path, frontmatter options, and user
--- variables. User-visible fields (__filename) are string keys accessible to
--- sandbox code; internal metadata uses symbol keys invisible to user expressions.
---
--- Context deliberately does NOT carry a buffer number — bufnr is a runtime
--- handle threaded as an explicit parameter through the call chain (pipeline →
--- processor → eval) rather than embedded in a portable document object.
---@class flemma.Context
---@field __filename string|nil The current file path (user-visible in eval env)
local Context = {}
Context.__index = Context

---Get the current filename
---@return string|nil filename The current file path
function Context:get_filename()
  return self.__filename
end

---Get the directory containing the current file
---@return string|nil dirname The directory path
function Context:get_dirname()
  if self.__filename then
    return path_util.dirname(self.__filename)
  end
  return nil
end

---Get a copy of the variables
---@return table<string, any> variables Copy of the variables
function Context:get_variables()
  return vim.deepcopy(self[symbols.VARIABLES] or {})
end

---Create a context object from a buffer number
---
---This context is used for resolving relative file paths in both @./file references
---and include() expressions, providing a unified pattern across the codebase.
---
---@param bufnr integer The buffer number
---@return flemma.Context context The context object
function M.from_buffer(bufnr)
  local context = setmetatable({}, Context)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr)

  if buffer_name ~= "" then
    context.__filename = buffer_name
  end

  return context
end

---Create a context object from a file path
---
---Used when you have a file path directly (e.g., in frontmatter execution for tests)
---
---@param file_path string The file path
---@return flemma.Context context The context object
function M.from_file(file_path)
  local context = setmetatable({}, Context)

  if file_path and file_path ~= "" then
    context.__filename = file_path
  end

  return context
end

---Deep clone a context object
---
---Creates a deep copy of the context, including all internal fields.
---This is used to create execution contexts that can be extended with
---user-defined variables without modifying the original context.
---
---@param context flemma.Context|nil The context to clone (nil returns empty context)
---@return flemma.Context cloned_context A deep copy of the context
function M.clone(context)
  if not context then
    return setmetatable({}, Context)
  end

  return setmetatable(symbols.deepcopy(context), Context)
end

---Extend a context with user-defined variables (returns a deep copy)
---@param base flemma.Context
---@param vars table<string, any>
---@return flemma.Context
function M.extend(base, vars)
  local c = M.clone(base)
  c[symbols.VARIABLES] = c[symbols.VARIABLES] or {}
  for k, v in pairs(vars or {}) do
    c[symbols.VARIABLES][k] = v
  end
  return c
end

return M
