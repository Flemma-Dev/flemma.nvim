--- Context creation utilities for Flemma
--- Provides unified context objects used by both @./file references and include() expressions

---@class Context
---@field __include_stack string[]|nil Stack of included files for circular reference detection (private)
---@field __variables table<string, any>|nil User-defined variables for execution contexts (private)

local M = {}

-- Context metatable with methods
local Context = {}
Context.__index = Context

---Get the current filename (top of include stack)
---@return string|nil filename The current file path
function Context:get_filename()
  local stack = self.__include_stack
  return stack and stack[#stack] or nil
end

---Get a copy of the include stack
---@return string[] stack Copy of the include stack
function Context:get_include_stack()
  local stack = self.__include_stack or {}
  return vim.list_extend({}, stack)
end

---Get a copy of the variables
---@return table<string, any> variables Copy of the variables
function Context:get_variables()
  return vim.deepcopy(self.__variables or {})
end

---Create a context object from a buffer number
---
---This context is used for resolving relative file paths in both @./file references
---and include() expressions, providing a unified pattern across the codebase.
---
---@param bufnr number The buffer number
---@return Context context The context object
function M.from_buffer(bufnr)
  local context = setmetatable({}, Context)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr)

  if buffer_name ~= "" then
    context.__include_stack = { buffer_name }
  end

  return context
end

---Create a context object from a file path
---
---Used when you have a file path directly (e.g., in frontmatter execution for tests)
---
---@param file_path string The file path
---@return Context context The context object
function M.from_file(file_path)
  local context = setmetatable({}, Context)

  if file_path and file_path ~= "" then
    context.__include_stack = { file_path }
  end

  return context
end

---Deep clone a context object
---
---Creates a deep copy of the context, including all internal fields.
---This is used to create execution contexts that can be extended with
---user-defined variables without modifying the original context.
---
---@param context Context The context to clone
---@return Context cloned_context A deep copy of the context
function M.clone(context)
  if not context then
    return setmetatable({}, Context)
  end

  -- Use vim.deepcopy to handle all fields, including nested tables
  local cloned = vim.deepcopy(context)
  return setmetatable(cloned, Context)
end

---Extend a context with user-defined variables (returns a deep copy)
---@param base Context
---@param vars table
---@return Context
function M.extend(base, vars)
  local c = M.clone(base)
  c.__variables = c.__variables or {}
  for k, v in pairs(vars or {}) do
    c.__variables[k] = v
  end
  return c
end

---Create a new context for an included file (push to include stack)
---@param base Context
---@param child_filename string
---@return Context
function M.for_include(base, child_filename)
  local c = M.clone(base)
  c.__include_stack = vim.deepcopy(base.__include_stack or {})
  table.insert(c.__include_stack, child_filename)
  return c
end

---Prepare a safe eval environment from a Context
---@param ctx Context|table
---@return table env
function M.to_eval_env(ctx)
  local eval = require("flemma.eval")
  local env = eval.create_safe_env()

  -- Handle both Context objects and plain tables
  if ctx and type(ctx.get_filename) == "function" then
    env.__filename = ctx:get_filename()
    env.__include_stack = ctx:get_include_stack()
  else
    env.__filename = nil
    env.__include_stack = {}
  end

  -- Merge user vars
  for k, v in pairs((ctx and ctx.__variables) or {}) do
    env[k] = v
  end
  return env
end

return M
