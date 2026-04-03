--- Template compiler for Flemma
--- Compiles AST segment lists into Lua source code with line maps,
--- and executes compiled templates in sandboxed environments.
---@class flemma.templating.Compiler
local M = {}

local ast = require("flemma.ast")
local emittable = require("flemma.emittable")
local json = require("flemma.utilities.json")
local log = require("flemma.logging")
local preproc_utils = require("flemma.preprocessor.utilities")

---@class flemma.templating.compiler.LineMapEntry
---@field lnum integer Buffer line number (1-based)

---@class flemma.templating.compiler.CompilationResult
---@field line_map flemma.templating.compiler.LineMapEntry[] Generated-line → buffer-line mapping
---@field source string The generated Lua source
---@field segments flemma.ast.Segment[] Original segment list (for __emit_part references)
---@field error string|nil Syntax error from load() validation (non-nil means invalid code)

--- Escape a string for embedding in a single-quoted Lua literal.
---@param str string
---@return string
local function escape_lua_string(str)
  return preproc_utils.lua_string_escape(str)
end

--- Get the buffer line for a segment (best-effort).
---@param segment flemma.ast.Segment
---@return integer
local function segment_lnum(segment)
  if segment.position and segment.position.start_line then
    return segment.position.start_line
  end
  return 0
end

--- Apply whitespace trimming to text segments based on adjacent trim flags.
--- Returns a new segment list with trimmed text values.
---@param segments flemma.ast.Segment[]
---@return flemma.ast.Segment[]
local function apply_trim(segments)
  local result = {}
  for i, seg in ipairs(segments) do
    if seg.kind == "text" then
      ---@cast seg flemma.ast.TextSegment
      local value = seg.value
      -- Check if next segment has trim_before
      local next_seg = segments[i + 1]
      if next_seg and next_seg.trim_before then
        -- Strip trailing whitespace up to and including nearest newline
        local trimmed = value:gsub("[\t ]*\n[\t ]*$", "")
        if trimmed == value then
          -- No newline found, strip all trailing whitespace
          trimmed = value:gsub("%s+$", "")
        end
        value = trimmed
      end
      -- Check if previous segment has trim_after
      local prev_seg = segments[i - 1]
      if prev_seg and prev_seg.trim_after then
        -- Strip leading whitespace up to and including nearest newline
        local trimmed = value:gsub("^[\t ]*\n[\t ]*", "")
        if trimmed == value then
          -- No newline found, strip all leading whitespace
          trimmed = value:gsub("^%s+", "")
        end
        value = trimmed
      end
      result[i] = value ~= seg.value and ast.text(value, seg.position) or seg
    else
      result[i] = seg
    end
  end
  return result
end

--- Compile a list of AST segments into a Lua function and line map.
---
--- The generated code uses the following environment entries:
---   __emit(value)                — output builder (text, emittable, table, etc.)
---   __emit_part(segment)         — pass-through for structural segments
---   __emit_expr_error(err, idx)  — report expression evaluation failures
---   __segments                   — the original segment array (for index references)
---   __capture_open()             — redirect subsequent __emit calls into a sub-collector
---   __capture_close()            — restore previous collector; return captured parts[]
---@param segments flemma.ast.Segment[]
---@return flemma.templating.compiler.CompilationResult
function M.compile(segments)
  segments = apply_trim(segments)

  local lines = {}
  local line_map = {}

  ---@param code string
  ---@param lnum integer
  local function add_line(code, lnum)
    lines[#lines + 1] = code
    line_map[#line_map + 1] = { lnum = lnum }
  end

  -- Unique tmp variable generator; local to this compile() call so it resets per compilation.
  local next_tmp_id = 0
  local function tmp_var()
    next_tmp_id = next_tmp_id + 1
    return "__tmp" .. next_tmp_id
  end

  ---@param segment flemma.ast.Segment
  ---@param seg_index integer|nil Segment index in the top-level segments table (nil for inner/recursive children)
  ---@param add_line_fn fun(code: string, lnum: integer)
  local function compile_one(segment, seg_index, add_line_fn)
    local lnum = segment_lnum(segment)

    if segment.kind == "text" then
      ---@cast segment flemma.ast.TextSegment
      if segment.value and #segment.value > 0 then
        add_line_fn("__emit('" .. escape_lua_string(segment.value) .. "')", lnum)
      end
    elseif segment.kind == "expression" then
      ---@cast segment flemma.ast.ExpressionSegment
      local raw_expr = "{{" .. (segment.code or "") .. "}}"
      local escaped_raw = escape_lua_string(raw_expr)
      local error_ref = seg_index and tostring(seg_index) or "nil"
      add_line_fn(
        "do local __ok,__v=pcall(function() return ("
          .. segment.code
          .. ") end); if __ok then __emit(__v) else __emit('"
          .. escaped_raw
          .. "'); __emit_expr_error(__v, "
          .. error_ref
          .. ") end end",
        lnum
      )
    elseif segment.kind == "code" then
      ---@cast segment flemma.ast.CodeSegment
      -- Insert raw code, one generated line per source line
      local code_lines = vim.split(segment.code, "\n", { plain = true })
      for j, code_line in ipairs(code_lines) do
        add_line_fn(code_line, lnum + j - 1)
      end
    elseif segment.kind == "tool_result" and segment.segments and #segment.segments > 0 then
      ---@cast segment flemma.ast.ToolResultSegment
      -- Compound tool_result: capture child segment output into a tool_result envelope.
      local var = tmp_var()
      add_line_fn("__capture_open()", lnum)
      for _, child in ipairs(segment.segments) do
        compile_one(child, nil, add_line_fn)
      end
      -- Retrieve the tool_result segment from __segments if we have a top-level index,
      -- otherwise reference fields directly via a local constructed table.
      if seg_index then
        add_line_fn("do local " .. var .. " = __segments[" .. seg_index .. "]", lnum)
        add_line_fn(
          "__emit_part({ kind = 'tool_result', tool_use_id = "
            .. var
            .. ".tool_use_id, "
            .. "is_error = "
            .. var
            .. ".is_error, content = "
            .. var
            .. ".content, "
            .. "parts = __capture_close() }) end",
          lnum
        )
      else
        add_line_fn(
          "__emit_part({ kind = 'tool_result', tool_use_id = '"
            .. escape_lua_string(segment.tool_use_id)
            .. "', "
            .. "is_error = "
            .. tostring(segment.is_error)
            .. ", content = '"
            .. escape_lua_string(segment.content)
            .. "', "
            .. "parts = __capture_close() })",
          lnum
        )
      end
    elseif
      segment.kind == "tool_result"
      or segment.kind == "tool_use"
      or segment.kind == "thinking"
      or segment.kind == "aborted"
    then
      -- Opaque structural pass-through (tool_result with no inner segments, or other kinds).
      add_line_fn("__emit_part(__segments[" .. (seg_index or "nil") .. "])", lnum)
    end
  end

  for i, segment in ipairs(segments) do
    compile_one(segment, i, add_line)
  end

  local source = table.concat(lines, "\n")

  -- Syntax-check only (no env needed). execute() re-loads with the real env.
  local _, load_err = load(source, "template", "t")

  if load_err then
    log.debug("compiler: syntax error in compiled template: " .. load_err)
  else
    log.trace("compiler: compiled " .. #segments .. " segments into " .. #lines .. " lines")
  end

  return {
    line_map = line_map,
    source = source,
    segments = segments,
    error = load_err,
  }
end

--- Convert a value to text, with table-to-JSON support.
---@param value any
---@return string
local function to_text(value)
  if value == nil then
    return ""
  end
  if type(value) == "table" then
    local ok, encoded = pcall(json.encode, value)
    if ok then
      return encoded
    end
  end
  return tostring(value)
end

--- Convert a structural segment to its corresponding processor part.
---@param segment flemma.ast.Segment
---@return table|nil
local function structural_segment_to_part(segment)
  if segment.kind == "tool_result" then
    ---@cast segment flemma.ast.ToolResultSegment
    if not segment.status then
      return {
        kind = "tool_result",
        tool_use_id = segment.tool_use_id,
        content = segment.content,
        is_error = segment.is_error,
      }
    end
  elseif segment.kind == "tool_use" then
    ---@cast segment flemma.ast.ToolUseSegment
    return {
      kind = "tool_use",
      id = segment.id,
      name = segment.name,
      input = segment.input,
    }
  elseif segment.kind == "thinking" then
    ---@cast segment flemma.ast.ThinkingSegment
    return {
      kind = "thinking",
      content = segment.content,
      signature = segment.signature,
      redacted = segment.redacted,
    }
  elseif segment.kind == "aborted" then
    ---@cast segment flemma.ast.AbortedSegment
    return { kind = "aborted", message = segment.message }
  end
  return nil
end

--- Parse a line number from a Lua error message.
---@param err_msg string
---@return integer|nil
local function parse_error_line(err_msg)
  local line = err_msg:match('%[string "template"%]:(%d+)')
  if line then
    return tonumber(line)
  end
  return nil
end

--- Look up buffer line from a generated-code line number.
---@param line_map flemma.templating.compiler.LineMapEntry[]
---@param generated_line integer|nil
---@return integer lnum Buffer line (0 if not found)
local function lookup_lnum(line_map, generated_line)
  if generated_line and line_map[generated_line] then
    return line_map[generated_line].lnum
  end
  return 0
end

--- Execute a compiled template in the given environment.
---
--- Loads the source with the provided env, installs __emit/__emit_part/__segments,
--- then runs. Expression errors degrade gracefully (emit raw text); code block
--- errors fail the entire message with diagnostics.
---@param result flemma.templating.compiler.CompilationResult
---@param env table Execution environment
---@return table[] parts Evaluated parts
---@return table[] diagnostics
function M.execute(result, env)
  local diagnostics = {} ---@type flemma.ast.Diagnostic[]

  -- Handle compile-time syntax errors
  if result.error then
    local err_line = parse_error_line(result.error)
    local lnum = lookup_lnum(result.line_map, err_line)
    table.insert(diagnostics, {
      type = "template",
      severity = "error",
      error = result.error,
      position = lnum > 0 and { start_line = lnum } or nil,
      source_file = env.__filename or "N/A",
    })
    return {}, diagnostics
  end

  -- Build output collector
  local parts = {} ---@type table[]
  local text_accum = {} ---@type string[]

  local function flush_text()
    if #text_accum > 0 then
      local merged = table.concat(text_accum)
      if #merged > 0 then
        table.insert(parts, { kind = "text", text = merged })
      end
      text_accum = {}
    end
  end

  -- __emit: the core output primitive
  ---@param value any
  local function emit(value)
    if value == nil then
      return
    end
    if emittable.is_emittable(value) then
      flush_text()
      local emit_ctx = emittable.EmitContext.new({
        diagnostics = diagnostics,
        source_file = env.__filename or "N/A",
      })
      local ok, err = pcall(value.emit, value, emit_ctx)
      if ok then
        for _, ep in ipairs(emit_ctx.parts) do
          table.insert(parts, ep)
        end
      else
        table.insert(diagnostics, {
          type = "template",
          severity = "warning",
          error = "Error during emit: " .. tostring(err),
          source_file = env.__filename or "N/A",
        })
      end
    elseif type(value) == "table" then
      text_accum[#text_accum + 1] = to_text(value)
    else
      text_accum[#text_accum + 1] = tostring(value)
    end
  end

  -- __emit_part: pass-through for structural segments, or directly for capture-assembled tables
  ---@param segment flemma.ast.Segment|table
  local function emit_part(segment)
    flush_text()
    -- If segment is already a plain part table (assembled by capture), emit it directly.
    ---@cast segment table
    if segment.kind and not segment.position then
      table.insert(parts, segment)
      return
    end
    ---@cast segment flemma.ast.Segment
    local part = structural_segment_to_part(segment)
    if part then
      table.insert(parts, part)
    end
  end

  -- Capture stack for __capture_open / __capture_close.
  -- Each frame saves the outer `parts` and `text_accum` so they can be restored.
  local capture_stack = {} ---@type table[]

  -- __capture_open: redirect subsequent __emit calls into a new sub-collector.
  local function capture_open()
    flush_text()
    table.insert(capture_stack, { parts = parts, text_accum = text_accum })
    parts = {}
    text_accum = {}
  end

  -- __capture_close: restore the outer collector; return captured parts[].
  ---@return table[] captured_parts
  local function capture_close()
    flush_text()
    local captured_parts = parts
    local frame = table.remove(capture_stack)
    parts = frame.parts
    text_accum = frame.text_accum
    return captured_parts
  end

  -- __emit_expr_error: report expression evaluation failures as diagnostics.
  -- Structured error tables (e.g., from include()) are used as-is with defaults
  -- filled in. Plain errors are wrapped in a new diagnostic.
  ---@param err any
  ---@param segment_index integer
  local function emit_expr_error(err, segment_index)
    local segment = result.segments[segment_index]
    local defaults = {
      position = segment and segment.position or nil,
      source_file = env.__filename or "N/A",
      severity = "warning",
    }
    if type(err) == "table" and err.type then
      -- Structured error: preserve its type and fields, fill in defaults
      for k, v in pairs(defaults) do
        if err[k] == nil then
          err[k] = v
        end
      end
      table.insert(diagnostics, err)
    else
      table.insert(diagnostics, {
        type = "expression",
        severity = "warning",
        expression = segment and segment.code or nil,
        error = tostring(err),
        position = segment and segment.position or nil,
        source_file = env.__filename or "N/A",
      })
    end
  end

  -- Ensure essential builtins are available in the env.
  -- The generated code uses pcall (for expression wrappers), tostring, and error.
  -- In production, the stdlib populator provides these; in tests with minimal envs,
  -- they may be missing. Preserve any existing overrides.
  -- Uses rawget to bypass the strict __index metamethod on create_env() tables.
  if rawget(env, "pcall") == nil then
    env.pcall = pcall
  end
  if rawget(env, "tostring") == nil then
    env.tostring = tostring
  end
  if rawget(env, "error") == nil then
    env.error = error
  end

  -- Install __emit, __emit_part, __emit_expr_error, __segments, __capture_open, __capture_close on env
  env.__emit = emit
  env.__emit_part = emit_part
  env.__emit_expr_error = emit_expr_error
  env.__segments = result.segments
  env.__capture_open = capture_open
  env.__capture_close = capture_close

  -- Override print to emit into template output (no separators, no trailing newline)
  env.print = function(...)
    for i = 1, select("#", ...) do
      emit(tostring(select(i, ...)))
    end
  end

  -- Load source with the execution environment
  local chunk, load_err = load(result.source, "template", "t", env)
  if not chunk then
    local err_line = parse_error_line(load_err or "")
    local lnum = lookup_lnum(result.line_map, err_line)
    table.insert(diagnostics, {
      type = "template",
      severity = "error",
      error = load_err or "Unknown load error",
      position = lnum > 0 and { start_line = lnum } or nil,
      source_file = env.__filename or "N/A",
    })
    env.__emit = nil
    env.__emit_part = nil
    env.__emit_expr_error = nil
    env.__segments = nil
    env.__capture_open = nil
    env.__capture_close = nil
    return {}, diagnostics
  end

  -- Execute
  local ok, err = pcall(chunk)
  if not ok then
    if type(err) == "table" and err.type then
      -- Structured error (from include, config proxy, etc.): preserve as-is
      if not err.severity then
        err.severity = "error"
      end
      if not err.source_file then
        err.source_file = env.__filename or "N/A"
      end
      table.insert(diagnostics, err)
    else
      -- Plain string error: existing handling
      log.debug("compiler: runtime error in template: " .. tostring(err))
      local err_line = parse_error_line(tostring(err))
      local lnum = lookup_lnum(result.line_map, err_line)
      table.insert(diagnostics, {
        type = "template",
        severity = "error",
        error = tostring(err),
        position = lnum > 0 and { start_line = lnum } or nil,
        source_file = env.__filename or "N/A",
      })
    end
    env.__emit = nil
    env.__emit_part = nil
    env.__emit_expr_error = nil
    env.__segments = nil
    env.__capture_open = nil
    env.__capture_close = nil
    return {}, diagnostics
  end

  flush_text()

  -- Clean up env
  env.__emit = nil
  env.__emit_part = nil
  env.__emit_expr_error = nil
  env.__segments = nil
  env.__capture_open = nil
  env.__capture_close = nil

  return parts, diagnostics
end

return M
