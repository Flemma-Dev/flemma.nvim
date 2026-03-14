--- AST node dump — serializes nodes to an indented tree format for diffing and hover.
---@class flemma.ast.Dump
local M = {}

local json = require("flemma.utilities.json")

local INDENT = "  "

---Format a position as a bracket string.
---@param pos flemma.ast.Position|nil
---@return string
local function format_position(pos)
  if not pos then
    return ""
  end
  local start_str = tostring(pos.start_line)
  if pos.start_col then
    start_str = start_str .. ":" .. pos.start_col
  end
  if pos.end_line then
    local end_str = tostring(pos.end_line)
    if pos.end_col then
      end_str = end_str .. ":" .. pos.end_col
    end
    return " [" .. start_str .. " - " .. end_str .. "]"
  end
  return " [" .. start_str .. "]"
end

---Append indented multiline content under a key label.
---@param output string[]
---@param level integer
---@param key string
---@param value string
local function append_multiline(output, level, key, value)
  local prefix = string.rep(INDENT, level)
  table.insert(output, prefix .. key .. ":")
  local content_prefix = string.rep(INDENT, level + 1)
  for line in (value .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(output, content_prefix .. line)
  end
end

---Pretty-print a compact JSON string with indentation.
---Uses the json utility module for decoding (never bare vim.json).
---@param compact_json string Compact JSON string
---@param base_indent string Base indentation prefix for all lines
---@return string
local function pretty_json(compact_json, base_indent)
  local indent_level = 0
  local in_string = false
  local escape = false
  local result = {}
  local current_indent = base_indent

  local function update_indent()
    current_indent = base_indent .. string.rep(INDENT, indent_level)
  end

  for i = 1, #compact_json do
    local c = compact_json:sub(i, i)

    if escape then
      table.insert(result, c)
      escape = false
    elseif in_string then
      table.insert(result, c)
      if c == "\\" then
        escape = true
      elseif c == '"' then
        in_string = false
      end
    elseif c == '"' then
      in_string = true
      table.insert(result, c)
    elseif c == "{" or c == "[" then
      local next_c = compact_json:sub(i + 1, i + 1)
      if (c == "{" and next_c == "}") or (c == "[" and next_c == "]") then
        table.insert(result, c)
      else
        indent_level = indent_level + 1
        update_indent()
        table.insert(result, c .. "\n" .. current_indent)
      end
    elseif c == "}" or c == "]" then
      local prev_c = compact_json:sub(i - 1, i - 1)
      if (c == "}" and prev_c == "{") or (c == "]" and prev_c == "[") then
        table.insert(result, c)
      else
        indent_level = indent_level - 1
        update_indent()
        table.insert(result, "\n" .. current_indent .. c)
      end
    elseif c == "," then
      table.insert(result, ",\n" .. current_indent)
    elseif c == ":" then
      table.insert(result, ": ")
    elseif c ~= " " then
      table.insert(result, c)
    end
  end

  return table.concat(result)
end

---Append pretty-printed JSON content under a key label.
---@param output string[]
---@param level integer
---@param key string
---@param value table
local function append_json(output, level, key, value)
  local encoded = json.encode_ordered(value)
  local indent_str = string.rep(INDENT, level + 1)
  local formatted = pretty_json(encoded, indent_str)
  local prefix = string.rep(INDENT, level)
  table.insert(output, prefix .. key .. ":")
  for line in (formatted .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(output, line)
  end
end

---Render inline scalar fields for a segment header.
---@param seg flemma.ast.Segment|flemma.ast.MessageNode|flemma.ast.FrontmatterNode|flemma.ast.DocumentNode
---@return string
local function inline_fields(seg)
  local parts = {}
  local kind = seg.kind

  if kind == "message" then
    ---@cast seg flemma.ast.MessageNode
    table.insert(parts, 'role="' .. seg.role .. '"')
  elseif kind == "frontmatter" then
    ---@cast seg flemma.ast.FrontmatterNode
    table.insert(parts, 'language="' .. seg.language .. '"')
  elseif kind == "expression" then
    ---@cast seg flemma.ast.ExpressionSegment
    -- Adaptive: inline if single-line
    if not seg.code:find("\n") then
      table.insert(parts, 'code="' .. seg.code .. '"')
    end
  elseif kind == "thinking" then
    ---@cast seg flemma.ast.ThinkingSegment
    table.insert(parts, "redacted=" .. tostring(seg.redacted or false))
    if seg.signature then
      table.insert(parts, 'signature.provider="' .. seg.signature.provider .. '"')
    end
  elseif kind == "tool_use" then
    ---@cast seg flemma.ast.ToolUseSegment
    table.insert(parts, 'name="' .. seg.name .. '"')
    table.insert(parts, 'id="' .. seg.id .. '"')
  elseif kind == "tool_result" then
    ---@cast seg flemma.ast.ToolResultSegment
    table.insert(parts, 'tool_use_id="' .. seg.tool_use_id .. '"')
    table.insert(parts, "is_error=" .. tostring(seg.is_error))
    if seg.status then
      table.insert(parts, 'status="' .. seg.status .. '"')
    end
  elseif kind == "aborted" then
    ---@cast seg flemma.ast.AbortedSegment
    table.insert(parts, 'message="' .. seg.message .. '"')
  end

  if #parts > 0 then
    return " " .. table.concat(parts, " ")
  end
  return ""
end

---Serialize an AST node to indented tree-format lines.
---@param node flemma.ast.DocumentNode|flemma.ast.MessageNode|flemma.ast.Segment|flemma.ast.FrontmatterNode
---@param opts? flemma.ast.dump.Opts
---@return string[]
function M.tree(node, opts)
  opts = opts or {}
  local depth = opts.depth
  local level = opts.indent or 0
  local output = {}
  local prefix = string.rep(INDENT, level)
  local kind = node.kind

  -- Header line
  local pos_str = format_position(node.position)
  local fields = inline_fields(node)
  table.insert(output, prefix .. kind .. pos_str .. fields)

  -- Check depth limit
  if depth and depth <= 0 then
    return output
  end

  local child_depth = depth and (depth - 1) or nil

  -- Node-specific children and multiline fields
  if kind == "document" then
    ---@cast node flemma.ast.DocumentNode
    if node.frontmatter then
      if depth == 1 then
        table.insert(output, prefix .. INDENT .. "frontmatter: 1 child")
      else
        local fm_lines = M.tree(node.frontmatter, { depth = child_depth, indent = level + 1 })
        vim.list_extend(output, fm_lines)
      end
    end
    if depth == 1 then
      -- Summarize messages
      local kinds = {}
      for _, msg in ipairs(node.messages) do
        table.insert(kinds, msg.role)
      end
      table.insert(output, prefix .. INDENT .. "messages: " .. #node.messages .. " children (" .. table.concat(kinds, ", ") .. ")")
    else
      for _, msg in ipairs(node.messages) do
        local msg_lines = M.tree(msg, { depth = child_depth, indent = level + 1 })
        vim.list_extend(output, msg_lines)
      end
    end
  elseif kind == "message" then
    ---@cast node flemma.ast.MessageNode
    if depth == 1 then
      local kinds = {}
      for _, seg in ipairs(node.segments) do
        table.insert(kinds, seg.kind)
      end
      table.insert(output, prefix .. INDENT .. "segments: " .. #node.segments .. " children (" .. table.concat(kinds, ", ") .. ")")
    else
      for _, seg in ipairs(node.segments) do
        local seg_lines = M.tree(seg, { depth = child_depth, indent = level + 1 })
        vim.list_extend(output, seg_lines)
      end
    end
  elseif kind == "frontmatter" then
    ---@cast node flemma.ast.FrontmatterNode
    append_multiline(output, level + 1, "code", node.code)
  elseif kind == "text" then
    ---@cast node flemma.ast.TextSegment
    append_multiline(output, level + 1, "value", node.value)
  elseif kind == "expression" then
    ---@cast node flemma.ast.ExpressionSegment
    -- Only render multiline if code contains newlines (otherwise it's inline)
    if node.code:find("\n") then
      append_multiline(output, level + 1, "code", node.code)
    end
  elseif kind == "thinking" then
    ---@cast node flemma.ast.ThinkingSegment
    append_multiline(output, level + 1, "content", node.content)
  elseif kind == "tool_use" then
    ---@cast node flemma.ast.ToolUseSegment
    append_json(output, level + 1, "input", node.input)
  elseif kind == "tool_result" then
    ---@cast node flemma.ast.ToolResultSegment
    append_multiline(output, level + 1, "content", node.content)
  end
  -- aborted: message is inline, no multiline fields

  return output
end

---@class flemma.ast.dump.Opts
---@field depth? integer nil = unlimited, 1 = this node + child summaries
---@field indent? integer starting indent level (default 0)

---Compute fold level for a line in a flemma-ast buffer.
---Node header lines (matching kind + position pattern) start folds.
---Multiline content key lines (value:, content:, code:, input:) start nested folds.
---@param lnum integer 1-indexed line number
---@return string
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  local indent = #(line:match("^(%s*)") or "")
  local level = indent / #INDENT

  -- Node header lines start a fold at their indent level + 1
  if line:match("^%s*%w+%s*%[") or line:match("^%s*%w+$") then
    return ">" .. (level + 1)
  end

  -- Multiline key lines (value:, content:, code:, input:) start a nested fold
  if line:match("^%s+%w+:$") then
    return ">" .. (level + 1)
  end

  return tostring(level + 1)
end

---Generate fold text for a collapsed fold in a flemma-ast buffer.
---@return string
function M.foldtext()
  local foldstart = vim.v.foldstart
  local foldend = vim.v.foldend
  local line = vim.fn.getline(foldstart)
  local line_count = foldend - foldstart + 1

  -- For multiline content keys (value:, content:, code:, input:),
  -- show a truncated preview of the content
  if line:match("^%s+%w+:$") then
    local key = vim.trim(line)
    local next_line = vim.fn.getline(foldstart + 1)
    local preview = vim.trim(next_line)

    -- Calculate total content size
    local total_bytes = 0
    for i = foldstart + 1, foldend do
      total_bytes = total_bytes + #vim.fn.getline(i)
    end

    if #preview > 40 then
      preview = preview:sub(1, 40) .. "..."
    end

    local indent = line:match("^(%s*)")
    return indent .. key:sub(1, -2) .. ': "' .. preview .. '" (' .. total_bytes .. " bytes)"
  end

  -- For node headers, show the header line with line count
  return line .. " (" .. line_count .. " lines)"
end

return M
