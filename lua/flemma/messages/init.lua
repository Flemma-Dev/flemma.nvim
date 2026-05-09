--- Message template registry for Flemma
--- Loads .chat templates co-located in this directory and renders them
--- through the existing templating engine with caller-supplied variables.
---@class flemma.messages
local M = {}

local log = require("flemma.logging")
local renderer = require("flemma.templating.renderer")

---@type string|nil
local base_directory = nil

---Get the base directory containing message templates.
---Resolved once from this file's location and cached.
---@return string
local function get_base_directory()
  if base_directory then
    return base_directory
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  base_directory = vim.fn.fnamemodify(source, ":h")
  return base_directory
end

---Read a template file from the messages directory.
---@param name string Template name (without extension)
---@return string content
local function read_template(name)
  local path = get_base_directory() .. "/" .. name .. ".chat"
  local file = assert(io.open(path, "r"), "messages: template not found: " .. path)
  local content = file:read("*a")
  file:close()
  return content
end

---Render a message template with variable interpolation.
---Uses the existing templating engine so templates support full `{{ expression }}`
---syntax including Lua code, not just simple variable substitution.
---@param name string Template name (without .chat extension)
---@param variables? table<string, any> Variables available as `{{ name }}` in the template
---@return string rendered Rendered template
function M.render(name, variables)
  local content = read_template(name)
  local parts, diagnostics = renderer.render(content, variables or {})
  for _, diagnostic in ipairs(diagnostics) do
    log.warn("messages: template '" .. name .. "': " .. (diagnostic.error or "unknown error"))
  end
  return vim.trim(renderer.parts_to_text(parts))
end

return M
