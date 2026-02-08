--- Context creation utilities for Flemma
--- Provides unified context objects used by both @./file references and include() expressions

---@class flemma.ContextUtil
local M = {}

---@class flemma.Context
---@field __filename string|nil The current file path (private)
---@field __variables table<string, any>|nil User-defined variables for execution contexts (private)
---@field __opts flemma.opt.ResolvedOpts|nil Resolved per-buffer options from frontmatter (private)
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
    return vim.fn.fnamemodify(self.__filename, ":h")
  end
  return nil
end

---Get a copy of the variables
---@return table<string, any> variables Copy of the variables
function Context:get_variables()
  return vim.deepcopy(self.__variables or {})
end

---Get the resolved per-buffer options
---@return flemma.opt.ResolvedOpts|nil opts The resolved options, or nil if none set
function Context:get_opts()
  return self.__opts
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

  -- Use vim.deepcopy to handle all fields, including nested tables
  local cloned = vim.deepcopy(context)
  return setmetatable(cloned, Context)
end

---Extend a context with user-defined variables (returns a deep copy)
---@param base flemma.Context
---@param vars table<string, any>
---@return flemma.Context
function M.extend(base, vars)
  local c = M.clone(base)
  c.__variables = c.__variables or {}
  for k, v in pairs(vars or {}) do
    c.__variables[k] = v
  end
  return c
end

---Prepare a safe eval environment from a Context
---@param ctx flemma.Context|table
---@return flemma.eval.Environment env
function M.to_eval_env(ctx)
  local eval = require("flemma.eval")
  local env = eval.create_safe_env()

  -- Handle both Context objects and plain tables
  if ctx and type(ctx.get_filename) == "function" then
    env.__filename = ctx:get_filename()
    env.__dirname = ctx:get_dirname()
  else
    env.__filename = nil
    env.__dirname = nil
  end

  -- Merge user vars
  for k, v in pairs((ctx and ctx.__variables) or {}) do
    env[k] = v
  end
  return env
end

return M
