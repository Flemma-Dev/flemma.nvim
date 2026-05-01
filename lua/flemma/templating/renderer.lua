--- Shared Lua-template renderer facade.
---
--- This module owns string-template parsing/compilation orchestration. It does
--- not cache globally; callers that need reuse should retain the function
--- returned by compile().
---@class flemma.templating.Renderer
local M = {}

local compiler = require("flemma.templating.compiler")
local parser = require("flemma.templating.parser")

---@alias flemma.templating.RenderFunction fun(env: table): table[], table[]

---Compile already-parsed segments into a reusable render function.
---@param segments flemma.ast.Segment[]
---@return flemma.templating.RenderFunction render
---@return flemma.templating.compiler.CompilationResult result
function M.compile_segments(segments)
  local result = compiler.compile(segments)
  ---@param env table
  ---@return table[] parts
  ---@return table[] diagnostics
  local function render(env)
    return compiler.execute(result, env)
  end
  return render, result
end

---Compile a Lua template string into a reusable render function.
---@param template string
---@return flemma.templating.RenderFunction render
---@return flemma.templating.compiler.CompilationResult result
function M.compile(template)
  return M.compile_segments(parser.parse_segments(template, 1))
end

---Render already-parsed segments once without caller-owned caching.
---@param segments flemma.ast.Segment[]
---@param env table
---@return table[] parts
---@return table[] diagnostics
function M.render_segments(segments, env)
  local render = M.compile_segments(segments)
  return render(env)
end

---Render a Lua template string once without caller-owned caching.
---@param template string
---@param env table
---@return table[] parts
---@return table[] diagnostics
function M.render(template, env)
  local render = M.compile(template)
  return render(env)
end

---Join text parts produced by the renderer.
---@param parts table[]
---@return string
function M.parts_to_text(parts)
  local text = {}
  for _, part in ipairs(parts) do
    if part.kind == "text" then
      text[#text + 1] = part.text or ""
    end
  end
  return table.concat(text)
end

return M
