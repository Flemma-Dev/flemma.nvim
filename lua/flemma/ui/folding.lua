--- Folding module for Flemma UI
--- Manages fold levels, fold text, fold setup, and auto-close behavior.
--- Uses a registry of fold rules following the BUILTINS pattern.
---@class flemma.ui.Folding
local M = {}

local state = require("flemma.state")
local log = require("flemma.logging")
local preview = require("flemma.ui.preview")
local config = require("flemma.config")

---@type flemma.ui.folding.FoldRule[]
local BUILTINS = {
  require("flemma.ui.folding.rules.frontmatter"),
  require("flemma.ui.folding.rules.thinking"),
  require("flemma.ui.folding.rules.tool_blocks"),
  require("flemma.ui.folding.rules.messages"),
}

-- ============================================================================
-- Fold Map Cache
-- ============================================================================

---@type { changedtick: integer, bufnr: integer, map: table<integer, string> }
local fold_map_cache = { changedtick = -1, bufnr = -1, map = {} }

---Build a fold map by iterating all BUILTINS rules.
---First-writer-wins: if a line already has a fold level, later rules skip it.
---@param doc flemma.ast.DocumentNode
---@return table<integer, string>
local function build_fold_map(doc)
  local fold_map = {}
  for _, rule in ipairs(BUILTINS) do
    rule.populate(doc, fold_map)
  end
  return fold_map
end

-- ============================================================================
-- Fold Level
-- ============================================================================

---Get fold level for a line number. O(1) lookup into cached fold map.
---@param lnum integer
---@return string
function M.get_fold_level(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if fold_map_cache.changedtick ~= tick or fold_map_cache.bufnr ~= bufnr then
    local parser = require("flemma.parser")
    local doc = parser.get_parsed_document(bufnr)
    fold_map_cache = { changedtick = tick, bufnr = bufnr, map = build_fold_map(doc) }
  end
  return fold_map_cache.map[lnum] or "="
end

-- ============================================================================
-- Fold Text Helpers (moved from preview.lua)
-- ============================================================================

---Get the cached AST document for the current buffer
---@return flemma.ast.DocumentNode
local function get_document()
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = require("flemma.parser")
  return parser.get_parsed_document(bufnr)
end

---Find a thinking segment whose start line matches the given line number
---@param doc flemma.ast.DocumentNode
---@param lnum integer 1-indexed line number
---@return flemma.ast.ThinkingSegment|nil segment
local function find_thinking_at_line(doc, lnum)
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "thinking" and seg.position then
        ---@cast seg flemma.ast.ThinkingSegment
        if seg.position.start_line == lnum then
          return seg
        end
      end
    end
  end
  return nil
end

---Find a tool_use or tool_result segment starting at the given line number
---@param doc flemma.ast.DocumentNode
---@param lnum integer 1-indexed line number
---@return flemma.ast.ToolUseSegment|flemma.ast.ToolResultSegment|nil segment
---@return "tool_use"|"tool_result"|nil kind
local function find_tool_segment_at_line(doc, lnum)
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.position and seg.position.start_line == lnum then
        if seg.kind == "tool_use" then
          ---@cast seg flemma.ast.ToolUseSegment
          return seg, "tool_use"
        elseif seg.kind == "tool_result" then
          ---@cast seg flemma.ast.ToolResultSegment
          return seg, "tool_result"
        end
      end
    end
  end
  return nil, nil
end

---Find a message whose start line matches the given line number
---@param doc flemma.ast.DocumentNode
---@param lnum integer 1-indexed line number
---@return flemma.ast.MessageNode|nil message
local function find_message_at_line(doc, lnum)
  for _, msg in ipairs(doc.messages) do
    if msg.position.start_line == lnum then
      return msg
    end
  end
  return nil
end

---Build a tool_use_id -> tool_name lookup from all Assistant messages in a document.
---@param doc flemma.ast.DocumentNode
---@return table<string, string>
local function build_tool_name_map(doc)
  local map = {}
  for _, msg in ipairs(doc.messages) do
    if msg.role == "Assistant" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_use" then
          local tool_seg = seg --[[@as flemma.ast.ToolUseSegment]]
          map[tool_seg.id] = tool_seg.name
        end
      end
    end
  end
  return map
end

-- ============================================================================
-- Fold Text
-- ============================================================================

---Get fold text for display
---@return string
function M.get_fold_text()
  local foldstart_lnum = vim.v.foldstart
  local foldend_lnum = vim.v.foldend
  local total_fold_lines = foldend_lnum - foldstart_lnum + 1
  local doc = get_document()
  local text_width = preview.get_text_area_width(vim.api.nvim_get_current_win())

  -- Check for frontmatter fold (level 2)
  local fm = doc.frontmatter
  if fm and fm.position.start_line == foldstart_lnum then
    -- Account for surrounding chrome: "```lang  ``` (N lines)"
    local suffix = string.format(" ``` (%d lines)", total_fold_lines)
    local prefix = "```" .. fm.language .. " "
    local fold_preview = preview.format_content_preview(fm.code, text_width - #prefix - #suffix)
    if fold_preview ~= "" then
      return prefix .. fold_preview .. suffix
    else
      return string.format("```%s (%d lines)", fm.language, total_fold_lines)
    end
  end

  -- Check if this is a thinking fold (level 2)
  local thinking_seg = find_thinking_at_line(doc, foldstart_lnum)
  if thinking_seg then
    if thinking_seg.redacted then
      return string.format("<thinking redacted> (%d lines)", total_fold_lines)
    end
    local provider = thinking_seg.signature and thinking_seg.signature.provider
    -- Account for surrounding chrome: "<thinking [provider]>  </thinking> (N lines)"
    local tag = provider and string.format("<thinking %s>", provider) or "<thinking>"
    local suffix = string.format(" </thinking> (%d lines)", total_fold_lines)
    local fold_preview = preview.format_content_preview(thinking_seg.content, text_width - #tag - #suffix - 1)
    if fold_preview ~= "" then
      return tag .. " " .. fold_preview .. suffix
    else
      local empty_tag = provider and string.format("<thinking %s/>", provider) or "<thinking/>"
      return string.format("%s (%d lines)", empty_tag, total_fold_lines)
    end
  end

  -- Check if this is a tool_use or tool_result fold (level 2)
  local tool_seg, tool_kind = find_tool_segment_at_line(doc, foldstart_lnum)
  if tool_seg then
    if tool_kind == "tool_use" then
      ---@cast tool_seg flemma.ast.ToolUseSegment
      local prefix = "◆ Tool Use: "
      local suffix = string.format(" (%d lines)", total_fold_lines)
      local available = text_width - #prefix - #suffix - 1
      local tool_preview = preview.format_tool_preview(tool_seg.name, tool_seg.input, available)
      return prefix .. tool_preview .. suffix
    elseif tool_kind == "tool_result" then
      ---@cast tool_seg flemma.ast.ToolResultSegment
      -- Resolve tool name from matching tool_use
      local prefix = "◆ Tool Result: "
      local tool_name_map = build_tool_name_map(doc)
      local tool_name = tool_name_map[tool_seg.tool_use_id] or "result"
      local suffix = string.format(" (%d lines)", total_fold_lines)
      local available = text_width - #prefix - #suffix - 1
      local result_preview =
        preview.format_tool_result_preview(tool_name, tool_seg.content, tool_seg.is_error, available)
      return prefix .. result_preview .. suffix
    end
  end

  -- Message folds (level 1)
  local msg = find_message_at_line(doc, foldstart_lnum)
  if msg then
    local role_prefix = "@" .. msg.role .. ":"
    -- Account for surrounding chrome: "@Role:  (N lines)"
    local suffix = string.format(" (%d lines)", total_fold_lines)
    local fold_preview = preview.format_message_fold_preview(msg, text_width - #role_prefix - #suffix - 1, doc)
    return role_prefix .. " " .. fold_preview .. suffix
  end

  return vim.fn.getline(foldstart_lnum)
end

-- ============================================================================
-- Fold Setup and Invalidation
-- ============================================================================

---Set up folding expression for a buffer.
---If bufnr is provided, sets folding on the window displaying that buffer,
---otherwise sets folding on the current window.
---@param bufnr? integer
function M.setup_folding(bufnr)
  local winid

  if bufnr then
    winid = vim.fn.bufwinid(bufnr)
    if winid == -1 then
      return
    end
  else
    winid = vim.api.nvim_get_current_win()
  end

  vim.wo[winid].foldmethod = "expr"
  vim.wo[winid].foldexpr = 'v:lua.require("flemma.ui.folding").get_fold_level(v:lnum)'
  vim.wo[winid].foldtext = 'v:lua.require("flemma.ui.folding").get_fold_text()'
  vim.wo[winid].foldlevel = config.editing.foldlevel
end

---Force Neovim to re-evaluate all fold levels for a buffer.
---
---Incremental fold recalculation only updates changed lines, but tool_use
---fold levels depend on distant tool_result segments — resetting foldmethod
---forces a complete re-evaluation.
---@param bufnr integer
function M.invalidate_folds(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    local foldmethod = vim.fn.win_execute(winid, "echo &foldmethod")
    if vim.trim(foldmethod) == "expr" then
      vim.fn.win_execute(winid, "set foldmethod=expr")
    end
  end
end

-- ============================================================================
-- Auto-Close
-- ============================================================================

---Close a fold range in a buffer's window, guarding against already-closed folds.
---@param winid integer
---@param start_lnum integer 1-indexed start line
---@param end_lnum integer 1-indexed end line
local function safe_foldclose(winid, start_lnum, end_lnum)
  local fold_exists = vim.fn.win_execute(winid, string.format("echo foldlevel(%d)", start_lnum))
  if not (tonumber(vim.trim(fold_exists)) and tonumber(vim.trim(fold_exists)) > 0) then
    return
  end
  local already_closed = vim.fn.win_execute(winid, string.format("echo foldclosed(%d)", start_lnum))
  if tonumber(vim.trim(already_closed)) ~= -1 then
    return
  end
  vim.fn.win_execute(winid, string.format("%d,%d foldclose", start_lnum, end_lnum))
end

---Fold all completed/terminal blocks using rules and auto_close configuration.
---Uses ephemeral auto_closed_folds set for new-fold detection.
---@param bufnr integer
function M.fold_completed_blocks(bufnr)
  log.debug("fold_completed_blocks(): Folding completed blocks in buffer " .. bufnr)

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    log.debug("fold_completed_blocks(): Buffer " .. bufnr .. " has no window. Cannot close folds.")
    return
  end

  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  if #doc.messages == 0 then
    return
  end

  local current_config = state.get_config()
  local auto_close_config = current_config.editing and current_config.editing.auto_close or {}

  local buffer_state = state.get_buffer_state(bufnr)
  if not buffer_state.auto_closed_folds then
    buffer_state.auto_closed_folds = {}
  end

  for _, rule in ipairs(BUILTINS) do
    local ranges = rule.get_closeable_ranges(doc)
    for _, range in ipairs(ranges) do
      -- Check config for this range's config_key (or rule name); fall back to rule's default
      local config_key = range.config_key or rule.name
      local should_auto_close = auto_close_config[config_key]
      if should_auto_close == nil then
        should_auto_close = rule.auto_close
      end

      if should_auto_close and not buffer_state.auto_closed_folds[range.id] then
        safe_foldclose(winid, range.start_line, range.end_line)
        buffer_state.auto_closed_folds[range.id] = true
      end
    end
  end
end

return M
