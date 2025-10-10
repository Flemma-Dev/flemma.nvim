local ast = require("flemma.ast")
local ctxutil = require("flemma.context")
local eval = require("flemma.eval")
local mime_util = require("flemma.mime")
local frontmatter = require("flemma.frontmatter")

local M = {}

local function safe_read_binary(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, ("Failed to open file: " .. (err or "unknown")) end
  local data = f:read("*a")
  f:close()
  if not data then return nil, "Failed to read content" end
  return data, nil
end

local function detect_mime(path, override)
  if override and #override > 0 then return override end
  local ok, mt, _ = pcall(mime_util.get_mime_type, path)
  if ok and mt then return mt end
  return mime_util.get_mime_by_extension(path)
end

--- Evaluate a document AST.
--- Returns:
--- - evaluated: { messages = { role, parts=[{kind,text|mime|data|...}] }, errors, expression_errors }
--- - warnings: array of { filename, raw, error }
function M.evaluate(doc, base_context)
  local warnings = {}
  local expression_errors = {}
  local context = ctxutil.clone(base_context or {})

  -- 1) Frontmatter execution using the parser registry
  if doc.frontmatter then
    local fm = doc.frontmatter
    local parser = frontmatter.get(fm.language)
    
    if parser then
      local ok, result = pcall(parser, fm.code, context)
      if ok then
        context = ctxutil.extend(context, result)
      else
        table.insert(doc.errors, {
          type = "frontmatter",
          language = fm.language,
          error = tostring(result),
          position = fm.position,
        })
      end
    else
      table.insert(doc.errors, {
        type = "frontmatter",
        language = fm.language,
        error = "Unsupported frontmatter language: " .. tostring(fm.language),
        position = fm.position,
      })
    end
  end

  -- 2) Evaluate messages
  local evaluated_messages = {}
  local env = ctxutil.to_eval_env(context)

  for _, msg in ipairs(doc.messages or {}) do
    local parts = {}

    for _, seg in ipairs(msg.segments or {}) do
      if seg.kind == "text" then
        if seg.value and #seg.value > 0 then
          table.insert(parts, { kind = "text", text = seg.value })
        end
      elseif seg.kind == "thinking" then
        -- Preserve thinking nodes - providers can choose to filter them
        table.insert(parts, { kind = "thinking", content = seg.content })
      elseif seg.kind == "expression" then
        local ok, result = pcall(eval.eval_expression, seg.code, env)
        if not ok then
          -- Collect the error for reporting
          table.insert(expression_errors, {
            expression = seg.code,
            error = tostring(result),
            position = seg.position,
            message_role = msg.role,
            file_path = context.__filename or "N/A",
          })
          -- Keep original expression text in output
          table.insert(parts, { kind = "text", text = "{{" .. (seg.code or "") .. "}}" })
        else
          local str_result = result == nil and "" or tostring(result)
          if str_result and #str_result > 0 then
            table.insert(parts, { kind = "text", text = str_result })
          end
        end
      elseif seg.kind == "file_reference" then
        local filename = seg.path
        -- Resolve relative to context.__filename
        if context and context.__filename and filename:match("^%.%.?/") then
          local buffer_dir = vim.fn.fnamemodify(context.__filename, ":h")
          filename = vim.fn.simplify(buffer_dir .. "/" .. filename)
        end
        local mime = detect_mime(filename, seg.mime_override)
        if vim.fn.filereadable(filename) == 1 and mime then
          local data, err = safe_read_binary(filename)
          if data then
            table.insert(parts, {
              kind = "file",
              filename = filename,
              raw = seg.raw,
              mime_type = mime,
              data = data,
            })
          else
            table.insert(warnings, { 
              filename = filename, 
              raw = seg.raw, 
              error = err or "read error",
              position = seg.position,
              source_file = context.__filename or "N/A",
            })
            table.insert(parts, { kind = "unsupported_file", raw = seg.raw })
          end
        else
          local err = "File not found or MIME undetermined"
          table.insert(warnings, { 
            filename = filename, 
            raw = seg.raw, 
            error = err,
            position = seg.position,
            source_file = context.__filename or "N/A",
          })
          table.insert(parts, { kind = "unsupported_file", raw = seg.raw })
        end
        if seg.trailing_punct and #seg.trailing_punct > 0 then
          table.insert(parts, { kind = "text", text = seg.trailing_punct })
        end
      end
    end

    table.insert(evaluated_messages, {
      role = msg.role,
      parts = parts,
      position = msg.position,
    })
  end

  return {
    messages = evaluated_messages,
    errors = doc.errors,
    expression_errors = expression_errors,
  }, warnings
end

return M
