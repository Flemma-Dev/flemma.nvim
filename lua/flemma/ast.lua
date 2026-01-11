local M = {}

-- Constructors for AST nodes. Positions are 1-based line/column.
function M.document(frontmatter, messages, errors, pos)
  return {
    kind = "document",
    frontmatter = frontmatter,
    messages = messages or {},
    errors = errors or {},
    position = pos,
  }
end

function M.frontmatter(language, code, pos)
  return { kind = "frontmatter", language = language, code = code, position = pos }
end

function M.message(role, segments, pos)
  return { kind = "message", role = role, segments = segments or {}, position = pos }
end

function M.text(value)
  return { kind = "text", value = value }
end

function M.file_reference(raw, path, mime_override, trailing_punct, pos)
  return {
    kind = "file_reference",
    raw = raw,
    path = path,
    mime_override = mime_override,
    trailing_punct = trailing_punct,
    position = pos,
  }
end

function M.expression(code, pos)
  return { kind = "expression", code = code, position = pos }
end

function M.thinking(content, pos, signature)
  return { kind = "thinking", content = content, position = pos, signature = signature }
end

function M.tool_use(id, name, input, pos)
  return {
    kind = "tool_use",
    id = id,
    name = name,
    input = input,
    position = pos,
  }
end

function M.tool_result(tool_use_id, content, is_error, pos)
  return {
    kind = "tool_result",
    tool_use_id = tool_use_id,
    content = content,
    is_error = is_error or false,
    position = pos,
  }
end

-- Evaluated message parts -> GenericPart[], diagnostics[]
-- Returns both the generic parts and any diagnostics generated during conversion
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
          filename = p.filename or p.raw,
          raw = p.raw or p.filename,
          error = err,
          position = p.position,
          source_file = source_file or "N/A",
        })
        table.insert(parts, { kind = "unsupported_file", raw_filename = p.raw or p.filename })
      end
    elseif p.kind == "unsupported_file" then
      -- Already unsupported - emit diagnostic
      table.insert(diagnostics, {
        type = "file",
        severity = "warning",
        filename = p.raw or "unknown",
        raw = p.raw,
        error = "Unsupported file type",
        position = p.position,
        source_file = source_file or "N/A",
      })
      table.insert(parts, { kind = "unsupported_file", raw_filename = p.raw })
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
