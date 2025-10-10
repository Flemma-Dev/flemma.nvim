local M = {}

-- Constructors for AST nodes. Positions are 1-based line/column.
function M.document(frontmatter, messages, errors, pos)
  return { kind = "document", frontmatter = frontmatter, messages = messages or {}, errors = errors or {}, position = pos }
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

function M.thinking(content, pos)
  return { kind = "thinking", content = content, position = pos }
end

return M
