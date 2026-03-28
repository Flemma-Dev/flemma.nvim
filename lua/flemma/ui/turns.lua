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

---@alias flemma.ui.TurnPosition "top"|"middle"|"bottom"|"pending"|"pending_end"

---@alias flemma.ui.TurnMap table<integer, flemma.ui.TurnPosition>

---@class flemma.ui.TurnRange
---@field start_line integer 1-indexed first line of the turn
---@field end_line integer 1-indexed last line of the turn
---@field streaming boolean Whether this turn is actively receiving streamed data (HTTP request in flight)
---@field incomplete boolean Whether this turn is open (no terminal assistant yet, e.g., mid-tool-use cycle)

---@class flemma.ui.TurnBufferCache
---@field enabled boolean Whether turns are enabled for this buffer
---@field result_empty string Pre-computed statuscolumn return string for non-turn lines
---@field result_disabled string Pre-computed statuscolumn return string when disabled
---@field results table<string, string> Pre-computed full return strings keyed by character constant
---@field changedtick integer Last changedtick when turn data was computed
---@field map flemma.ui.TurnMap Line-to-position lookup
---@field end_line_map table<integer, integer> Line-to-turn-end-line lookup for O(1) fold correction
---@field ranges flemma.ui.TurnRange[] Detected turn ranges

-- ============================================================================
-- Constants
-- ============================================================================

local CHAR_TOP = "\u{256d}" -- ╭
local CHAR_MIDDLE = "\u{2502}" -- │
local CHAR_BOTTOM = "\u{2570}" -- ╰
local CHAR_PENDING = "\u{250a}" -- ┊ (incomplete/streaming interior)
local CHAR_PENDING_END = "\u{2514}" -- └ (incomplete turn end — sharp corner vs rounded ╰)

-- ============================================================================
-- Per-buffer cache
-- ============================================================================

---@type table<integer, flemma.ui.TurnBufferCache>
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
  ---@param opts? { streaming?: boolean, incomplete?: boolean }
  local function close_turn(start_index, end_index, opts)
    opts = opts or {}
    local start_msg = messages[start_index]
    local end_msg = messages[end_index]
    local start_line = start_msg.position.start_line
    local end_line = end_msg.position.end_line or start_line
    table.insert(turns, {
      start_line = start_line,
      end_line = end_line,
      streaming = opts.streaming or false,
      incomplete = opts.incomplete or false,
    })
  end

  while i <= #messages do
    local msg = messages[i]

    if msg.role == "System" then
      -- System messages break any open turn (defensive)
      if turn_start_index then
        close_turn(turn_start_index, i - 1)
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
          -- If streaming and this turn extends to the last message,
          -- the assistant is still writing — mark as streaming.
          if is_streaming and turn_end == #messages then
            close_turn(turn_start_index, turn_end, { streaming = true })
          else
            close_turn(turn_start_index, turn_end)
          end
          turn_start_index = nil
          i = turn_end + 1
        end
      end
    else
      i = i + 1
    end
  end

  -- After loop: if turn_start is set, determine whether to emit an incomplete turn.
  -- Streaming (active HTTP request) always emits. For non-streaming, emit if the
  -- trailing sequence contains at least one @Assistant — this covers the tool-use
  -- cycle where the assistant has responded with tool calls but the final answer
  -- hasn't arrived yet. A trailing sequence of only @You messages (e.g., the empty
  -- prompt at buffer bottom) is not emitted.
  if turn_start_index then
    local has_assistant = false
    if not is_streaming then
      for j = turn_start_index, #messages do
        if messages[j].role == "Assistant" then
          has_assistant = true
          break
        end
      end
    end
    if is_streaming then
      close_turn(turn_start_index, #messages, { streaming = true })
    elseif has_assistant then
      close_turn(turn_start_index, #messages, { incomplete = true })
    end
  end

  return turns
end

---Build a line-to-position map and an end-line lookup from a list of turn ranges.
---@param ranges flemma.ui.TurnRange[]
---@return flemma.ui.TurnMap map
---@return table<integer, integer> end_line_map
local function build_turn_map(ranges)
  local map = {} ---@type flemma.ui.TurnMap
  local end_line_map = {} ---@type table<integer, integer>
  for _, range in ipairs(ranges) do
    if range.streaming or range.incomplete then
      -- Streaming/incomplete turns: ╭ at top, ┊ for interior, ╰ at current end.
      map[range.start_line] = "top"
      map[range.end_line] = "pending_end"
      for lnum = range.start_line + 1, range.end_line - 1 do
        map[lnum] = "pending"
      end
    else
      -- Complete turns: ╭ at top, │ for interior, ╰ at bottom.
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
    -- O(1) fold correction: every line in the range knows the turn's end line
    for lnum = range.start_line, range.end_line do
      end_line_map[lnum] = range.end_line
    end
  end
  return map, end_line_map
end

-- ============================================================================
-- Pre-computed result strings
-- ============================================================================

---Build the set of pre-computed statuscolumn return strings for a given config.
---Returns both the full result strings (keyed by character) and the empty-line result.
---@param padding_left integer
---@param padding_right integer
---@param highlight_group string
---@return table<string, string> results Char → full statuscolumn return string
---@return string result_empty Full return string for non-turn lines
local function build_result_strings(padding_left, padding_right, highlight_group)
  local prefix = "%s%=%l"
  local left = string.rep(" ", padding_left)
  local right = string.rep(" ", padding_right)
  local result_empty = prefix .. left .. " " .. right

  local results = {} ---@type table<string, string>
  local hl_open = "%#" .. highlight_group .. "#"
  local hl_close = "%*"
  for _, char in ipairs({ CHAR_TOP, CHAR_MIDDLE, CHAR_BOTTOM, CHAR_PENDING, CHAR_PENDING_END }) do
    results[char] = prefix .. left .. hl_open .. char .. hl_close .. right
  end

  return results, result_empty
end

-- ============================================================================
-- Public API
-- ============================================================================

---Set up the statuscolumn on the window displaying a buffer.
---Materializes config into a per-buffer cache of plain Lua values and
---pre-computed result strings. Called once per buffer open and on config refresh.
---@param bufnr integer
function M.setup_statuscolumn(bufnr)
  local cfg = config_facade.materialize(bufnr)
  local turns_cfg = cfg.turns or {}
  local enabled = turns_cfg.enabled ~= false

  -- Initialize or update cache with config-derived values
  ---@type flemma.ui.TurnBufferCache
  local cache = turn_caches[bufnr]
    or {
      enabled = false,
      result_empty = "",
      result_disabled = "%s%=%l ",
      results = {},
      changedtick = 0,
      map = {},
      end_line_map = {},
      ranges = {},
    }
  cache.enabled = enabled

  if enabled then
    local padding = turns_cfg.padding or {}
    local padding_left = padding.left or 1
    local padding_right = padding.right or 0
    local highlight_group = turns_cfg.hl or "FlemmaTurn"

    local results, result_empty = build_result_strings(padding_left, padding_right, highlight_group)
    cache.results = results
    cache.result_empty = result_empty
    cache.result_disabled = "%s%=%l "

    -- Preserve existing turn data if present (config refresh shouldn't discard computed turns)
    cache.changedtick = cache.changedtick or 0
    cache.map = cache.map or {}
    cache.end_line_map = cache.end_line_map or {}
    cache.ranges = cache.ranges or {}

    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.wo[winid].statuscolumn = '%!v:lua.require("flemma.ui.turns").statuscolumn()'
    else
      log.debug("setup_statuscolumn(): Buffer " .. bufnr .. " has no window, skipping")
    end
  end

  turn_caches[bufnr] = cache
end

---Recompute the turn map for a buffer from its AST.
---Called by update_ui on buffer changes. Config is read from the per-buffer
---cache populated by setup_statuscolumn — no config proxy access here.
---@param bufnr integer
function M.update(bufnr)
  local cache = turn_caches[bufnr]
  if not cache or not cache.enabled then
    return
  end

  local tick = vim.api.nvim_buf_get_changedtick(bufnr)

  -- Skip if cache is fresh
  if cache.changedtick == tick then
    return
  end

  local doc = parser.get_parsed_document(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local is_streaming = buffer_state.current_request ~= nil

  local ranges = detect_turns(doc, is_streaming)
  local map, end_line_map = build_turn_map(ranges)

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

  cache.changedtick = tick
  cache.map = map
  cache.end_line_map = end_line_map
  cache.ranges = ranges
end

-- ============================================================================
-- Statuscolumn function
-- ============================================================================

---Get the turn map entry for a line, with streaming fallback.
---@param cache flemma.ui.TurnBufferCache
---@param lnum integer
---@return flemma.ui.TurnPosition|nil position
---@return boolean is_streaming
local function get_line_turn_info(cache, lnum)
  local position = cache.map[lnum]
  if position then
    -- Lines in the turn map render with their normal position characters
    -- (╭/│/╰), even if they belong to a streaming range. Only lines that
    -- fall through to the streaming fallback below get the ┊ indicator.
    return position, false
  end

  -- Streaming fallback: lines beyond the cached map that appeared after the
  -- last update but before the next are rendered as streaming members.
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.streaming_start_line and lnum >= buffer_state.streaming_start_line then
    return "middle", true
  end

  return nil, false
end

---Statuscolumn function called by Neovim for each screen line.
---Set via vim.wo.statuscolumn with a v:lua expression pointing to this function.
---All config values and result strings are read from the per-buffer cache
---populated by setup_statuscolumn — zero config proxy access, zero string
---allocation on the hot path.
---@return string
function M.statuscolumn()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache = turn_caches[bufnr]
  if not cache or not cache.enabled then
    return "%s%=%l "
  end

  local lnum = vim.v.lnum
  local virtnum = vim.v.virtnum
  local results = cache.results

  local position, is_streaming = get_line_turn_info(cache, lnum)

  if not position then
    return cache.result_empty
  end

  if is_streaming then
    -- Streaming fallback: lines beyond the frozen turn map render as ┊
    return results[CHAR_PENDING]
  end

  -- Wrapped lines (virtnum > 0) and virtual lines (virtnum < 0):
  -- continue the appropriate vertical character to maintain visual continuity.
  if virtnum ~= 0 then
    if position == "pending" or position == "pending_end" then
      return results[CHAR_PENDING]
    end
    return results[CHAR_MIDDLE]
  end

  -- Real line (virtnum == 0): direct position-to-character mapping
  if position == "top" then
    return results[CHAR_TOP]
  elseif position == "bottom" then
    return results[CHAR_BOTTOM]
  elseif position == "pending_end" then
    return results[CHAR_PENDING_END]
  elseif position == "pending" then
    -- Fold correction: if a fold below this line covers the turn's end,
    -- render ╰ instead of ┊.
    local fold_end = vim.fn.foldclosedend(lnum)
    if fold_end ~= -1 then
      local turn_end = cache.end_line_map[lnum]
      if turn_end and fold_end >= turn_end then
        return results[CHAR_PENDING_END]
      end
    end
    return results[CHAR_PENDING]
  else
    -- position == "middle"
    -- Fold correction: if this middle line is visible and a fold below it
    -- covers the turn's bottom line, render ╰ instead of │.
    local fold_end = vim.fn.foldclosedend(lnum)
    if fold_end ~= -1 then
      local turn_end = cache.end_line_map[lnum]
      if turn_end and fold_end >= turn_end then
        return results[CHAR_BOTTOM]
      end
    end
    return results[CHAR_MIDDLE]
  end
end

-- ============================================================================
-- Teardown
-- ============================================================================

---Clean up turn cache for a buffer.
---Registered as a state cleanup hook so it runs on buffer teardown.
---@param bufnr integer
function M.cleanup(bufnr)
  turn_caches[bufnr] = nil
end

-- Register cleanup hook with state module
state.register_cleanup("turns", M.cleanup)

-- ============================================================================
-- Test helpers
-- ============================================================================

---Expose the cached turn data for a buffer (test-only).
---@param bufnr integer
---@return flemma.ui.TurnBufferCache|nil
function M._get_turn_cache(bufnr)
  return turn_caches[bufnr]
end

return M
