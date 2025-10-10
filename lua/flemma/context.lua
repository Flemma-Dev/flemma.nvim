--- Context creation utilities for Flemma
--- Provides unified context objects used by both @./file references and include() expressions

---@class Context
---@field __filename string|nil The absolute path to the current buffer/file
---@field __include_stack string[]|nil Stack of included files for circular reference detection
---@field __variables table<string, any>|nil User-defined variables for execution contexts

local M = {}

---Create a context object from a buffer number
---
---This context is used for resolving relative file paths in both @./file references
---and include() expressions, providing a unified pattern across the codebase.
---
---@param bufnr number The buffer number
---@return Context context The context object with __filename and __include_stack
function M.from_buffer(bufnr)
  local context = {}
  local buffer_name = vim.api.nvim_buf_get_name(bufnr)

  if buffer_name ~= "" then
    context.__filename = buffer_name
    context.__include_stack = { buffer_name }
  end

  return context
end

---Create a context object from a file path
---
---Used when you have a file path directly (e.g., in frontmatter execution for tests)
---
---@param file_path string The file path
---@return Context context The context object with __filename and __include_stack
function M.from_file(file_path)
  local context = {}

  if file_path and file_path ~= "" then
    context.__filename = file_path
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
    return {}
  end

  -- Use vim.deepcopy to handle all fields, including nested tables
  return vim.deepcopy(context)
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
  c.__filename = child_filename
  c.__include_stack = vim.deepcopy(base.__include_stack or {})
  table.insert(c.__include_stack, child_filename)
  return c
end

---Prepare a safe eval environment from a Context
---@param ctx Context
---@return table env
function M.to_eval_env(ctx)
  local eval = require("flemma.eval")
  local env = eval.create_safe_env()
  env.__filename = ctx.__filename
  env.__include_stack = vim.deepcopy(ctx.__include_stack or { ctx.__filename })
  -- Merge user vars
  for k, v in pairs((ctx.__variables or {})) do
    env[k] = v
  end
  return env
end

return M
