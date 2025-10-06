--- Context creation utilities for Flemma
--- Provides unified context objects used by both @./file references and include() expressions

---@class Context
---@field __filename string|nil The absolute path to the current buffer/file
---@field __include_stack string[]|nil Stack of included files for circular reference detection

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

return M
