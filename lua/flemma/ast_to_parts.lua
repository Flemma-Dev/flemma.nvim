local M = {}

-- Evaluated message parts -> GenericPart[]
function M.to_generic_parts(evaluated_parts)
  local parts = {}
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
        table.insert(parts, { kind = "unsupported_file", raw_filename = p.raw or p.filename })
      end
    elseif p.kind == "unsupported_file" then
      table.insert(parts, { kind = "unsupported_file", raw_filename = p.raw })
    end
  end
  return parts
end

return M
