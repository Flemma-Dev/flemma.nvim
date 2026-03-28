--- Turn detection and statuscolumn rendering for Flemma chat buffers.
--- A "turn" is a user-initiated request/response cycle: one or more @You messages,
--- any intermediate tool use/result exchanges, and terminating @Assistant messages.
--- The module computes a per-line turn map from the AST and exposes a statuscolumn
--- function that renders turn boundary characters in the gutter.
---@class flemma.ui.Turns
local M = {}

local config_facade = require("flemma.config")
local log = require("flemma.logging")
local parser = require("flemma.parser")
local state = require("flemma.state")

-- ============================================================================
-- Types
-- ============================================================================

---@alias flemma.ui.TurnPosition "top"|"middle"|"bottom"

---@alias flemma.ui.TurnMap table<integer, flemma.ui.TurnPosition>

---@class flemma.ui.TurnRange
---@field start_line integer 1-indexed first line of the turn
---@field end_line integer 1-indexed last line of the turn
---@field streaming boolean Whether this turn is still receiving data

-- ============================================================================
-- Constants
-- ============================================================================

local CHAR_TOP = "\u{256d}" -- ╭
local CHAR_MIDDLE = "\u{2502}" -- │
local CHAR_BOTTOM = "\u{2570}" -- ╰
local CHAR_STREAMING = "\u{250a}" -- ┊

-- ============================================================================
-- Per-buffer turn map cache
-- ============================================================================

---@type table<integer, { changedtick: integer, map: flemma.ui.TurnMap, ranges: flemma.ui.TurnRange[] }>
local turn_caches = {}

-- ============================================================================
-- Turn detection
-- ============================================================================

---Check whether a message contains a tool_use segment.
---@param msg flemma.ast.MessageNode
---@return boolean
local function has_tool_use(msg)
  for _, seg in ipairs(msg.segments) do
    if seg.kind == "tool_use" then
      return true
    end
  end
  return false
end

---Detect turns from a parsed document's message list.
---A turn starts with one or more @You messages and ends with one or more
---terminal @Assistant messages (where the final assistant has no tool_use segment).
---@System messages break any open turn and are never included.
---@param doc flemma.ast.DocumentNode
---@param is_streaming boolean Whether the buffer has an active streaming request
---@return flemma.ui.TurnRange[]
local function detect_turns(doc, is_streaming)
  local messages = doc.messages
  local turns = {} ---@type flemma.ui.TurnRange[]
  local turn_start_index = nil ---@type integer|nil
  local i = 1

  ---Close a turn spanning message indices [start_index, end_index].
  ---@param start_index integer
  ---@param end_index integer
  ---@param streaming boolean
  local function close_turn(start_index, end_index, streaming)
    local start_msg = messages[start_index]
    local end_msg = messages[end_index]
    local start_line = start_msg.position.start_line
    local end_line = end_msg.position.end_line or start_line
    table.insert(turns, {
      start_line = start_line,
      end_line = end_line,
      streaming = streaming,
    })
  end

  while i <= #messages do
    local msg = messages[i]

    if msg.role == "System" then
      -- System messages break any open turn (defensive)
      if turn_start_index then
        close_turn(turn_start_index, i - 1, false)
        turn_start_index = nil
      end
      i = i + 1
    elseif msg.role == "You" then
      if not turn_start_index then
        turn_start_index = i
      end
      i = i + 1
    elseif msg.role == "Assistant" then
      if not turn_start_index then
        -- Orphan assistant (no preceding @You) -- skip
        i = i + 1
      else
        local msg_has_tool_use = has_tool_use(msg)
        if msg_has_tool_use then
          -- Mid-turn: assistant with tool_use, continue
          i = i + 1
        else
          -- Terminal assistant. Peek forward for consecutive assistants.
          local turn_end = i
          while turn_end + 1 <= #messages and messages[turn_end + 1].role == "Assistant" do
            turn_end = turn_end + 1
          end
          close_turn(turn_start_index, turn_end, false)
          turn_start_index = nil
          i = turn_end + 1
        end
      end
    else
      i = i + 1
    end
  end

  -- After loop: if turn_start is set and streaming is active, mark as streaming turn
  if turn_start_index then
    if is_streaming then
      close_turn(turn_start_index, #messages, true)
    end
    -- If not streaming but turn_start is set, the turn is incomplete (no terminal
    -- assistant yet). We do not emit it -- it will appear once the response arrives.
  end

  return turns
end

---Build a line-to-position map from a list of turn ranges.
---@param ranges flemma.ui.TurnRange[]
---@return flemma.ui.TurnMap
local function build_turn_map(ranges)
  local map = {} ---@type flemma.ui.TurnMap
  for _, range in ipairs(ranges) do
    if range.streaming then
      -- Streaming turns: all lines are marked as "middle" (rendered with ┊)
      -- The actual rendering uses the streaming flag, but we populate the map
      -- so the statuscolumn can distinguish streaming lines from empty lines.
      for lnum = range.start_line, range.end_line do
        map[lnum] = "middle"
      end
    else
      for lnum = range.start_line, range.end_line do
        if lnum == range.start_line then
          map[lnum] = "top"
        elseif lnum == range.end_line then
          map[lnum] = "bottom"
        else
          map[lnum] = "middle"
        end
      end
    end
  end
  return map
end

-- ============================================================================
-- Public API
-- ============================================================================

---Recompute the turn map for a buffer from its AST.
---Called by update_ui on buffer changes.
---@param bufnr integer
function M.update(bufnr)
  local current_config = config_facade.get(bufnr)
  if not current_config.turns or not current_config.turns.enabled then
    turn_caches[bufnr] = nil
    return
  end

  local tick = vim.api.nvim_buf_get_changedtick(bufnr)

  -- Skip if cache is fresh
  local cache = turn_caches[bufnr]
  if cache and cache.changedtick == tick then
    return
  end

  local doc = parser.get_parsed_document(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local is_streaming = buffer_state.current_request ~= nil

  local ranges = detect_turns(doc, is_streaming)
  local map = build_turn_map(ranges)

  -- Set streaming_start_line on buffer state for statuscolumn fallback
  if is_streaming and #ranges > 0 then
    local last_range = ranges[#ranges]
    if last_range.streaming then
      buffer_state.streaming_start_line = last_range.start_line
    else
      buffer_state.streaming_start_line = nil
    end
  else
    buffer_state.streaming_start_line = nil
  end

  turn_caches[bufnr] = {
    changedtick = tick,
    map = map,
    ranges = ranges,
  }
end

-- ============================================================================
-- Statuscolumn
-- ============================================================================

-- Pre-computed format string fragments.
-- The statuscolumn format is: %s%=%l{padding}{turn_char}
-- where {padding} is spaces and {turn_char} is a highlighted turn character.
-- We build the static prefix once and concatenate the turn character at render time.

---Build the static prefix portion of the statuscolumn string.
---Format: %s%=%l (signs + right-align + line number)
---@return string
local function build_statuscolumn_prefix()
  return "%s%=%l"
end

---Build the format string for a highlighted turn character.
---@param char string The turn character to display
---@param highlight_group string The highlight group name
---@return string
local function format_turn_char(char, highlight_group)
  return "%#" .. highlight_group .. "#" .. char .. "%*"
end

---Get the turn map entry for a line, with streaming fallback.
---@param bufnr integer
---@param lnum integer
---@return flemma.ui.TurnPosition|nil position
---@return boolean is_streaming
local function get_line_turn_info(bufnr, lnum)
  local cache = turn_caches[bufnr]
  if not cache then
    return nil, false
  end

  local position = cache.map[lnum]
  if position then
    -- Check if this line belongs to a streaming range
    for _, range in ipairs(cache.ranges) do
      if range.streaming and lnum >= range.start_line and lnum <= range.end_line then
        return position, true
      end
    end
    return position, false
  end

  -- Streaming fallback: lines beyond the cached map that appeared after the
  -- last update but before the next are rendered as streaming members.
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.streaming_start_line and lnum >= buffer_state.streaming_start_line then
    return "middle", true
  end

  return nil, false
end

---Find the end line of the turn containing a given line number.
---Used for fold correction.
---@param bufnr integer
---@param lnum integer
---@return integer|nil
local function find_turn_end_line(bufnr, lnum)
  local cache = turn_caches[bufnr]
  if not cache then
    return nil
  end
  for _, range in ipairs(cache.ranges) do
    if lnum >= range.start_line and lnum <= range.end_line then
      return range.end_line
    end
  end
  return nil
end

---Statuscolumn function called by Neovim for each screen line.
---Set via vim.wo.statuscolumn with a v:lua expression pointing to this function.
---@return string
function M.statuscolumn()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.v.lnum
  local virtnum = vim.v.virtnum

  local current_config = config_facade.get(bufnr)
  if not current_config.turns or not current_config.turns.enabled then
    return build_statuscolumn_prefix() .. " "
  end

  local padding_count = current_config.turns.padding or 1
  local highlight_group = current_config.turns.hl or "FlemmaTurn"
  local padding = string.rep(" ", padding_count)
  local prefix = build_statuscolumn_prefix()

  -- Virtual lines below a screen line (v:virtnum < 0 = above, > 0 = wrapped)
  if virtnum < 0 then
    return prefix .. padding .. " "
  end

  local position, is_streaming = get_line_turn_info(bufnr, lnum)

  if not position then
    return prefix .. padding .. " "
  end

  if is_streaming then
    -- Streaming: all positions render as ┊
    local char = format_turn_char(CHAR_STREAMING, highlight_group)
    return prefix .. padding .. char
  end

  if virtnum > 0 then
    -- Wrapped lines always get │
    local char = format_turn_char(CHAR_MIDDLE, highlight_group)
    return prefix .. padding .. char
  end

  -- Real line (virtnum == 0): pick character based on position
  local render_char
  if position == "top" then
    render_char = CHAR_TOP
  elseif position == "bottom" then
    render_char = CHAR_BOTTOM
  else
    -- position == "middle"
    -- Fold correction: if this middle line is visible and a fold below it
    -- covers the turn's bottom line, render ╰ instead of │.
    local fold_end = vim.fn.foldclosedend(lnum)
    if fold_end ~= -1 then
      local turn_end = find_turn_end_line(bufnr, lnum)
      if turn_end and fold_end >= turn_end then
        render_char = CHAR_BOTTOM
      else
        render_char = CHAR_MIDDLE
      end
    else
      render_char = CHAR_MIDDLE
    end
  end

  local char = format_turn_char(render_char, highlight_group)
  return prefix .. padding .. char
end

-- ============================================================================
-- Setup / Teardown
-- ============================================================================

---Set up the statuscolumn on the window displaying a buffer.
---@param bufnr integer
function M.setup_statuscolumn(bufnr)
  local current_config = config_facade.get(bufnr)
  if not current_config.turns or not current_config.turns.enabled then
    return
  end

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    log.debug("setup_statuscolumn(): Buffer " .. bufnr .. " has no window, skipping")
    return
  end

  vim.wo[winid].statuscolumn = '%!v:lua.require("flemma.ui.turns").statuscolumn()'
end

---Clean up turn cache for a buffer.
---Registered as a state cleanup hook so it runs on buffer teardown.
---@param bufnr integer
function M.cleanup(bufnr)
  turn_caches[bufnr] = nil
end

-- Register cleanup hook with state module
state.register_cleanup("turns", M.cleanup)

return M
