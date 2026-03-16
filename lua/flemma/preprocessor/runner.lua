--- Preprocessor pipeline execution engine
--- Scans TextSegments line-by-line for pattern matches, calls handlers,
--- assembles emissions into new AST segments, and applies system/frontmatter
--- mutations after each rewriter.
---@class flemma.preprocessor.Runner
local M = {}

local ast = require("flemma.ast")
local buffer_util = require("flemma.utilities.buffer")
local context_module = require("flemma.preprocessor.context")

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

---@class flemma.preprocessor.RunOpts
---@field interactive boolean Whether this is an interactive (live) run
---@field rewriters flemma.preprocessor.Rewriter[] Ordered list of rewriters to execute
---@field bufnr? integer Buffer number (required for interactive mode)

---@class flemma.preprocessor.BufferEdit
---@field start_line integer 0-indexed start line
---@field start_col integer 0-indexed start column
---@field end_line integer 0-indexed end line
---@field end_col integer 0-indexed end column
---@field replacement string[] Replacement lines

---@class flemma.preprocessor.MessageContext
---@field message flemma.ast.MessageNode The current message being processed
---@field index integer 1-indexed position in the message array

---@class flemma.preprocessor.RewriterState
---@field system flemma.preprocessor.SystemAccessor
---@field frontmatter flemma.preprocessor.FrontmatterAccessor
---@field metadata table<string, any>
---@field diagnostics flemma.preprocessor.RewriterDiagnostic[]
---@field _buffer_edits? flemma.preprocessor.BufferEdit[]

--------------------------------------------------------------------------------
-- Local helpers
--------------------------------------------------------------------------------

---Check whether a new match [match_start, match_end] overlaps any existing range.
---@param ranges {[1]: integer, [2]: integer}[] Existing ranges as {start, end} pairs
---@param match_start integer
---@param match_end integer
---@return boolean
local function overlaps_any(ranges, match_start, match_end)
  for _, range in ipairs(ranges) do
    if match_start <= range[2] and match_end >= range[1] then
      return true
    end
  end
  return false
end

---Build a Match object from a Lua pattern match result.
---@param line string The full line text
---@param m { start_pos: integer, end_pos: integer, captures: string[] } Raw match data
---@param current_line integer 1-indexed line number
---@return flemma.preprocessor.Match
local function build_match(line, m, current_line)
  local full = line:sub(m.start_pos, m.end_pos)
  ---@type flemma.preprocessor.Match
  local match = {
    full = full,
    start_col = m.start_pos,
    end_col = m.end_pos,
    captures = m.captures,
  }
  -- Attach line number for position derivation
  match._line = current_line
  return match
end

---Emit a text AST segment from a string with position information.
---Computes end_line and end_col from the string content.
---@param result flemma.ast.Segment[] Accumulator for segments
---@param str string Text to emit
---@param line integer 1-indexed line number
---@param col integer 1-indexed column offset
local function emit_text(result, str, line, col)
  if #str == 0 then
    return
  end
  local end_line = line
  local end_col = col + #str - 1
  -- Count newlines to compute end position
  for _ in str:gmatch("\n") do
    end_line = end_line + 1
  end
  if end_line > line then
    -- After newlines, end_col is the length of the last line
    local last_newline = str:find("\n[^\n]*$")
    end_col = #str - last_newline
  end
  table.insert(
    result,
    ast.text(str, {
      start_line = line,
      start_col = col,
      end_line = end_line,
      end_col = end_col,
    })
  )
end

---Convert a single emission to AST segments.
---Handles: nil (keep original), text, expression, remove, rewrite.
---@param emission flemma.preprocessor.Emission|flemma.preprocessor.EmissionList|nil
---@param position { line: integer, col: integer, end_line?: integer, end_col?: integer } Position for generated segments
---@param original_text string|nil Original matched text (for nil/keep-as-is case)
---@param buffer_edits flemma.preprocessor.BufferEdit[] Accumulator for buffer edits
---@param interactive boolean Whether in interactive mode
---@return flemma.ast.Segment[]
local function emission_to_segments(emission, position, original_text, buffer_edits, interactive)
  local segments = {}

  if emission == nil then
    -- nil means keep original text
    if original_text and #original_text > 0 then
      table.insert(
        segments,
        ast.text(original_text, {
          start_line = position.line,
          start_col = position.col,
          end_line = position.end_line,
          end_col = position.end_col,
        })
      )
    end
    return segments
  end

  -- Check if this is an emission list (array of emissions)
  local emission_table = emission --[[@as table]]
  if emission_table[1] ~= nil and emission_table.kind == nil then
    ---@cast emission flemma.preprocessor.EmissionList
    -- Distribute position range across sub-emissions based on content lengths.
    -- Text/rewrite emissions consume #value characters of the original span;
    -- expression emissions share the remaining characters.
    local match_end_col = position.end_col or position.col
    local total_span = match_end_col - position.col + 1
    local text_chars = 0
    local expr_count = 0
    for _, e in ipairs(emission) do
      local et = e --[[@as table]]
      if (et.kind == "text" or et.kind == "rewrite") and et.value then
        text_chars = text_chars + #et.value
      elseif et.kind == "expression" then
        expr_count = expr_count + 1
      end
    end
    local expr_chars_total = math.max(total_span - text_chars, 0)
    local expr_chars_each = expr_count > 0 and math.floor(expr_chars_total / expr_count) or 0
    local expr_remainder = expr_count > 0 and (expr_chars_total - expr_chars_each * expr_count) or 0
    local expr_seen = 0

    local cursor_col = position.col
    for _, single_emission in ipairs(emission) do
      local et = single_emission --[[@as table]]
      local span
      if (et.kind == "text" or et.kind == "rewrite") and et.value then
        span = #et.value
      elseif et.kind == "expression" then
        expr_seen = expr_seen + 1
        span = expr_chars_each + (expr_seen == expr_count and expr_remainder or 0)
      else
        -- remove or unknown: no span consumed
        span = 0
      end
      local sub_end_col = cursor_col + math.max(span - 1, 0)
      local sub_pos = {
        line = position.line,
        col = cursor_col,
        end_line = position.end_line or position.line,
        end_col = sub_end_col,
      }
      local sub_segments = emission_to_segments(single_emission, sub_pos, nil, buffer_edits, interactive)
      for _, seg in ipairs(sub_segments) do
        table.insert(segments, seg)
      end
      if span > 0 then
        cursor_col = cursor_col + span
      end
    end
    return segments
  end

  ---@cast emission flemma.preprocessor.Emission
  local pos = {
    start_line = position.line,
    start_col = position.col,
    end_line = position.end_line,
    end_col = position.end_col,
  }

  if emission.kind == "remove" then
    -- Remove emission: produce no segments (delete matched text)
    return segments
  elseif emission.kind == "text" then
    ---@cast emission flemma.preprocessor.TextEmission
    if #emission.value > 0 then
      table.insert(segments, ast.text(emission.value, pos))
    end
  elseif emission.kind == "expression" then
    ---@cast emission flemma.preprocessor.ExpressionEmission
    table.insert(segments, ast.expression(emission.code, pos))
  elseif emission.kind == "rewrite" then
    ---@cast emission flemma.preprocessor.RewriteEmission
    -- Rewrite replaces text in the AST and queues a buffer edit in interactive mode
    if #emission.value > 0 then
      table.insert(segments, ast.text(emission.value, pos))
    end
    if interactive and original_text then
      -- Queue a buffer edit to replace the original text with the rewrite
      local start_line_0 = position.line - 1
      local start_col_0 = position.col - 1
      local end_line_0 = start_line_0
      local end_col_0 = start_col_0 + #original_text
      -- Split replacement into lines for nvim_buf_set_text
      local replacement_lines = vim.split(emission.value, "\n", { plain = true })
      table.insert(buffer_edits, {
        start_line = start_line_0,
        start_col = start_col_0,
        end_line = end_line_0,
        end_col = end_col_0,
        replacement = replacement_lines,
      })
    end
  elseif emission.kind == "code" then
    ---@cast emission flemma.preprocessor.CodeEmission
    table.insert(
      segments,
      ast.code(emission.code, pos, {
        trim_before = emission.trim_before,
        trim_after = emission.trim_after,
      })
    )
  end

  return segments
end

---Run text handlers on a single TextSegment: split by newlines, scan each line
---for pattern matches, call handlers, collect emissions.
---@param text_segment flemma.ast.TextSegment The text segment to process
---@param handlers flemma.preprocessor.TextHandlerEntry[] Text handlers from the rewriter
---@param rewriter_state flemma.preprocessor.RewriterState Shared state for this rewriter
---@param opts flemma.preprocessor.RunOpts Pipeline options
---@param message_context flemma.preprocessor.MessageContext Current message iteration context
---@return flemma.ast.Segment[] result_segments
local function run_text_handlers(text_segment, handlers, rewriter_state, opts, message_context)
  if #handlers == 0 then
    return { text_segment }
  end

  local value = text_segment.value

  -- Quick pre-scan: if no handler pattern matches anywhere in the text, return unchanged
  local any_match = false
  for _, entry in ipairs(handlers) do
    if value:find(entry.pattern) then
      any_match = true
      break
    end
  end
  if not any_match then
    return { text_segment }
  end

  local base_line = (text_segment.position and text_segment.position.start_line) or 1
  local buffer_edits_accumulator = {} ---@type flemma.preprocessor.BufferEdit[]

  -- Split text by newlines, preserving the structure
  local lines = vim.split(value, "\n", { plain = true })
  local result_segments = {} ---@type flemma.ast.Segment[]
  local current_line = base_line

  -- Accumulator for consecutive non-matching content to minimize segment splitting
  local accum_text = ""
  local accum_start_line = base_line
  local accum_start_col = 1

  ---Flush accumulated non-matching text as a single segment.
  local function flush_accum()
    if #accum_text > 0 then
      emit_text(result_segments, accum_text, accum_start_line, accum_start_col)
      accum_text = ""
    end
  end

  for line_index, line in ipairs(lines) do
    -- Collect all matches from all handlers for this line
    ---@type { start_pos: integer, end_pos: integer, captures: string[], handler: flemma.preprocessor.TextHandler, pattern: string }[]
    local all_matches = {}

    for _, entry in ipairs(handlers) do
      local search_start = 1
      while search_start <= #line do
        local match_results = { line:find(entry.pattern, search_start) }
        if not match_results[1] then
          break
        end
        local start_pos = match_results[1] --[[@as integer]]
        local end_pos = match_results[2] --[[@as integer]]
        local captures = {} ---@type string[]
        for ci = 3, #match_results do
          table.insert(captures, match_results[ci])
        end

        table.insert(all_matches, {
          start_pos = start_pos,
          end_pos = end_pos,
          captures = captures,
          handler = entry.handler,
          pattern = entry.pattern,
        })
        search_start = end_pos + 1
      end
    end

    -- Sort matches by start position, then by end position (longer match first)
    table.sort(all_matches, function(a, b)
      if a.start_pos == b.start_pos then
        return a.end_pos > b.end_pos
      end
      return a.start_pos < b.start_pos
    end)

    -- Process matches, skipping overlaps
    ---@type {[1]: integer, [2]: integer}[]
    local consumed_ranges = {}
    ---@type { match: flemma.preprocessor.Match, handler: flemma.preprocessor.TextHandler, start_pos: integer, end_pos: integer }[]
    local accepted_matches = {}

    for _, raw_match in ipairs(all_matches) do
      if not overlaps_any(consumed_ranges, raw_match.start_pos, raw_match.end_pos) then
        local match = build_match(line, raw_match, current_line)
        table.insert(accepted_matches, {
          match = match,
          handler = raw_match.handler,
          start_pos = raw_match.start_pos,
          end_pos = raw_match.end_pos,
        })
        table.insert(consumed_ranges, { raw_match.start_pos, raw_match.end_pos })
      end
    end

    -- Sort accepted matches by start position for linear traversal
    table.sort(accepted_matches, function(a, b)
      return a.start_pos < b.start_pos
    end)

    if #accepted_matches == 0 then
      -- No matches on this line: accumulate text to minimize segment splitting
      if #accum_text == 0 then
        accum_start_line = current_line
        accum_start_col = 1
      end
      accum_text = accum_text .. line
      if line_index < #lines then
        accum_text = accum_text .. "\n"
      end
    else
      -- Has matches: flush accumulated text, then process matched line
      flush_accum()

      local line_pos = 1

      for _, accepted in ipairs(accepted_matches) do
        -- Emit preceding unmatched text
        if accepted.start_pos > line_pos then
          local preceding = line:sub(line_pos, accepted.start_pos - 1)
          emit_text(result_segments, preceding, current_line, line_pos)
        end

        -- Call handler with context
        local ctx = context_module.new({
          system = rewriter_state.system,
          frontmatter = rewriter_state.frontmatter,
          message = message_context.message,
          message_index = message_context.index,
          position = { line = current_line, col = accepted.start_pos },
          interactive = opts.interactive,
          _bufnr = opts.bufnr,
          _metadata = rewriter_state.metadata,
          _diagnostics = rewriter_state.diagnostics,
          _rewriter_name = rewriter_state.system._ctx and rewriter_state.system._ctx._rewriter_name,
        })
        rewriter_state.system:set_context(ctx)

        local handler_ok, emission = pcall(accepted.handler, accepted.match, ctx)

        if not handler_ok then
          -- Check if this is a Confirmation throw (re-throw it)
          if context_module.is_confirmation(emission) then
            error(emission)
          end
          -- Handler error — record diagnostic, leave text unchanged
          ctx:diagnostic("error", "handler error: " .. tostring(emission))
          emit_text(result_segments, accepted.match.full, current_line, accepted.start_pos)
        else
          -- Convert emission to segments
          local emission_segments = emission_to_segments(
            emission,
            { line = current_line, col = accepted.start_pos, end_line = current_line, end_col = accepted.end_pos },
            accepted.match.full,
            buffer_edits_accumulator,
            opts.interactive
          )
          for _, seg in ipairs(emission_segments) do
            table.insert(result_segments, seg)
          end
        end

        line_pos = accepted.end_pos + 1
      end

      -- Accumulate trailing text after the last match on this line
      local trailing = ""
      if line_pos <= #line then
        trailing = line:sub(line_pos)
      end
      if line_index < #lines then
        trailing = trailing .. "\n"
      end
      if #trailing > 0 then
        accum_text = trailing
        accum_start_line = current_line
        accum_start_col = line_pos
      end
    end

    if line_index < #lines then
      current_line = current_line + 1
    end
  end

  -- Flush any remaining accumulated text
  flush_accum()

  -- Attach buffer edits to the runner-level accumulator (stored in rewriter_state)
  if rewriter_state._buffer_edits then
    for _, edit in ipairs(buffer_edits_accumulator) do
      table.insert(rewriter_state._buffer_edits, edit)
    end
  end

  return result_segments
end

---Run segment handlers (on(kind)) on a single segment.
---@param segment flemma.ast.Segment The segment to process
---@param handlers flemma.preprocessor.SegmentHandlerEntry[] Segment handlers from the rewriter
---@param rewriter_state flemma.preprocessor.RewriterState Shared state for this rewriter
---@param opts flemma.preprocessor.RunOpts Pipeline options
---@param message_context flemma.preprocessor.MessageContext Current message iteration context
---@return flemma.ast.Segment[] result_segments
local function run_segment_handlers(segment, handlers, rewriter_state, opts, message_context)
  local matching_handlers = {}
  for _, entry in ipairs(handlers) do
    if entry.kind == segment.kind then
      table.insert(matching_handlers, entry)
    end
  end

  if #matching_handlers == 0 then
    return { segment }
  end

  -- Run the first matching handler (multiple handlers for same kind chain)
  local current_segments = { segment }

  for _, entry in ipairs(matching_handlers) do
    local next_segments = {} ---@type flemma.ast.Segment[]

    for _, seg in ipairs(current_segments) do
      if seg.kind ~= entry.kind then
        table.insert(next_segments, seg)
      else
        local position = seg.position or {}
        local ctx = context_module.new({
          system = rewriter_state.system,
          frontmatter = rewriter_state.frontmatter,
          message = message_context.message,
          message_index = message_context.index,
          position = { line = position.start_line, col = position.start_col },
          interactive = opts.interactive,
          _bufnr = opts.bufnr,
          _metadata = rewriter_state.metadata,
          _diagnostics = rewriter_state.diagnostics,
          _rewriter_name = rewriter_state.system._ctx and rewriter_state.system._ctx._rewriter_name,
        })
        rewriter_state.system:set_context(ctx)

        local handler_ok, emission = pcall(entry.handler, seg, ctx)

        if not handler_ok then
          if context_module.is_confirmation(emission) then
            error(emission)
          end
          ctx:diagnostic("error", "segment handler error: " .. tostring(emission))
          table.insert(next_segments, seg)
        else
          -- nil return means keep the original segment unchanged
          if emission == nil then
            table.insert(next_segments, seg)
          else
            local buffer_edits_accumulator = {} ---@type flemma.preprocessor.BufferEdit[]
            -- For segment handlers, original_text is the segment's value (for text) or code (for expression)
            local original_text = nil
            if seg.kind == "text" then
              ---@cast seg flemma.ast.TextSegment
              original_text = seg.value
            elseif seg.kind == "expression" then
              ---@cast seg flemma.ast.ExpressionSegment
              original_text = "{{" .. seg.code .. "}}"
            end

            local emission_segments = emission_to_segments(emission, {
              line = position.start_line or 1,
              col = position.start_col or 1,
              end_line = position.end_line,
              end_col = position.end_col,
            }, original_text, buffer_edits_accumulator, opts.interactive)

            if rewriter_state._buffer_edits then
              for _, edit in ipairs(buffer_edits_accumulator) do
                table.insert(rewriter_state._buffer_edits, edit)
              end
            end

            for _, new_seg in ipairs(emission_segments) do
              table.insert(next_segments, new_seg)
            end
          end
        end
      end
    end

    current_segments = next_segments
  end

  return current_segments
end

---Process a single segment through a rewriter's two phases:
---Phase 1: on_text handlers (text segments only)
---Phase 2: on(kind) handlers on ALL resulting segments
---@param segment flemma.ast.Segment The segment to process
---@param rewriter flemma.preprocessor.Rewriter The rewriter being executed
---@param rewriter_state flemma.preprocessor.RewriterState Shared state
---@param opts flemma.preprocessor.RunOpts Pipeline options
---@param message_context flemma.preprocessor.MessageContext Current message iteration context
---@return flemma.ast.Segment[]
local function process_segment(segment, rewriter, rewriter_state, opts, message_context)
  -- Phase 1: on_text handlers (only for text segments)
  local phase1_segments ---@type flemma.ast.Segment[]
  if segment.kind == "text" then
    ---@cast segment flemma.ast.TextSegment
    phase1_segments = run_text_handlers(segment, rewriter.text_handlers, rewriter_state, opts, message_context)
  else
    phase1_segments = { segment }
  end

  -- Phase 2: on(kind) handlers on ALL resulting segments
  if #rewriter.segment_handlers == 0 then
    return phase1_segments
  end

  local phase2_segments = {} ---@type flemma.ast.Segment[]
  for _, seg in ipairs(phase1_segments) do
    local handled = run_segment_handlers(seg, rewriter.segment_handlers, rewriter_state, opts, message_context)
    for _, result_seg in ipairs(handled) do
      table.insert(phase2_segments, result_seg)
    end
  end

  return phase2_segments
end

---Apply buffer edits to a buffer, sorted in reverse order.
---@param edits flemma.preprocessor.BufferEdit[] Edits to apply
---@param bufnr integer Buffer number
local function apply_buffer_edits(edits, bufnr)
  if #edits == 0 then
    return
  end

  -- Sort in reverse order (bottom-to-top) so earlier edits don't shift later ones
  table.sort(edits, function(a, b)
    if a.start_line == b.start_line then
      return a.start_col > b.start_col
    end
    return a.start_line > b.start_line
  end)

  buffer_util.with_modifiable(bufnr, function()
    for _, edit in ipairs(edits) do
      vim.api.nvim_buf_set_text(bufnr, edit.start_line, edit.start_col, edit.end_line, edit.end_col, edit.replacement)
    end
  end)
end

---Apply system accessor mutations to the document.
---Finds or creates a @System message and applies prepends/appends.
---@param doc flemma.ast.DocumentNode
---@param system_accessor flemma.preprocessor.SystemAccessor
local function apply_system_mutations(doc, system_accessor)
  local prepends = system_accessor:get_prepends()
  local appends = system_accessor:get_appends()

  if #prepends == 0 and #appends == 0 then
    return
  end

  -- Find or create the @System message
  local system_message = nil
  for _, msg in ipairs(doc.messages) do
    if msg.role == "System" then
      system_message = msg
      break
    end
  end

  if not system_message then
    -- Create a new @System message at the beginning
    system_message = ast.message("System", {}, { start_line = 1, end_line = 1 })
    table.insert(doc.messages, 1, system_message)
  end

  -- Apply prepends in reverse order (so first prepend ends up first)
  for i = #prepends, 1, -1 do
    local entry = prepends[i]
    local pos = entry.position or {}
    local segments = emission_to_segments(entry.emission, { line = pos.line or 1, col = pos.col or 1 }, nil, {}, false)
    for j = #segments, 1, -1 do
      table.insert(system_message.segments, 1, segments[j])
    end
  end

  -- Apply appends
  for _, entry in ipairs(appends) do
    local pos = entry.position or {}
    local segments = emission_to_segments(entry.emission, { line = pos.line or 1, col = pos.col or 1 }, nil, {}, false)
    for _, seg in ipairs(segments) do
      table.insert(system_message.segments, seg)
    end
  end
end

---Apply frontmatter accessor mutations to the document.
---Ensures a frontmatter node exists, then applies set/append/remove mutations.
---@param doc flemma.ast.DocumentNode
---@param frontmatter_accessor flemma.preprocessor.FrontmatterAccessor
local function apply_frontmatter_mutations(doc, frontmatter_accessor)
  local mutations = frontmatter_accessor:get_mutations()

  if #mutations == 0 then
    return
  end

  -- Ensure frontmatter exists
  if not doc.frontmatter then
    doc.frontmatter = ast.frontmatter("yaml", "", { start_line = 1, end_line = 1 })
  end

  local fm_lines = vim.split(doc.frontmatter.code, "\n", { plain = true })

  for _, mutation in ipairs(mutations) do
    if mutation.action == "set" then
      ---@cast mutation flemma.preprocessor.FrontmatterSetMutation
      -- Find existing key and replace, or append
      local found = false
      local value_str = type(mutation.value) == "string" and mutation.value or tostring(mutation.value)
      for li, fm_line in ipairs(fm_lines) do
        local key = fm_line:match("^(%S+):%s*")
        if key == mutation.key then
          fm_lines[li] = mutation.key .. ": " .. value_str
          found = true
          break
        end
      end
      if not found then
        table.insert(fm_lines, mutation.key .. ": " .. value_str)
      end
    elseif mutation.action == "append" then
      ---@cast mutation flemma.preprocessor.FrontmatterAppendMutation
      table.insert(fm_lines, mutation.line)
    elseif mutation.action == "remove" then
      ---@cast mutation flemma.preprocessor.FrontmatterRemoveMutation
      for li = #fm_lines, 1, -1 do
        local key = fm_lines[li]:match("^(%S+):%s*")
        if key == mutation.key then
          table.remove(fm_lines, li)
          break
        end
      end
    end
  end

  doc.frontmatter.code = table.concat(fm_lines, "\n")
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---Run the full preprocessor pipeline on a document.
---Iterates rewriters in priority order, processes each message's segments,
---applies system/frontmatter mutations after each rewriter, and applies
---buffer edits in interactive mode.
---@param doc flemma.ast.DocumentNode
---@param bufnr integer|nil Buffer number (required for interactive mode)
---@param opts flemma.preprocessor.RunOpts
---@return flemma.ast.DocumentNode result_doc
---@return flemma.preprocessor.RewriterDiagnostic[] diagnostics
function M.run_pipeline(doc, bufnr, opts)
  local all_diagnostics = {} ---@type flemma.preprocessor.RewriterDiagnostic[]
  local all_buffer_edits = {} ---@type flemma.preprocessor.BufferEdit[]

  for _, rewriter in ipairs(opts.rewriters) do
    local system_accessor = context_module.SystemAccessor.new()
    local frontmatter_accessor = context_module.FrontmatterAccessor.new()

    ---@type flemma.preprocessor.RewriterState
    local rewriter_state = {
      system = system_accessor,
      frontmatter = frontmatter_accessor,
      metadata = {},
      diagnostics = {},
      _buffer_edits = all_buffer_edits,
    }

    -- Set up a dummy context for the system accessor's rewriter name
    local name_ctx = context_module.new({
      _rewriter_name = rewriter.name,
      system = system_accessor,
      frontmatter = frontmatter_accessor,
    })
    system_accessor:set_context(name_ctx)

    -- Process each message's segments
    for message_index, message in ipairs(doc.messages) do
      ---@type flemma.preprocessor.MessageContext
      local message_context = { message = message, index = message_index }
      local new_segments = {} ---@type flemma.ast.Segment[]

      for _, segment in ipairs(message.segments) do
        local result_segs = process_segment(segment, rewriter, rewriter_state, opts, message_context)
        for _, seg in ipairs(result_segs) do
          table.insert(new_segments, seg)
        end
      end

      message.segments = new_segments
    end

    -- Apply system/frontmatter mutations
    apply_system_mutations(doc, system_accessor)
    apply_frontmatter_mutations(doc, frontmatter_accessor)

    -- Collect diagnostics from this rewriter
    for _, diag in ipairs(rewriter_state.diagnostics) do
      table.insert(all_diagnostics, diag)
    end
  end

  -- Apply buffer edits in interactive mode
  if opts.interactive and bufnr and #all_buffer_edits > 0 then
    apply_buffer_edits(all_buffer_edits, bufnr)
  end

  return doc, all_diagnostics
end

return M
