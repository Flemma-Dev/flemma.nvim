---@class flemma.Ast
local M = {}

---@class flemma.ast.Position
---@field start_line integer
---@field end_line? integer
---@field start_col? integer

---@class flemma.ast.DocumentNode
---@field kind "document"
---@field frontmatter flemma.ast.FrontmatterNode|nil
---@field messages flemma.ast.MessageNode[]
---@field errors flemma.ast.Diagnostic[]
---@field position flemma.ast.Position

---@class flemma.ast.FrontmatterNode
---@field kind "frontmatter"
---@field language string
---@field code string
---@field position flemma.ast.Position

---@class flemma.ast.MessageNode
---@field kind "message"
---@field role "You"|"Assistant"|"System"
---@field segments flemma.ast.Segment[]
---@field position flemma.ast.Position

---@class flemma.ast.TextSegment
---@field kind "text"
---@field value string

---@class flemma.ast.ExpressionSegment
---@field kind "expression"
---@field code string
---@field position flemma.ast.Position|nil

---@class flemma.ast.ThinkingSegment : flemma.ast.GenericThinkingPart
---@field position flemma.ast.Position

---@class flemma.ast.ToolUseSegment : flemma.ast.GenericToolUsePart
---@field position flemma.ast.Position

---@class flemma.ast.ToolResultSegment : flemma.ast.GenericToolResultPart
---@field position flemma.ast.Position

---@alias flemma.ast.Segment flemma.ast.TextSegment|flemma.ast.ExpressionSegment|flemma.ast.ThinkingSegment|flemma.ast.ToolUseSegment|flemma.ast.ToolResultSegment

---@class flemma.ast.Diagnostic
---@field type "frontmatter"|"expression"|"file"|"tool_use"|"parse"
---@field severity "error"|"warning"
---@field error? string
---@field position? flemma.ast.Position
---@field language? string
---@field expression? string
---@field filename? string
---@field raw? string
---@field message_role? string
---@field source_file? string

---@class flemma.ast.GenericTextPart
---@field kind "text"
---@field text string

---@class flemma.ast.GenericBinaryPart
---@field mime_type string
---@field data string
---@field data_url string
---@field filename string

---@class flemma.ast.GenericImagePart : flemma.ast.GenericBinaryPart
---@field kind "image"

---@class flemma.ast.GenericPdfPart : flemma.ast.GenericBinaryPart
---@field kind "pdf"

---@class flemma.ast.GenericTextFilePart
---@field kind "text_file"
---@field mime_type string
---@field text string
---@field filename string

---@class flemma.ast.GenericUnsupportedFilePart
---@field kind "unsupported_file"
---@field filename? string

---@class flemma.ast.GenericThinkingPart
---@field kind "thinking"
---@field content string
---@field signature? string

---@class flemma.ast.GenericToolUsePart
---@field kind "tool_use"
---@field id string
---@field name string
---@field input table<string, any>

---@class flemma.ast.GenericToolResultPart
---@field kind "tool_result"
---@field tool_use_id string
---@field content string
---@field is_error boolean

---@alias flemma.ast.GenericPart flemma.ast.GenericTextPart|flemma.ast.GenericImagePart|flemma.ast.GenericPdfPart|flemma.ast.GenericTextFilePart|flemma.ast.GenericUnsupportedFilePart|flemma.ast.GenericThinkingPart|flemma.ast.GenericToolUsePart|flemma.ast.GenericToolResultPart

--- Constructors for AST nodes. Positions are 1-based line/column.

---@param frontmatter flemma.ast.FrontmatterNode|nil
---@param messages flemma.ast.MessageNode[]|nil
---@param errors flemma.ast.Diagnostic[]|nil
---@param pos flemma.ast.Position
---@return flemma.ast.DocumentNode
function M.document(frontmatter, messages, errors, pos)
  return {
    kind = "document",
    frontmatter = frontmatter,
    messages = messages or {},
    errors = errors or {},
    position = pos,
  }
end

---@param language string
---@param code string
---@param pos flemma.ast.Position
---@return flemma.ast.FrontmatterNode
function M.frontmatter(language, code, pos)
  return { kind = "frontmatter", language = language, code = code, position = pos }
end

---@param role "You"|"Assistant"|"System"
---@param segments flemma.ast.Segment[]|nil
---@param pos flemma.ast.Position
---@return flemma.ast.MessageNode
function M.message(role, segments, pos)
  return { kind = "message", role = role, segments = segments or {}, position = pos }
end

---@param value string
---@return flemma.ast.TextSegment
function M.text(value)
  return { kind = "text", value = value }
end

---@param code string
---@param pos flemma.ast.Position|nil
---@return flemma.ast.ExpressionSegment
function M.expression(code, pos)
  return { kind = "expression", code = code, position = pos }
end

---@param content string
---@param pos flemma.ast.Position
---@param signature string|nil
---@return flemma.ast.ThinkingSegment
function M.thinking(content, pos, signature)
  return { kind = "thinking", content = content, position = pos, signature = signature }
end

---@param id string
---@param name string
---@param input table<string, any>
---@param pos flemma.ast.Position
---@return flemma.ast.ToolUseSegment
function M.tool_use(id, name, input, pos)
  return {
    kind = "tool_use",
    id = id,
    name = name,
    input = input,
    position = pos,
  }
end

---@param tool_use_id string
---@param content string
---@param is_error boolean|nil
---@param pos flemma.ast.Position
---@return flemma.ast.ToolResultSegment
function M.tool_result(tool_use_id, content, is_error, pos)
  return {
    kind = "tool_result",
    tool_use_id = tool_use_id,
    content = content,
    is_error = is_error or false,
    position = pos,
  }
end

--- Evaluated message parts -> GenericPart[], diagnostics[]
--- Returns both the generic parts and any diagnostics generated during conversion
---@param evaluated_parts flemma.processor.EvaluatedPart[]|nil
---@param source_file string|nil
---@return flemma.ast.GenericPart[] parts
---@return flemma.ast.Diagnostic[] diagnostics
function M.to_generic_parts(evaluated_parts, source_file)
  local parts = {}
  local diagnostics = {}
  for _, p in ipairs(evaluated_parts or {}) do
    if p.kind == "text" then
      if p.text and #p.text > 0 then
        table.insert(parts, { kind = "text", text = p.text })
      end
    elseif p.kind == "file" then
      local mt = p.mime_type or ""
      if mt:sub(1, 6) == "image/" then
        local encoded = vim.base64.encode(p.data or "")
        table.insert(parts, {
          kind = "image",
          mime_type = mt,
          data = encoded,
          data_url = "data:" .. mt .. ";base64," .. encoded,
          filename = p.filename,
        })
      elseif mt == "application/pdf" then
        local encoded = vim.base64.encode(p.data or "")
        table.insert(parts, {
          kind = "pdf",
          mime_type = mt,
          data = encoded,
          data_url = "data:application/pdf;base64," .. encoded,
          filename = p.filename,
        })
      elseif mt:sub(1, 5) == "text/" then
        table.insert(parts, {
          kind = "text_file",
          mime_type = mt,
          text = p.data, -- treat as text content
          filename = p.filename,
        })
      else
        -- Unsupported file type - emit diagnostic
        local err = "Unsupported MIME type: " .. mt
        table.insert(diagnostics, {
          type = "file",
          severity = "warning",
          filename = p.filename,
          error = err,
          position = p.position,
          source_file = source_file or "N/A",
        })
        table.insert(parts, { kind = "unsupported_file", filename = p.filename })
      end
    elseif p.kind == "thinking" then
      -- Preserve thinking nodes with signature for provider state preservation
      table.insert(parts, {
        kind = "thinking",
        content = p.content,
        signature = p.signature,
      })
    elseif p.kind == "tool_use" then
      table.insert(parts, {
        kind = "tool_use",
        id = p.id,
        name = p.name,
        input = p.input,
      })
    elseif p.kind == "tool_result" then
      table.insert(parts, {
        kind = "tool_result",
        tool_use_id = p.tool_use_id,
        content = p.content,
        is_error = p.is_error,
      })
    end
  end
  return parts, diagnostics
end

return M
