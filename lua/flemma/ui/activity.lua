--- Progress lifecycle for in-flight requests.
--- Manages the waiting → thinking → streaming → buffering state machine,
--- inline virt_text on the @Assistant: line, and the off-screen progress Bar.
---@class flemma.ui.Activity
local M = {}

local config_facade = require("flemma.config")
local state = require("flemma.state")
local buffer_utils = require("flemma.utilities.buffer")
local cursor = require("flemma.cursor")
local writequeue = require("flemma.buffer.writequeue")
local str = require("flemma.utilities.string")
local spinners = require("flemma.ui.spinners")
local Bar = require("flemma.ui.bar")
local log = require("flemma.logging")

local PRIORITY_SPINNER = 300

local spinner_ns = vim.api.nvim_create_namespace("flemma_spinner")
local ns_id = vim.api.nvim_create_namespace("flemma")

---@type string
local WAITING_LABEL = "Waiting…"

---@type string
local MIDDLE_DOT = " · "

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
---@return string body
---@return integer|nil tool_name_len Byte length of the tool name prefix (nil when absent)
local function format_progress_body(bs)
  local phase = bs.progress_phase or "waiting"
  local elapsed_seconds = 0
  if bs.progress_started_at then
    elapsed_seconds = (vim.uv.now() - bs.progress_started_at) / 1000
  end
  local elapsed_str = str.format_elapsed(elapsed_seconds)

  if phase == "waiting" then
    return WAITING_LABEL .. MIDDLE_DOT .. elapsed_str, nil
  else
    local count = bs.progress_char_count or 0
    local suffix = count == 1 and " character" or " characters"
    local count_str = str.format_text_length(count) .. suffix
    if phase == "buffering" and bs.progress_tool_name then
      local name = bs.progress_tool_name
      return name .. MIDDLE_DOT .. count_str .. MIDDLE_DOT .. elapsed_str, #name
    end
    return count_str .. MIDDLE_DOT .. elapsed_str, nil
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
    priority = PRIORITY_SPINNER,
    spell = false,
  })
end

---Wrap a flat progress text into a minimal single-item segment list.
---warn_hl is nil in neutral state (no extmark emitted) or a diagnostic
---group name during timeout pressure. tool_name_len, when set, applies
---a bold accent highlight to the leading tool-name span.
---@param text string
---@param warn_hl string|nil
---@param tool_name_len integer|nil
---@return flemma.ui.bar.layout.Segment[]
local function progress_segments(text, warn_hl, tool_name_len)
  ---@type flemma.ui.bar.layout.ItemHighlight|nil
  local hl
  if warn_hl then
    hl = { group = warn_hl }
  elseif tool_name_len then
    hl = { group = "FlemmaProgressBarAccent", offset = 0, length = tool_name_len }
  end
  return {
    {
      key = "progress",
      items = {
        {
          key = "text",
          text = text,
          priority = 1,
          highlight = hl,
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

  local base_body, tool_name_len = format_progress_body(bs)
  local body, warn_hl = timeout_pressure(bs, base_body)

  if phase == "waiting" or phase == "thinking" then
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
    segments = progress_segments(body, warn_hl, tool_name_len),
  })
end

---Start the progress line for a new request.
---Creates the waiting-phase extmark on the @Assistant: line and starts the
---100ms animation timer. The timer reads all progress state from buffer_state
---exclusively — no closure-local copies of extmark IDs or line positions.
---@param bufnr integer
---@param progress_opts { force?: boolean, timeout: integer }
---@param update_ui_fn fun(bufnr: integer)
---@return integer timer_id
function M.start_progress(bufnr, progress_opts, update_ui_fn)
  local buffer_state = state.get_buffer_state(bufnr)

  -- Initialize progress state
  buffer_state.progress_phase = "waiting"
  buffer_state.progress_char_count = 0
  buffer_state.progress_started_at = vim.uv.now()
  buffer_state.progress_timeout = progress_opts.timeout
  buffer_state.progress_extmark_id = nil
  buffer_state.progress_last_line = nil
  buffer_state.progress_tool_name = nil
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
        priority = PRIORITY_SPINNER,
        spell = false,
      })

      buffer_state.progress_extmark_id = extmark_id
      buffer_state.progress_last_line = progress_line_idx0

      -- Immediately update UI and position cursor
      update_ui_fn(bufnr)
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
---@param update_ui_fn fun(bufnr: integer)
function M.cleanup_progress(bufnr, update_ui_fn)
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
      update_ui_fn(bufnr)
      return
    end

    -- Only modify lines if the last line is the empty @Assistant: progress placeholder.
    if last_line_content and last_line_content == "@Assistant:" then
      buffer_utils.buffer_cmd(bufnr, "undojoin")

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

    update_ui_fn(bufnr)
  end)
end

return M
