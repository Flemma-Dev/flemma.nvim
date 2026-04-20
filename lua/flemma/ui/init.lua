--- UI module for Flemma plugin
--- Handles visual presentation: rulers, progress indicators, and folding
---@class flemma.UI
local M = {}

local config_facade = require("flemma.config")
local log = require("flemma.logging")
local state = require("flemma.state")
local buffer_utils = require("flemma.utilities.buffer")
local preview = require("flemma.ui.preview")
local folding = require("flemma.ui.folding")
local roles = require("flemma.utilities.roles")
local bridge = require("flemma.bridge")
local migration = require("flemma.migration")
local parser = require("flemma.parser")
local processor = require("flemma.processor")
local cursor = require("flemma.cursor")
local writequeue = require("flemma.buffer.writequeue")
local str = require("flemma.utilities.string")
local ast = require("flemma.ast")
local spinners = require("flemma.ui.spinners")
local turns = require("flemma.ui.turns")
local Bar = require("flemma.ui.bar")

-- Extmark priority constants
-- Higher values take precedence when multiple extmarks overlap on the same line.
-- The hierarchy from lowest to highest:
--   1. LINE_HIGHLIGHT (50)      - Base backgrounds for messages and frontmatter
--   2. THINKING_BLOCK (100)     - Thinking block backgrounds, overrides message line highlights
--   3. CURSORLINE (125)         - CursorLine overlay, blends with underlying line highlights
--   4. THINKING_TAG (200)       - Text styling for <thinking> and </thinking> tags
--   5. SPINNER (300)            - Progress line, highest priority to suppress spell checking
local PRIORITY = {
  LINE_HIGHLIGHT = 50,
  THINKING_BLOCK = 100,
  CURSORLINE = 125,
  THINKING_TAG = 200,
  TOOL_EXECUTION = 250,
  SPINNER = 300,
}

---@type string
local WAITING_LABEL = "Waiting…"

---@type string
local MIDDLE_DOT = " · "

-- Define namespace for our extmarks
local ns_id = vim.api.nvim_create_namespace("flemma")
local spinner_ns = vim.api.nvim_create_namespace("flemma_spinner")
local line_hl_ns = vim.api.nvim_create_namespace("flemma_line_highlights")
local cursorline_ns = vim.api.nvim_create_namespace("flemma_cursorline")
local thinking_ns = vim.api.nvim_create_namespace("flemma_thinking_tags")
local tool_exec_ns = vim.api.nvim_create_namespace("flemma_tool_execution")
local tool_preview_ns = vim.api.nvim_create_namespace("flemma_tool_preview")

---@class flemma.ui.ToolIndicator
---@field extmark_id integer
---@field timer integer|nil

---Get or initialize the tool indicators table for a buffer
---@param bufnr integer
---@return table<string, flemma.ui.ToolIndicator>
local function get_tool_indicators(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if not buffer_state.tool_indicators then
    buffer_state.tool_indicators = {}
  end
  return buffer_state.tool_indicators
end

--- Execute a command in the context of a buffer's window
---@param bufnr number Buffer number
---@param cmd string Command to execute
function M.buffer_cmd(bufnr, cmd)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end
  vim.fn.win_execute(winid, "noautocmd " .. cmd)
end

---Add rulers merged with role marker lines
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.add_rulers(bufnr, doc)
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local current_config = config_facade.get(bufnr)
  local ruler_config = current_config.ruler
  if ruler_config.enabled == false then
    return
  end

  -- Get the window displaying this buffer to calculate correct ruler width
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end

  local win_width = vim.api.nvim_win_get_width(winid)

  local progress_line = state.get_buffer_state(bufnr).progress_last_line

  for _, msg in ipairs(doc.messages) do
    local line_idx = msg.position.start_line - 1
    if line_idx >= 0 and line_idx < vim.api.nvim_buf_line_count(bufnr) then
      -- Use the AST role directly — only recognized roles (You, System, Assistant) get rulers
      local role_name = msg.role
      local colon_col = 1 + #role_name -- position of ':' in @Role:

      -- Replace @ with ruler char
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 0, {
        virt_text = { { ruler_config.char, "FlemmaRuler" } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
      })

      -- Insert a non-editable space between ruler char and the role name
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 1, {
        virt_text = { { " ", "FlemmaRuler" } },
        virt_text_pos = "inline",
        hl_mode = "combine",
      })

      -- Apply role style to just the name text (not the ruler chars)
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 1, {
        end_col = colon_col,
        hl_group = roles.highlight_group("FlemmaRole", role_name) .. "Name",
        hl_mode = "combine",
      })

      -- On the progress line, only replace : with a space (no ruler extension)
      -- so the EOL progress text isn't covered by overlay chars.
      -- On all other lines, extend ruler chars to the window edge.
      if line_idx == progress_line then
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, colon_col, {
          virt_text = { { " ", "FlemmaRuler" } },
          virt_text_pos = "overlay",
          hl_mode = "combine",
        })
      else
        local inline_space = 1 -- inserted space between ruler char and role name
        local remaining = math.max(0, win_width - colon_col - 1 - inline_space)
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, colon_col, {
          virt_text = { { " " .. string.rep(ruler_config.char, remaining), "FlemmaRuler" } },
          virt_text_pos = "overlay",
          hl_mode = "combine",
        })
      end
    end
  end
end

---Highlight thinking tags and blocks using extmarks (higher priority than Treesitter)
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.highlight_thinking_tags(bufnr, doc)
  -- Clear existing thinking tag highlights
  vim.api.nvim_buf_clear_namespace(bufnr, thinking_ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Iterate through messages and their segments to find thinking blocks
  for _, msg in ipairs(doc.messages) do
    if msg.segments then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "thinking" and seg.position then
          -- Apply range extmark for thinking block background
          local start_idx = seg.position.start_line - 1
          local end_idx = (seg.position.end_line or seg.position.start_line) - 1
          if start_idx >= 0 and end_idx < #lines then
            vim.api.nvim_buf_set_extmark(bufnr, thinking_ns, start_idx, 0, {
              end_row = end_idx,
              end_col = #lines[end_idx + 1],
              line_hl_group = "FlemmaThinkingBlock",
              priority = PRIORITY.THINKING_BLOCK,
            })
          end

          -- Highlight opening tag text
          vim.api.nvim_buf_set_extmark(bufnr, thinking_ns, seg.position.start_line - 1, 0, {
            end_line = seg.position.start_line,
            hl_group = "FlemmaThinkingTag",
            priority = PRIORITY.THINKING_TAG,
          })
          -- Highlight closing tag text
          if seg.position.end_line then
            vim.api.nvim_buf_set_extmark(bufnr, thinking_ns, seg.position.end_line - 1, 0, {
              end_line = seg.position.end_line,
              hl_group = "FlemmaThinkingTag",
              priority = PRIORITY.THINKING_TAG,
            })
          end
        end
      end
    end
  end
end

---Build virtual text chunks for the progress line.
---@param progress_text string The formatted progress text (e.g., "⠋ Waiting… · 3s")
---@param bufnr integer
---@param highlight? string Override highlight group (for timeout warnings)
---@return {[1]:string, [2]:string}[]
local function build_progress_virt_text(progress_text, bufnr, highlight)
  local current_config = config_facade.get(bufnr)
  local ruler_config = current_config.ruler
  local rulers_enabled = ruler_config and ruler_config.enabled ~= false

  local prefix = rulers_enabled and "" or " "
  local hl = highlight or "FlemmaAssistantSpinner"
  ---@type {[1]:string, [2]:string}[]
  local chunks = { { prefix .. progress_text, hl } }

  if rulers_enabled then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      local win_width = vim.api.nvim_win_get_width(winid)
      table.insert(chunks, { " " .. string.rep(ruler_config.char, win_width), "FlemmaRuler" })
    end
  end

  return chunks
end

---Return the warning highlight group to apply when approaching timeout.
---Matches the two-tier threshold already used inline:
---  >= 90% elapsed -> DiagnosticError
---  >= 80% elapsed -> DiagnosticWarn
---  else           -> nil (neutral)
---Also returns the updated text (may append "timeout in Xs").
---@param bs flemma.state.BufferState
---@param base_text string
---@return string text
---@return string|nil highlight
local function timeout_pressure(bs, base_text)
  local timeout = bs.progress_timeout
  if not (timeout and timeout > 0 and bs.progress_started_at) then
    return base_text, nil
  end
  local elapsed_seconds = (vim.uv.now() - bs.progress_started_at) / 1000
  local pct = elapsed_seconds / timeout
  if pct >= 0.9 then
    local remaining = math.max(0, math.floor(timeout - elapsed_seconds))
    return base_text .. MIDDLE_DOT .. "timeout in " .. str.format_elapsed(remaining), "DiagnosticError"
  elseif pct >= 0.8 then
    local remaining = math.max(0, math.floor(timeout - elapsed_seconds))
    return base_text .. MIDDLE_DOT .. "timeout in " .. str.format_elapsed(remaining), "DiagnosticWarn"
  end
  return base_text, nil
end

---Produce the progress body (label + elapsed, optionally char count) without
---the leading spinner glyph. The spinner is the Bar's `icon` or a prepended
---chunk on the inline virt_text path — it is never baked into the body so the
---two rendering paths can share one source of truth without duplicating glyphs.
---@param bs flemma.state.BufferState
---@return string
local function format_progress_body(bs)
  local phase = bs.progress_phase or "waiting"
  local elapsed_seconds = 0
  if bs.progress_started_at then
    elapsed_seconds = (vim.uv.now() - bs.progress_started_at) / 1000
  end
  local elapsed_str = str.format_elapsed(elapsed_seconds)

  if phase == "waiting" then
    return WAITING_LABEL .. MIDDLE_DOT .. elapsed_str
  else
    local count = bs.progress_char_count or 0
    local suffix = count == 1 and " character" or " characters"
    local count_str = str.format_text_length(count) .. suffix
    return count_str .. MIDDLE_DOT .. elapsed_str
  end
end

---Set the inline "Waiting"/"Thinking" virt_text extmark on the
---@Assistant: line. Stable id via buffer_state.progress_extmark_id.
---@param bufnr integer
---@param text string Progress text (spinner + label + elapsed, optionally timeout)
---@param highlight? string Override highlight group (nil in neutral state)
local function update_inline_waiting_extmark(bufnr, text, highlight)
  local bs = state.get_buffer_state(bufnr)
  local target_line = bs.progress_last_line
  local ext_id = bs.progress_extmark_id
  if target_line == nil or ext_id == nil then
    return
  end
  local chunks = build_progress_virt_text(text, bufnr, highlight)
  pcall(vim.api.nvim_buf_set_extmark, bufnr, spinner_ns, target_line, 0, {
    id = ext_id,
    virt_text = chunks,
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY.SPINNER,
    spell = false,
  })
end

---Wrap a flat progress text into a minimal single-item segment list.
---warn_hl is nil in neutral state (no extmark emitted) or a diagnostic
---group name during timeout pressure.
---@param text string
---@param warn_hl string|nil
---@return flemma.ui.bar.layout.Segment[]
local function progress_segments(text, warn_hl)
  return {
    {
      key = "progress",
      items = {
        {
          key = "text",
          text = text,
          priority = 1,
          highlight = warn_hl and { group = warn_hl } or nil,
        },
      },
    },
  }
end

---Get or create the progress Bar for a buffer.
---@param bufnr integer
---@return flemma.ui.bar.Bar
local function ensure_progress_bar(bufnr)
  local bs = state.get_buffer_state(bufnr)
  if bs.progress_bar and not bs.progress_bar:is_dismissed() then
    return bs.progress_bar
  end
  local cfg = config_facade.get(bufnr).ui.progress
  local frames = spinners.FRAMES[bs.progress_phase or "waiting"] or spinners.FRAMES.waiting
  bs.progress_bar = Bar.new({
    bufnr = bufnr,
    position = cfg.position,
    segments = progress_segments("", nil),
    icon = frames[1],
    -- Same reasoning as usage.show: paint with FlemmaProgressBar
    -- (derived by highlight.lua from cfg.highlight) so attributes on
    -- the user's resolved chain group do NOT leak. cfg.highlight stays
    -- as a fallback tail.
    highlight = "FlemmaProgressBar," .. cfg.highlight,
    on_dismiss = function()
      local inner = state.get_buffer_state(bufnr)
      inner.progress_bar = nil
    end,
  })
  return bs.progress_bar
end

---@param bufnr integer
local function dismiss_progress_bar(bufnr)
  local bs = state.get_buffer_state(bufnr)
  if bs.progress_bar then
    bs.progress_bar:dismiss()
    bs.progress_bar = nil
  end
end

---Per-tick advance. Preserves today's behaviour exactly:
---  waiting / thinking  -> inline virt_text + Bar only when off-screen
---  streaming / buffering -> Bar only (clears leftover inline extmark)
---@param bufnr integer
local function advance_progress(bufnr)
  local bs = state.get_buffer_state(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not bs.current_request then
    return
  end

  bs.progress_tick = (bs.progress_tick or 0) + 1

  local phase = bs.progress_phase or "waiting"
  local frames = spinners.FRAMES[phase]
  local speed = spinners.SPEED[phase] or 1
  local frame = frames[(math.floor(bs.progress_tick / speed) % #frames) + 1]

  local base_body = format_progress_body(bs)
  local body, warn_hl = timeout_pressure(bs, base_body)

  if phase == "waiting" or phase == "thinking" then
    -- Inline virt_text is a flat chunk list with no icon slot; prepend the
    -- spinner to the body so the `@Assistant:` line shows `<spinner> <body>`.
    update_inline_waiting_extmark(bufnr, frame .. " " .. body, warn_hl)

    local winid = vim.fn.bufwinid(bufnr)
    local off_screen = winid ~= -1 and bs.progress_last_line and (bs.progress_last_line + 1) > vim.fn.line("w$", winid)

    if off_screen then
      ensure_progress_bar(bufnr):update({
        icon = frame,
        segments = progress_segments(body, warn_hl),
      })
    else
      dismiss_progress_bar(bufnr)
    end
    return
  end

  -- streaming / buffering: clear any leftover inline extmark; Bar only.
  if bs.progress_extmark_id ~= nil then
    vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, 0, -1)
    bs.progress_extmark_id = nil
  end

  ensure_progress_bar(bufnr):update({
    icon = frame,
    segments = progress_segments(body, warn_hl),
  })
end

---Start the progress line for a new request.
---Creates the waiting-phase extmark on the @Assistant: line and starts the
---100ms animation timer. The timer reads all progress state from buffer_state
---exclusively — no closure-local copies of extmark IDs or line positions.
---@param bufnr integer
---@param progress_opts { force?: boolean, timeout: integer }
---@return integer timer_id
function M.start_progress(bufnr, progress_opts)
  local buffer_state = state.get_buffer_state(bufnr)

  -- Initialize progress state
  buffer_state.progress_phase = "waiting"
  buffer_state.progress_char_count = 0
  buffer_state.progress_started_at = vim.uv.now()
  buffer_state.progress_timeout = progress_opts.timeout
  buffer_state.progress_extmark_id = nil
  buffer_state.progress_last_line = nil
  buffer_state.progress_tick = 0

  writequeue.schedule(bufnr, function()
    buffer_utils.with_modifiable(bufnr, function()
      -- Clear any existing virtual text
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
      vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, 0, -1)

      -- Write @Assistant: on its own line so the parser recognises it as a message
      local last_line = buffer_utils.get_last_line(bufnr)
      if last_line:match("%S") then
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "@Assistant:" })
      else
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant:" })
      end

      -- Create the waiting-phase extmark (virt_text at EOL on @Assistant: line)
      local progress_line_idx0 = vim.api.nvim_buf_line_count(bufnr) - 1
      local frames = spinners.FRAMES.waiting
      local spinner_char = frames[1]
      local progress_text = spinner_char .. " " .. WAITING_LABEL .. MIDDLE_DOT .. "0s"
      local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, spinner_ns, progress_line_idx0, 0, {
        virt_text = build_progress_virt_text(progress_text, bufnr),
        virt_text_pos = "eol",
        hl_mode = "combine",
        priority = PRIORITY.SPINNER,
        spell = false,
      })

      buffer_state.progress_extmark_id = extmark_id
      buffer_state.progress_last_line = progress_line_idx0

      -- Immediately update UI and position cursor
      M.update_ui(bufnr)
      local is_user_send = progress_opts ~= nil and progress_opts.force
      cursor.request_move(bufnr, {
        line = vim.api.nvim_buf_line_count(bufnr),
        bottom = true,
        force = is_user_send,
        reason = is_user_send and "progress/user-send" or "progress/autopilot",
      })
    end)
  end)

  local timer = vim.fn.timer_start(100, function()
    advance_progress(bufnr)
  end, { ["repeat"] = -1 })

  buffer_state.progress_timer = timer
  return timer
end

---Clean up progress line and prepare for response completion.
---Handles both waiting phase (inline virt_text) and streaming/buffering phase (float).
---@param bufnr integer
function M.cleanup_progress(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  buffer_utils.with_modifiable(bufnr, function()
    local buffer_state = state.get_buffer_state(bufnr)
    if buffer_state.progress_timer then
      vim.fn.timer_stop(buffer_state.progress_timer)
      buffer_state.progress_timer = nil
    end

    -- Close the progress float if open
    dismiss_progress_bar(bufnr)

    -- Clear progress state
    buffer_state.progress_phase = nil
    buffer_state.progress_char_count = 0
    buffer_state.progress_started_at = nil
    buffer_state.progress_timeout = nil
    buffer_state.progress_extmark_id = nil
    buffer_state.progress_last_line = nil
    buffer_state.progress_tick = nil

    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, 0, -1)

    local last_line_content, line_count = buffer_utils.get_last_line(bufnr)
    if line_count == 0 then
      M.update_ui(bufnr)
      return
    end

    -- Only modify lines if the last line is the empty @Assistant: progress placeholder.
    if last_line_content and last_line_content == "@Assistant:" then
      M.buffer_cmd(bufnr, "undojoin")

      local prev_line_actual_content = nil
      if line_count > 1 then
        prev_line_actual_content = buffer_utils.get_line(bufnr, line_count - 1)
      end

      if prev_line_actual_content and prev_line_actual_content:match("%S") then
        vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, { "" })
      else
        vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, {})
      end
    else
      log.debug("cleanup_progress(): Last line is not the progress placeholder, not modifying lines.")
    end

    M.update_ui(bufnr)
  end)
end

---Apply full-line background highlighting for messages and frontmatter
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.apply_line_highlights(bufnr, doc)
  local current_config = config_facade.get(bufnr)
  if not current_config.line_highlights or not current_config.line_highlights.enabled then
    return
  end

  -- Clear existing line highlights
  vim.api.nvim_buf_clear_namespace(bufnr, line_hl_ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Highlight frontmatter if present
  if doc.frontmatter and doc.frontmatter.position then
    local start_idx = doc.frontmatter.position.start_line - 1
    local end_idx = (doc.frontmatter.position.end_line or doc.frontmatter.position.start_line) - 1
    if start_idx >= 0 and end_idx < #lines then
      vim.api.nvim_buf_set_extmark(bufnr, line_hl_ns, start_idx, 0, {
        end_row = end_idx,
        end_col = #lines[end_idx + 1],
        line_hl_group = "FlemmaLineFrontmatter",
        priority = PRIORITY.LINE_HIGHLIGHT,
      })
    end
  end

  -- Highlight messages with range extmarks (one per message)
  for _, msg in ipairs(doc.messages) do
    local hl_group = roles.highlight_group("FlemmaLine", msg.role)
    local start_idx = msg.position.start_line - 1
    local end_idx = (msg.position.end_line or msg.position.start_line) - 1
    if start_idx >= 0 and end_idx < #lines then
      vim.api.nvim_buf_set_extmark(bufnr, line_hl_ns, start_idx, 0, {
        end_row = end_idx,
        end_col = #lines[end_idx + 1],
        end_right_gravity = true,
        line_hl_group = hl_group,
        priority = PRIORITY.LINE_HIGHLIGHT,
      })
    end
  end

  -- Invalidate cursorline cache so update_cursorline() (called later in
  -- update_ui) re-evaluates with the new highlight groups instead of
  -- hitting the same-row early return.
  state.get_buffer_state(bufnr).cursorline_prev_row = nil
end

---Remove the CursorLine overlay extmark for a buffer.
---@param bufnr integer
local function remove_cursorline(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local eid = buffer_state.cursorline_extmark_id
  if eid then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, cursorline_ns, eid)
    buffer_state.cursorline_extmark_id = nil
  end
  buffer_state.cursorline_prev_row = nil
end

---Check whether a window is a floating window.
---@param winid integer
---@return boolean
local function is_floating_window(winid)
  local ok, win_config = pcall(vim.api.nvim_win_get_config, winid)
  return ok and win_config.relative ~= nil and win_config.relative ~= ""
end

---Update the CursorLine overlay extmark for the current cursor position.
---Finds the line highlight (or thinking block) under the cursor and places
---a higher-priority extmark with the blended CursorLine variant.
---Uses a stable extmark ID to update in-place (no clear-and-recreate).
---Queries the buffer's own window for cursor position and cursorline state,
---so it works correctly even when focus is in a floating window.
---NOTE: bufwinid() returns only the first window displaying the buffer;
---if the same .chat buffer is open in multiple splits, only one gets the overlay.
---@param bufnr integer
local function update_cursorline(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end

  local row = vim.api.nvim_win_get_cursor(winid)[1] - 1 -- 0-indexed

  -- Check cursorline on the buffer's own window, not whichever window has focus
  if not vim.wo[winid].cursorline then
    remove_cursorline(bufnr)
    return
  end

  -- Only show overlay when the buffer's window is "active": either focused directly
  -- or focus is in a transient floating window (completion menu, hover, etc.)
  local current_win = vim.api.nvim_get_current_win()
  if current_win ~= winid then
    if not is_floating_window(current_win) then
      remove_cursorline(bufnr)
      return
    end
  end

  local buffer_state = state.get_buffer_state(bufnr)

  -- Skip if cursor hasn't moved to a different line
  if row == buffer_state.cursorline_prev_row then
    return
  end
  buffer_state.cursorline_prev_row = row

  -- Find the line highlight group at the cursor row
  ---@type string|nil
  local target_hl_group

  -- Check thinking blocks namespace first (higher visual priority)
  local thinking_marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    thinking_ns,
    { row, 0 },
    { row, 0 },
    { details = true, overlap = true }
  )
  for _, mark in ipairs(thinking_marks) do
    local details = mark[4]
    if details and details.line_hl_group then
      target_hl_group = details.line_hl_group .. "CursorLine"
      break
    end
  end

  -- Check line highlights namespace
  if not target_hl_group then
    local line_marks = vim.api.nvim_buf_get_extmarks(
      bufnr,
      line_hl_ns,
      { row, 0 },
      { row, 0 },
      { details = true, overlap = true }
    )
    for _, mark in ipairs(line_marks) do
      local details = mark[4]
      if details and details.line_hl_group then
        target_hl_group = details.line_hl_group .. "CursorLine"
        break
      end
    end
  end

  if target_hl_group then
    ---@type vim.api.keyset.set_extmark
    local opts = {
      line_hl_group = target_hl_group,
      priority = PRIORITY.CURSORLINE,
    }
    local eid = buffer_state.cursorline_extmark_id
    if eid then
      opts.id = eid
    end
    buffer_state.cursorline_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, cursorline_ns, row, 0, opts)
  else
    remove_cursorline(bufnr)
  end
end

-- Updatetime management state
-- We use reference counting to track how many chat buffers are "active"
-- (i.e., currently being displayed in a window). Only restore updatetime
-- when the last active chat buffer is left.
local updatetime_state = {
  original = nil, -- The original updatetime before any chat buffer was entered
  active_chat_buffers = {}, -- Set of bufnr that are currently active (in a window)
}

---Count active chat buffers
---@return integer
local function count_active_chat_buffers()
  local count = 0
  for _ in pairs(updatetime_state.active_chat_buffers) do
    count = count + 1
  end
  return count
end

---Parse the `editing.conceal` format `{conceallevel}{concealcursor}` into a
---pair. Accepts string (`"2n"`), integer (`2`), or boolean/nil (skip).
---Returns nil when parsing should skip the override (unset/false/malformed).
---@param value string|integer|boolean|nil
---@return { level: integer, cursor: string }|nil
local function parse_conceal_override(value)
  if value == nil or value == false then
    return nil
  end
  local spec = tostring(value)
  local level_str, cursor_chars = spec:match("^(%d)(.*)$")
  if not level_str then
    return nil
  end
  return { level = tonumber(level_str), cursor = cursor_chars or "" }
end

---Apply window-local settings for a chat buffer displayed in a window.
---Sets `conceallevel` and `concealcursor` from `editing.conceal`. A nil/false
---value leaves whatever the user/colorscheme has configured alone.
---@param winid integer Window ID
---@param bufnr integer Buffer displayed in the window
function M.apply_chat_window_settings(winid, bufnr)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  local cfg = config_facade.get(bufnr)
  local parsed = cfg and cfg.editing and parse_conceal_override(cfg.editing.conceal)
  if not parsed then
    return
  end
  vim.api.nvim_set_option_value("conceallevel", parsed.level, { win = winid })
  vim.api.nvim_set_option_value("concealcursor", parsed.cursor, { win = winid })
end

---Apply buffer-local settings for chat files, plus window-local settings for
---whatever window currently hosts the buffer.
---@param bufnr integer Buffer number
local function apply_chat_buffer_settings(bufnr)
  folding.setup_folding(bufnr)
  turns.setup_statuscolumn(bufnr)

  local current = config_facade.get(bufnr)
  if current and current.editing and current.editing.disable_textwidth then
    vim.bo[bufnr].textwidth = 0
  end

  -- Enable gf / <C-w>f navigation for @./file references and {{ include() }} expressions.
  -- Extend isfname so Neovim's gf extracts a candidate that covers the full {{ ... }}
  -- expression — without these, cursor on ), }, or { wouldn't trigger includeexpr.
  for character in ("{()}"):gmatch(".") do
    vim.opt_local.isfname:append(character)
  end
  vim.bo[bufnr].includeexpr = 'v:lua.require("flemma.navigation").resolve_include_path_expr()'

  -- Apply window-scoped options (conceal) to whichever window currently shows
  -- the buffer. Our BufRead/BufNewFile and FileType callbacks always fire in
  -- that window, so bufwinid resolves correctly.
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    M.apply_chat_window_settings(winid, bufnr)
  end
end

---Set up chat filetype autocmds
function M.setup_chat_filetype_autocmds()
  -- Create or clear the augroup for all chat-related autocmds
  local augroup = vim.api.nvim_create_augroup("FlemmaChat", { clear = true })

  -- Reset updatetime state when re-initializing
  updatetime_state = {
    original = nil,
    active_chat_buffers = {},
  }

  -- Handle .chat file detection
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = augroup,
    pattern = "*.chat",
    desc = "Flemma: migrate legacy .chat, set filetype, apply buffer+window settings",
    callback = function(ev)
      -- Clear any orphaned cursorline extmark from a prior session.
      -- :e reload fires BufUnload first, which calls cleanup_buffer_state() and
      -- sets buffer_states[bufnr] = nil — losing cursorline_extmark_id. The
      -- actual extmark in cursorline_ns survives the reload (extmarks are owned
      -- by the buffer object, not the text), leaving a permanently highlighted
      -- line that no code path can remove. Clearing the namespace here runs
      -- once per reload, not on every cursor move.
      vim.api.nvim_buf_clear_namespace(ev.buf, cursorline_ns, 0, -1)
      migration.migrate_buffer(ev.buf)
      vim.bo[ev.buf].filetype = "chat"
      apply_chat_buffer_settings(ev.buf)
      bridge.auto_prompt(ev.buf)
    end,
  })

  -- Handle manual filetype changes to 'chat'
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "chat",
    desc = "Flemma: apply buffer+window settings on filetype=chat",
    callback = function(ev)
      apply_chat_buffer_settings(ev.buf)
    end,
  })

  -- The frontmatter fold rule reads `vim.wo.conceallevel` to decide whether
  -- to fold (see lua/flemma/ui/folding/rules/frontmatter.lua). The fold map
  -- cache is keyed on changedtick + bufnr, so a bare conceallevel flip
  -- wouldn't invalidate it. Rebuild on conceallevel changes in chat windows.
  vim.api.nvim_create_autocmd("OptionSet", {
    group = augroup,
    pattern = "conceallevel",
    desc = "Flemma: rebuild fold map when conceallevel changes in a chat buffer",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if vim.bo[bufnr].filetype == "chat" then
        folding.invalidate_folds(bufnr)
      end
    end,
  })

  -- Handle updatetime management for chat buffers
  local editing_config = config_facade.get()
  if editing_config and editing_config.editing and editing_config.editing.manage_updatetime then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = augroup,
      pattern = "*.chat",
      callback = function(ev)
        local bufnr = ev.buf

        -- Save original updatetime on first chat buffer activation
        if updatetime_state.original == nil then
          updatetime_state.original = vim.o.updatetime
        end

        -- Mark this buffer as active
        updatetime_state.active_chat_buffers[bufnr] = true

        -- Set fast updatetime for chat buffers
        vim.o.updatetime = 100
      end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
      group = augroup,
      pattern = "*.chat",
      callback = function(ev)
        local bufnr = ev.buf

        -- Remove this buffer from active set
        updatetime_state.active_chat_buffers[bufnr] = nil

        -- Use vim.schedule to defer the check - this allows BufEnter on the
        -- next buffer to fire first, so we can see if we're switching to another
        -- chat buffer (in which case we shouldn't restore updatetime)
        vim.schedule(function()
          -- Only restore updatetime if no more active chat buffers
          if count_active_chat_buffers() == 0 and updatetime_state.original ~= nil then
            vim.o.updatetime = updatetime_state.original
            updatetime_state.original = nil
          end
        end)
      end,
    })

    -- Also clean up when buffers are deleted
    vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload", "BufDelete" }, {
      group = augroup,
      pattern = "*.chat",
      callback = function(ev)
        local bufnr = ev.buf
        updatetime_state.active_chat_buffers[bufnr] = nil

        -- Use vim.schedule here too for consistency
        vim.schedule(function()
          -- Restore if this was the last active chat buffer
          if count_active_chat_buffers() == 0 and updatetime_state.original ~= nil then
            vim.o.updatetime = updatetime_state.original
            updatetime_state.original = nil
          end
        end)
      end,
    })
  end

  -- CursorLine overlay: swap line highlight to blended CursorLine variant under cursor
  local current_config = config_facade.get()
  if current_config.line_highlights and current_config.line_highlights.enabled then
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = augroup,
      pattern = "*.chat",
      callback = function(ev)
        update_cursorline(ev.buf)
      end,
    })

    -- Re-apply overlay when entering a chat window (including first entry
    -- where cursorline_prev_row is nil and the global WinEnter would skip it).
    vim.api.nvim_create_autocmd("WinEnter", {
      group = augroup,
      pattern = "*.chat",
      callback = function(ev)
        update_cursorline(ev.buf)
      end,
    })

    -- Global WinEnter: re-evaluate cursorline overlays for chat buffers that have one.
    -- When entering a regular (non-float) window, overlays on unfocused chat windows
    -- are cleared. When entering a floating window (completion menu, hover, etc.),
    -- overlays persist — the user is still conceptually in the chat window.
    -- No WinLeave handler is needed: the overlay persists untouched until WinEnter
    -- re-evaluates, avoiding any rendering frame where it's missing.
    vim.api.nvim_create_autocmd("WinEnter", {
      group = augroup,
      callback = function()
        for bufnr, buffer_state in state.each_buffer_state() do
          if buffer_state.cursorline_prev_row and vim.api.nvim_buf_is_valid(bufnr) then
            update_cursorline(bufnr)
          end
        end
      end,
    })

    -- React to :set cursorline / :set nocursorline / :setlocal variants.
    -- Ignore changes originating from floating windows (e.g., blink-cmp
    -- setting cursorline on its completion menu), which fire OptionSet
    -- but don't affect the chat window's cursorline state.
    vim.api.nvim_create_autocmd("OptionSet", {
      group = augroup,
      pattern = "cursorline",
      callback = function()
        if is_floating_window(vim.api.nvim_get_current_win()) then
          return -- Change originated from a floating window; ignore
        end

        -- Re-evaluate overlays for all chat buffers (not just those with an
        -- active overlay — :set cursorline needs to CREATE overlays too)
        for bufnr in state.each_buffer_state() do
          if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "chat" then
            update_cursorline(bufnr)
          end
        end
      end,
    })
  end
end

---Add virtual line previews inside empty tool_result fences that carry a
---lifecycle (status) suffix in the header. Shows a compact summary of the
---tool call (name + input) so users can see what they're approving/rejecting
---without the content being editable.
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.add_tool_previews(bufnr, doc)
  vim.api.nvim_buf_clear_namespace(bufnr, tool_preview_ns, 0, -1)

  local siblings = ast.build_tool_sibling_table(doc)

  -- Compute available text width from the buffer's window
  local winid = vim.fn.bufwinid(bufnr)
  local max_length = preview.get_text_area_width(winid)

  -- At conceallevel>=1, tree-sitter's markdown highlights query hides the
  -- fenced_code_block_delimiter lines entirely via `#set! conceal_lines ""`,
  -- taking any extmarks anchored to those lines (including our virt_lines)
  -- with them. Anchor one line higher — on the blank line between the
  -- `**Tool Result:**` header and the opening fence, which carries no conceal
  -- metadata — so the preview survives. At conceallevel=0 the fences render
  -- normally and we keep the original inside-the-fence position.
  local conceal_level = 0
  if winid ~= -1 then
    conceal_level = vim.api.nvim_get_option_value("conceallevel", { win = winid })
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Show previews for tool_result blocks with empty content that are either
  -- pending/approved (have a lifecycle status suffix) or currently executing (have active indicator).
  -- Without the indicator check, the preview disappears when the executor
  -- clears the header status suffix at execution start.
  local indicators = get_tool_indicators(bufnr)

  for _, msg in ipairs(doc.messages) do
    if roles.is_user(msg.role) then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" and seg.content == "" and (seg.status or indicators[seg.tool_use_id]) then
          local sibling = siblings[seg.tool_use_id]
          local tool_use = sibling and sibling.use or nil
          if tool_use then
            -- Opening fence is one line before closing fence (empty content)
            local opening_fence_line = seg.position.end_line - 1
            local line_idx
            if conceal_level >= 1 then
              line_idx = opening_fence_line - 2 -- 0-indexed: blank line before fence
            else
              line_idx = opening_fence_line - 1 -- 0-indexed: opening fence line
            end

            if line_idx >= 0 and line_idx < line_count then
              local preview_text = preview.format_tool_preview(tool_use.name, tool_use.input, max_length)
              vim.api.nvim_buf_set_extmark(bufnr, tool_preview_ns, line_idx, 0, {
                virt_lines = { { { preview_text, "FlemmaToolPreview" } } },
              })
            end
          end
        end
      end
    end
  end
end

---Force UI update (rulers, line highlights, and turn indicators)
---@param bufnr integer
function M.update_ui(bufnr)
  -- Ensure buffer is valid before proceeding
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.debug("update_ui(): Invalid buffer: " .. bufnr)
    return
  end

  -- Bail if config is not fully initialized (e.g. in test environments)
  local current_config = config_facade.get(bufnr)
  if not current_config.ruler then
    return
  end

  -- Parse messages using AST
  local doc = parser.get_parsed_document(bufnr)

  M.add_rulers(bufnr, doc)
  M.highlight_thinking_tags(bufnr, doc)
  M.apply_line_highlights(bufnr, doc)
  M.add_tool_previews(bufnr, doc)
  -- Note: progress extmark (with spell suppression) is managed by start_progress and its timer

  -- Re-apply CursorLine overlay now that line highlights are refreshed,
  -- so the blend reflects the current AST state instead of the pre-edit state.
  update_cursorline(bufnr)

  folding.invalidate_folds(bufnr)
  folding.fold_completed_blocks(bufnr)
  turns.update(bufnr)
end

-- ============================================================================
-- Tool Execution Indicators
-- ============================================================================

--- Get the current line of a tool execution extmark (auto-adjusted by Neovim)
---@param bufnr integer
---@param extmark_id integer
---@return integer|nil 0-based line index, or nil if extmark not found
local function get_extmark_line(bufnr, extmark_id)
  local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, tool_exec_ns, extmark_id, {})
  if ok and pos and #pos >= 1 then
    return pos[1]
  end
  return nil
end

--- Show pending-approval indicator for a tool
--- Creates a static extmark (no spinner) at the tool result header line.
--- Automatically replaced when `show_tool_indicator` starts the execution spinner.
---@param bufnr integer
---@param tool_id string
---@param header_line integer 1-based line number of the tool result header
function M.show_pending_tool_indicator(bufnr, tool_id, header_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  M.clear_tool_indicator(bufnr, tool_id)

  local line_idx = header_line - 1

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, tool_exec_ns, line_idx, 0, {
    virt_text = { { " ● Pending", "FlemmaToolPending" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY.TOOL_EXECUTION,
    spell = false,
  })

  get_tool_indicators(bufnr)[tool_id] = {
    extmark_id = extmark_id,
    timer = nil,
  }
end

--- Show execution indicator for a tool
--- Creates extmark with animated spinner at the tool result header line
---@param bufnr integer
---@param tool_id string
---@param header_line integer 1-based line number of the tool result header
function M.show_tool_indicator(bufnr, tool_id, header_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clean up any existing indicator for this tool
  M.clear_tool_indicator(bufnr, tool_id)

  local line_idx = header_line - 1
  local frame = 1

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, tool_exec_ns, line_idx, 0, {
    virt_text = { { " " .. spinners.FRAMES.tool[frame] .. " Executing…", "FlemmaToolPending" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY.TOOL_EXECUTION,
    spell = false,
  })

  local timer ---@type integer
  timer = vim.fn.timer_start(200, function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      -- Buffer gone — stop ourselves; buffer state cleanup may have already run
      vim.fn.timer_stop(timer)
      return
    end

    local indicators = get_tool_indicators(bufnr)
    local ind = indicators[tool_id]
    if not ind then
      return
    end

    local current_line = get_extmark_line(bufnr, ind.extmark_id)
    if not current_line then
      return
    end

    frame = (frame % #spinners.FRAMES.tool) + 1
    pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, current_line, 0, {
      id = ind.extmark_id,
      virt_text = { { " " .. spinners.FRAMES.tool[frame] .. " Executing…", "FlemmaToolPending" } },
      virt_text_pos = "eol",
      hl_mode = "combine",
      priority = PRIORITY.TOOL_EXECUTION,
      spell = false,
    })
  end, { ["repeat"] = -1 })

  get_tool_indicators(bufnr)[tool_id] = {
    extmark_id = extmark_id,
    timer = timer,
  }
end

--- Update indicator to show completion/error state
--- Stops animation, shows final state
---@param bufnr integer
---@param tool_id string
---@param success boolean
function M.update_tool_indicator(bufnr, tool_id, success)
  local indicators = get_tool_indicators(bufnr)
  local ind = indicators[tool_id]
  if not ind then
    return
  end

  -- Stop animation timer
  if ind.timer then
    vim.fn.timer_stop(ind.timer)
    ind.timer = nil
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    indicators[tool_id] = nil
    return
  end

  -- Query extmark's current position (may have shifted due to buffer edits)
  local current_line = get_extmark_line(bufnr, ind.extmark_id)
  if not current_line then
    indicators[tool_id] = nil
    return
  end

  -- Show final state
  local text, hl
  if success then
    text = " ✓ Complete"
    hl = "FlemmaToolSuccess"
  else
    text = " ✗ Failed"
    hl = "FlemmaToolError"
  end

  pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, current_line, 0, {
    id = ind.extmark_id,
    virt_text = { { text, hl } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY.TOOL_EXECUTION,
    spell = false,
  })
end

--- Clear indicator for a tool (removes extmark and stops timer)
---@param bufnr integer
---@param tool_id string
function M.clear_tool_indicator(bufnr, tool_id)
  local indicators = get_tool_indicators(bufnr)
  local ind = indicators[tool_id]
  if not ind then
    return
  end

  if ind.timer then
    vim.fn.timer_stop(ind.timer)
  end

  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, tool_exec_ns, ind.extmark_id)
  end

  indicators[tool_id] = nil
end

--- Reposition all tool indicators to their correct header lines after buffer modification.
--- When inject_placeholder or inject_result replaces lines containing an extmark,
--- Neovim pushes that extmark to the start of the replacement range, which may be
--- a different tool's header. This function uses the AST to find each tool_result's
--- actual position and moves the extmark there.
---@param bufnr integer
function M.reposition_tool_indicators(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local doc = parser.get_parsed_document(bufnr)
  local siblings = ast.build_tool_sibling_table(doc)

  local indicators = get_tool_indicators(bufnr)
  for tool_id, ind in pairs(indicators) do
    local sibling = siblings[tool_id]
    local target_line = sibling and sibling.result and (sibling.result.position.start_line - 1) or nil
    if target_line then
      local current_line = get_extmark_line(bufnr, ind.extmark_id)
      if current_line and current_line ~= target_line then
        -- Read current virtual text to preserve it during repositioning
        local ok, pos =
          pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, tool_exec_ns, ind.extmark_id, { details = true })
        if ok and pos and #pos >= 3 then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, target_line, 0, {
            id = ind.extmark_id,
            virt_text = pos[3].virt_text,
            virt_text_pos = "eol",
            hl_mode = "combine",
            priority = PRIORITY.TOOL_EXECUTION,
            spell = false,
          })
        end
      end
    end
  end
end

--- Schedule indicator clear after a delay, or immediately on user edit
--- Uses extmark_id guard to avoid clearing a newer indicator if tool is re-executed.
--- The on_lines listener only fires when the buffer is idle (not locked by tool
--- execution and no active API request), so programmatic edits from other tool
--- completions or streaming responses won't prematurely dismiss the indicator.
---@param bufnr integer
---@param tool_id string
---@param delay_ms integer Milliseconds to wait before clearing
function M.schedule_tool_indicator_clear(bufnr, tool_id, delay_ms)
  local indicators = get_tool_indicators(bufnr)
  local ind = indicators[tool_id]
  if not ind then
    return
  end
  local expected_extmark = ind.extmark_id
  local cleared = false

  local function do_clear()
    if cleared then
      return
    end
    local current = get_tool_indicators(bufnr)[tool_id]
    if not current or current.extmark_id ~= expected_extmark then
      cleared = true
      return -- indicator was replaced by re-execution
    end
    cleared = true
    M.clear_tool_indicator(bufnr, tool_id)
  end

  vim.defer_fn(function()
    do_clear()
  end, delay_ms)

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_attach(bufnr, false, {
      on_lines = function()
        -- Ignore programmatic edits: tool result injection (buffer locked) and
        -- streaming responses (active API request). Only dismiss on user edits.
        local buffer_state = state.get_buffer_state(bufnr)
        if buffer_state.locked or buffer_state.current_request then
          return
        end
        vim.schedule(function()
          do_clear()
        end)
        return true -- detach after first user edit
      end,
    })
  end
end

--- Clear all tool indicators for a buffer (used on buffer cleanup)
---@param bufnr integer
function M.clear_all_tool_indicators(bufnr)
  local indicators = get_tool_indicators(bufnr)
  local to_clear = {}
  for tool_id in pairs(indicators) do
    table.insert(to_clear, tool_id)
  end

  for _, tool_id in ipairs(to_clear) do
    M.clear_tool_indicator(bufnr, tool_id)
  end

  -- Also clear the namespace for this buffer
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, tool_exec_ns, 0, -1)
  end
end

---Set up UI-related autocmds and initialization
function M.setup()
  -- Create or clear the augroup for UI-related autocmds
  local augroup = vim.api.nvim_create_augroup("FlemmaUI", { clear = true })

  -- Add autocmd for updating rulers and line highlights (debounced via CursorHold)
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "VimResized", "CursorHold", "CursorHoldI" }, {
    group = augroup,
    pattern = "*.chat",
    callback = function(ev)
      local buffer_state = state.get_buffer_state(ev.buf)
      local tick = vim.api.nvim_buf_get_changedtick(ev.buf)
      -- CursorHold fires frequently with low updatetime — skip if buffer unchanged
      if (ev.event == "CursorHold" or ev.event == "CursorHoldI") and buffer_state.ui_update_tick == tick then
        return
      end
      bridge.update_ui(ev.buf)
      buffer_state.ui_update_tick = tick
    end,
  })

  -- Passively evaluate frontmatter when buffer content changes so integrations
  -- (e.g., lualine) see up-to-date config values without waiting for a request send.
  -- Gated inside evaluate_frontmatter_if_changed: no-op unless the frontmatter code
  -- actually changed, and skipped when buffer is locked (request in flight).
  -- BufEnter covers switching to a buffer whose frontmatter hasn't been evaluated yet.
  vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "BufEnter" }, {
    group = augroup,
    pattern = "*.chat",
    callback = function(ev)
      processor.evaluate_frontmatter_if_changed(ev.buf)
    end,
  })

  -- Ensure buffer-local state gets cleaned up when chat buffers are removed.
  -- This prevents leaking timers or jobs if a buffer is deleted while a request/progress indicator is active.
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload", "BufDelete" }, {
    group = augroup,
    pattern = "*",
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "chat" or string.match(vim.api.nvim_buf_get_name(ev.buf), "%.chat$") then
        M.cleanup_progress(ev.buf)
        M.clear_all_tool_indicators(ev.buf)
        -- state.cleanup_buffer_state handles executor.cleanup_buffer internally
        state.cleanup_buffer_state(ev.buf)
      end
    end,
  })
end

return M
