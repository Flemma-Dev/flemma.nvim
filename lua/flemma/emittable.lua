--- Emit protocol for structured expression results in Flemma
---
--- Provides EmitContext (builder for collecting parts from emittable objects),
--- IncludePart constructors (binary and composite), and protocol detection.

---@class flemma.Emittable
local M = {}

--- Check whether a value implements the emit protocol (duck-typed).
---@param value any
---@return boolean
function M.is_emittable(value)
  return type(value) == "table" and type(value.emit) == "function"
end

-- EmitContext ----------------------------------------------------------------

---@class flemma.emittable.EmitContext
---@field parts flemma.processor.EvaluatedPart[]
---@field position flemma.ast.Position|nil
---@field diagnostics flemma.ast.Diagnostic[]|nil
---@field source_file string|nil
local EmitContext = {}
EmitContext.__index = EmitContext

---Create a new EmitContext.
---@param opts? {position?: flemma.ast.Position, diagnostics?: flemma.ast.Diagnostic[], source_file?: string}
---@return flemma.emittable.EmitContext
function EmitContext.new(opts)
  opts = opts or {}
  local self = setmetatable({}, EmitContext)
  self.parts = {}
  self.position = opts.position
  self.diagnostics = opts.diagnostics
  self.source_file = opts.source_file
  return self
end

---Emit a text part. No-op for nil or empty strings.
---@param str string|nil
function EmitContext:text(str)
  if str and #str > 0 then
    table.insert(self.parts, { kind = "text", text = str })
  end
end

---Emit a file part.
---@param filename string Resolved file path
---@param mime_type string Detected or overridden MIME type
---@param data string Raw binary file content
function EmitContext:file(filename, mime_type, data)
  table.insert(self.parts, {
    kind = "file",
    filename = filename,
    mime_type = mime_type,
    data = data,
    position = self.position,
  })
end

---Recursive dispatch: if value is emittable call its emit(), otherwise emit as text.
---@param value any
function EmitContext:emit(value)
  if M.is_emittable(value) then
    value:emit(self)
  elseif value ~= nil then
    self:text(tostring(value))
  end
end

---Append a diagnostic entry.
---@param diag flemma.ast.Diagnostic
function EmitContext:diagnostic(diag)
  if self.diagnostics then
    table.insert(self.diagnostics, diag)
  end
end

M.EmitContext = EmitContext

-- IncludePart constructors ---------------------------------------------------

---Create a binary IncludePart (emits a single file part).
---@param filename string Resolved absolute file path
---@param mime_type string Detected or overridden MIME type
---@param data string Raw binary file content
---@return table emittable A table with an emit(self, ctx) method
function M.binary_include_part(filename, mime_type, data)
  return {
    _filename = filename,
    _mime_type = mime_type,
    _data = data,
    ---@param self table
    ---@param ctx flemma.emittable.EmitContext
    emit = function(self, ctx)
      ctx:file(self._filename, self._mime_type, self._data)
    end,
  }
end

---Create a composite IncludePart (emits children in order).
---Children may be strings or emittable tables.
---@param children any[] Array of strings or emittable tables
---@return table emittable A table with an emit(self, ctx) method
function M.composite_include_part(children)
  return {
    _children = children,
    ---@param self table
    ---@param ctx flemma.emittable.EmitContext
    emit = function(self, ctx)
      for _, child in ipairs(self._children) do
        ctx:emit(child)
      end
    end,
  }
end

return M
