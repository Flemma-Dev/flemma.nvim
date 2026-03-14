--- AST node dump — serializes nodes to an indented tree format for diffing and hover.
---@class flemma.ast.Dump
local M = {}

local json = require("flemma.utilities.json")
-- NOTE: require("flemma.ast.query") directly instead of the barrel require("flemma.ast")
-- because dump.lua is itself part of the ast/ package and imported by the barrel — using
-- the barrel here would create a circular require.
local ast_query = require("flemma.ast.query")
local parser = require("flemma.parser")

local INDENT = "  "
local NEWLINE_CHAR = "↵"

---Format a position as a bracket string.
---Collapses [N - N] to [N] when start and end are identical with no meaningful columns.
---Omits start_col when it's 1 with no end_col (default "start of line" — not useful info).
---@param pos flemma.ast.Position|nil
---@return string
local function format_position(pos)
  if not pos then
    return ""
  end
  -- Only include start_col if end_col is also present (a meaningful column range)
  -- or if start_col is not the default "start of line" value
  local has_col_range = pos.start_col ~= nil and pos.end_col ~= nil
  local start_str = tostring(pos.start_line)
  if has_col_range then
    start_str = start_str .. ":" .. pos.start_col
  end
  if pos.end_line then
    -- Collapse [N - N] to [N] when no meaningful column range exists
    if pos.end_line == pos.start_line and not has_col_range then
      return " [" .. start_str .. "]"
    end
    local end_str = tostring(pos.end_line)
    if has_col_range then
      end_str = end_str .. ":" .. pos.end_col
    end
    return " [" .. start_str .. " - " .. end_str .. "]"
  end
  return " [" .. start_str .. "]"
end

---Append indented multiline content under a key label.
---Each line ends with a visible newline marker (↵) so line boundaries
---are unambiguous in the dump. Empty content lines show just the marker.
---@param output string[]
---@param level integer
---@param key string
---@param value string
local function append_multiline(output, level, key, value)
  local prefix = string.rep(INDENT, level)
  table.insert(output, prefix .. key .. ":")
  local content_prefix = string.rep(INDENT, level + 1)
  local lines = vim.split(value, "\n", { plain = true })
  for i, line in ipairs(lines) do
    local suffix = i < #lines and NEWLINE_CHAR or ""
    if line == "" then
      table.insert(output, suffix == "" and "" or content_prefix .. suffix)
    else
      table.insert(output, content_prefix .. line .. suffix)
    end
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
  local content_indent = string.rep(INDENT, level + 1)
  local formatted = pretty_json(encoded, content_indent)
  local prefix = string.rep(INDENT, level)
  table.insert(output, prefix .. key .. ":")
  -- First line of pretty_json output has no leading indent — prepend it
  for line in (content_indent .. formatted .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^%s+$") then
      table.insert(output, "")
    else
      table.insert(output, line)
    end
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
      table.insert(
        output,
        prefix .. INDENT .. "messages: " .. #node.messages .. " children (" .. table.concat(kinds, ", ") .. ")"
      )
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
      table.insert(
        output,
        prefix .. INDENT .. "segments: " .. #node.segments .. " children (" .. table.concat(kinds, ", ") .. ")"
      )
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

---Open a side-by-side diff of the raw (pre-rewriter) and rewritten (post-rewriter) ASTs.
---Both buffers scroll to the node under the cursor in the source .chat buffer.
---@param bufnr integer Source .chat buffer number
function M.open_diff(bufnr)
  -- Record cursor position before switching buffers
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1]
  local col = cursor[2] + 1 -- convert 0-indexed col to 1-indexed

  local raw_doc = parser.get_raw_document(bufnr)
  local rewritten_doc = parser.get_parsed_document(bufnr)

  local raw_lines = M.tree(raw_doc)
  local rewritten_lines = M.tree(rewritten_doc)

  -- Create scratch buffers
  local buf_raw = vim.api.nvim_create_buf(false, true)
  local buf_rewritten = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(buf_raw, 0, -1, false, raw_lines)
  vim.api.nvim_buf_set_lines(buf_rewritten, 0, -1, false, rewritten_lines)

  for _, buf in ipairs({ buf_raw, buf_rewritten }) do
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "flemma-ast"
  end

  local source_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  vim.api.nvim_buf_set_name(buf_raw, "ast:raw (" .. source_name .. ")")
  vim.api.nvim_buf_set_name(buf_rewritten, "ast:rewritten (" .. source_name .. ")")

  -- Open in a new tab with diff mode
  vim.cmd("tabnew")
  vim.api.nvim_set_current_buf(buf_raw)
  vim.cmd("diffthis")
  vim.cmd("vsplit")
  vim.api.nvim_set_current_buf(buf_rewritten)
  vim.cmd("diffthis")

  -- diffthis overrides foldmethod to "diff" — restore our expr-based folding
  -- while keeping diff highlighting and scrollbind active
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    vim.wo[win].foldmethod = "expr"
    vim.wo[win].foldexpr = "v:lua.require('flemma.ast.dump').foldexpr(v:lnum)"
    vim.wo[win].foldtext = "v:lua.require('flemma.ast.dump').foldtext()"
    vim.wo[win].foldlevel = 99
  end

  -- Find the node under the cursor and scroll to it
  local function find_target_line(doc, dump_lines)
    -- Try segment first
    local seg, msg = ast_query.find_segment_at_position(doc, lnum, col)
    local target_node = seg or msg

    -- Check frontmatter
    if not target_node and doc.frontmatter and doc.frontmatter.position then
      local fm_pos = doc.frontmatter.position
      local fm_end = fm_pos.end_line or fm_pos.start_line
      if lnum >= fm_pos.start_line and lnum <= fm_end then
        target_node = doc.frontmatter
      end
    end

    if not target_node or not target_node.position then
      return 1
    end

    -- Build the position string to search for
    local pos_str = format_position(target_node.position)
    local search_pattern = target_node.kind .. pos_str

    for i, line in ipairs(dump_lines) do
      if line:find(search_pattern, 1, true) then
        return i
      end
    end

    return 1
  end

  local target_raw = find_target_line(raw_doc, raw_lines)
  local target_rewritten = find_target_line(rewritten_doc, rewritten_lines)

  -- Scroll both windows to the target lines
  local rewritten_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(rewritten_win, { target_rewritten, 0 })

  vim.cmd("wincmd h")
  local raw_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(raw_win, { target_raw, 0 })

  -- Close all folds, then open the path to the cursor node
  for _, win in ipairs({ raw_win, rewritten_win }) do
    vim.api.nvim_set_current_win(win)
    vim.cmd("normal! zM") -- close all folds
    vim.cmd("normal! zv") -- open folds at cursor
  end
end

---Compute fold level for a line in a flemma-ast buffer.
---Node header lines (matching kind + position pattern) start folds.
---Multiline content key lines (value:, content:, code:, input:) start nested folds.
---@param lnum integer 1-indexed line number
---@return string
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)

  -- Empty lines (from multiline content blocks) inherit the previous fold level
  if line == "" then
    return "="
  end

  local indent = #(line:match("^(%s*)") or "")
  local level = indent / #INDENT

  -- Node header lines start a fold at their indent level + 1
  -- Match kind + position bracket, or a bare kind word followed by inline fields
  if line:match("^%s*%w+%s*%[") or line:match("^%s*%w+%s+%w+") then
    return ">" .. (level + 1)
  end

  -- Bare node headers without position or fields (e.g., "text" with no position)
  local word = line:match("^%s*(%w+)$")
  if
    word
    and (
      word == "document"
      or word == "message"
      or word == "text"
      or word == "expression"
      or word == "thinking"
      or word == "tool_use"
      or word == "tool_result"
      or word == "aborted"
      or word == "frontmatter"
    )
  then
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
