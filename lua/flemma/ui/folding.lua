--- Folding module for Flemma UI
--- Manages fold levels, fold text, fold setup, and auto-close behavior.
--- Uses a registry of fold rules following the BUILTIN_RULES pattern.
---@class flemma.ui.Folding
local M = {}

local state = require("flemma.state")
local log = require("flemma.logging")
local loader = require("flemma.loader")
local preview = require("flemma.ui.preview")
local query = require("flemma.ast.query")

---@class flemma.ui.folding.FoldRule
---@field name string
---@field auto_close boolean
---@field populate fun(doc: flemma.ast.DocumentNode, fold_map: table<integer, string>)
---@field get_closeable_ranges fun(doc: flemma.ast.DocumentNode): flemma.ui.folding.CloseableRange[]

---@class flemma.ui.folding.CloseableRange
---@field id string
---@field start_line integer
---@field end_line integer
---@field config_key? string Override rule.name for auto_close config lookup

local BUILTIN_RULES = {
  "flemma.ui.folding.rules.frontmatter",
  "flemma.ui.folding.rules.thinking",
  "flemma.ui.folding.rules.tool_blocks",
  "flemma.ui.folding.rules.messages",
}

-- ============================================================================
-- Fold Map Cache
-- ============================================================================

---@type { changedtick: integer, bufnr: integer, map: table<integer, string> }
local fold_map_cache = { changedtick = -1, bufnr = -1, map = {} }

---Invalidate the fold map cache so the next get_fold_level rebuilds it.
local function invalidate_cache()
  fold_map_cache = { changedtick = -1, bufnr = -1, map = {} }
end

-- ============================================================================
-- Rule Registry
-- ============================================================================

---@type flemma.ui.folding.FoldRule[]
local rules = {}
local initialized = false

---Load built-in rules on first use.
local function ensure_rules_loaded()
  if initialized then
    return
  end
  initialized = true
  for _, module_path in ipairs(BUILTIN_RULES) do
    table.insert(rules, loader.load(module_path))
  end
end

---Register a fold rule by module path or table.
---Invalidates the fold map cache since the rule set changed.
---@param source string|flemma.ui.folding.FoldRule Module path or rule table
function M.register(source)
  ensure_rules_loaded()
  if type(source) == "string" then
    table.insert(rules, loader.load(source))
  else
    table.insert(rules, source)
  end
  invalidate_cache()
end

---Get a fold rule by name.
---@param name string
---@return flemma.ui.folding.FoldRule|nil
function M.get(name)
  ensure_rules_loaded()
  for _, rule in ipairs(rules) do
    if rule.name == name then
      return rule
    end
  end
  return nil
end

---Get all registered fold rules (ordered copy).
---@return flemma.ui.folding.FoldRule[]
function M.get_all()
  ensure_rules_loaded()
  return vim.deepcopy(rules)
end

---Check if a fold rule exists by name.
---@param name string
---@return boolean
function M.has(name)
  ensure_rules_loaded()
  for _, rule in ipairs(rules) do
    if rule.name == name then
      return true
    end
  end
  return false
end

---Unregister a fold rule by name.
---@param name string
---@return boolean removed True if a rule was found and removed
function M.unregister(name)
  ensure_rules_loaded()
  for i, rule in ipairs(rules) do
    if rule.name == name then
      table.remove(rules, i)
      invalidate_cache()
      return true
    end
  end
  return false
end

---Clear all registered rules and reset initialization state.
---Used by tests for isolation.
function M.clear()
  rules = {}
  initialized = false
  invalidate_cache()
end

---Get the count of registered fold rules.
---@return integer
function M.count()
  ensure_rules_loaded()
  return #rules
end

---Build a fold map by iterating all registered rules.
---Highest foldlevel wins: when two rules claim the same line, the entry
---with the greater numeric level is kept (via utils.set_fold).
---@param doc flemma.ast.DocumentNode
---@return table<integer, string>
local function build_fold_map(doc)
  ensure_rules_loaded()
  local fold_map = {}
  for _, rule in ipairs(rules) do
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
-- Fold Text
-- ============================================================================

---Get the cached AST document for the current buffer.
---@return flemma.ast.DocumentNode
local function get_document()
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = require("flemma.parser")
  return parser.get_parsed_document(bufnr)
end

---Compute the display width of a string (handles multibyte characters correctly).
---@param s string
---@return integer
local function strwidth(s)
  return vim.api.nvim_strwidth(s)
end

---Get the body text for a tool use fold (custom format_preview or generic key-value).
---@param tool_seg flemma.ast.ToolUseSegment
---@param available integer Available width for the body
---@return string
local function get_tool_use_body(tool_seg, available)
  local registry = require("flemma.tools.registry")
  local tool_def = registry.get(tool_seg.name)

  local body
  if tool_def and tool_def.format_preview then
    body = tool_def.format_preview(tool_seg.input, available)
    body = body:gsub("\n", "⤶")
  else
    local keys = vim.tbl_keys(tool_seg.input)
    if #keys == 0 then
      return ""
    end
    body = preview.format_tool_preview_body(tool_seg.input, available)
  end

  -- Post-hoc truncation for custom format_preview that may ignore max_length
  if strwidth(body) > available then
    -- Truncate to fit: use byte-level truncation then verify display width
    while strwidth(body) > available - 1 do
      body = body:sub(1, #body - 1)
    end
    body = body .. "…"
  end

  return body
end

---Get fold text for display.
---Returns a list of {text, highlight_group} tuples for per-segment highlighting.
---@return {[1]:string, [2]:string}[]
function M.get_fold_text()
  local roles = require("flemma.roles")
  local foldstart_lnum = vim.v.foldstart
  local foldend_lnum = vim.v.foldend
  local total_fold_lines = foldend_lnum - foldstart_lnum + 1
  local doc = get_document()
  local text_width = preview.get_text_area_width(vim.api.nvim_get_current_win())
  local suffix = string.format("(%d lines)", total_fold_lines)

  -- Check for frontmatter fold (level 2)
  local fm = doc.frontmatter
  if fm and fm.position.start_line == foldstart_lnum then
    local prefix = "```" .. fm.language .. " "
    local suffix_full = " ``` " .. suffix
    local fold_preview = preview.format_content_preview(fm.code, text_width - strwidth(prefix) - strwidth(suffix_full))
    if fold_preview ~= "" then
      return {
        { prefix, "Comment" },
        { fold_preview, "Comment" },
        { " ``` ", "Comment" },
        { suffix, "FlemmaFoldMeta" },
      }
    else
      return {
        { string.format("```%s ", fm.language), "Comment" },
        { suffix, "FlemmaFoldMeta" },
      }
    end
  end

  -- Check if this is a thinking fold (level 2)
  local thinking_seg = query.find_thinking_at_line(doc, foldstart_lnum)
  if thinking_seg then
    if thinking_seg.redacted then
      return {
        { "<thinking redacted> ", "FlemmaThinkingTag" },
        { suffix, "FlemmaFoldMeta" },
      }
    end
    local provider = thinking_seg.signature and thinking_seg.signature.provider
    ---@type {[1]:string, [2]:string}[]
    local chunks = {}
    table.insert(chunks, { "<thinking", "FlemmaThinkingTag" })
    if provider then
      table.insert(chunks, { " " .. provider, "Comment" })
    end
    table.insert(chunks, { "> ", "FlemmaThinkingTag" })

    -- Compute available width for preview
    local chrome_width = strwidth("<thinking")
      + (provider and strwidth(" " .. provider) or 0)
      + strwidth("> ")
      + strwidth(" </thinking> ")
      + strwidth(suffix)
    local fold_preview = preview.format_content_preview(thinking_seg.content, text_width - chrome_width)

    if fold_preview ~= "" then
      table.insert(chunks, { fold_preview .. " ", "FlemmaThinkingBlock" })
      table.insert(chunks, { "</thinking> ", "FlemmaThinkingTag" })
      table.insert(chunks, { suffix, "FlemmaFoldMeta" })
    else
      -- Remove the chunks we added and use self-closing tag
      chunks = {}
      local empty_tag = provider and string.format("<thinking %s/> ", provider) or "<thinking/> "
      table.insert(chunks, { empty_tag, "FlemmaThinkingTag" })
      table.insert(chunks, { suffix, "FlemmaFoldMeta" })
    end
    return chunks
  end

  -- Check if this is a tool_use or tool_result fold (level 2)
  local tool_seg, tool_kind = query.find_tool_segment_at_line(doc, foldstart_lnum)
  if tool_seg then
    if tool_kind == "tool_use" then
      ---@cast tool_seg flemma.ast.ToolUseSegment
      ---@type {[1]:string, [2]:string}[]
      local chunks = {
        { "◆ ", "FlemmaToolIcon" },
        { "Tool Use: ", "FlemmaToolUseTitle" },
      }

      local fixed_width = strwidth("◆ ")
        + strwidth("Tool Use: ")
        + strwidth(tool_seg.name)
        + strwidth(": ")
        + strwidth(" ")
        + strwidth(suffix)
      local available = text_width - fixed_width
      local body = get_tool_use_body(tool_seg, available)

      if body ~= "" then
        table.insert(chunks, { tool_seg.name, "FlemmaToolName" })
        table.insert(chunks, { ": " .. body .. " ", "FlemmaFoldPreview" })
      else
        table.insert(chunks, { tool_seg.name .. " ", "FlemmaToolName" })
      end
      table.insert(chunks, { suffix, "FlemmaFoldMeta" })
      return chunks
    elseif tool_kind == "tool_result" then
      ---@cast tool_seg flemma.ast.ToolResultSegment
      local tool_name_map = query.build_tool_name_map(doc)
      local tool_name = tool_name_map[tool_seg.tool_use_id] or "result"

      ---@type {[1]:string, [2]:string}[]
      local chunks = {
        { "◆ ", "FlemmaToolIcon" },
        { "Tool Result: ", "FlemmaToolResultTitle" },
        { tool_name, "FlemmaToolName" },
      }

      local fixed_width = strwidth("◆ ")
        + strwidth("Tool Result: ")
        + strwidth(tool_name)
        + strwidth(": ")
        + strwidth(" ")
        + strwidth(suffix)
      if tool_seg.is_error then
        fixed_width = fixed_width + strwidth("(error) ")
      end
      local available = text_width - fixed_width

      local body = preview.format_content_preview(tool_seg.content, available)

      if body ~= "" or tool_seg.is_error then
        table.insert(chunks, { ": ", "FlemmaFoldPreview" })
        if tool_seg.is_error then
          table.insert(chunks, { "(error) ", "FlemmaToolResultError" })
        end
        if body ~= "" then
          table.insert(chunks, { body .. " ", "FlemmaFoldPreview" })
        end
      else
        table.insert(chunks, { " ", "FlemmaToolName" })
      end
      table.insert(chunks, { suffix, "FlemmaFoldMeta" })
      return chunks
    end
  end

  -- Message folds (level 1)
  local msg = query.find_message_at_line(doc, foldstart_lnum)
  if msg then
    local role_marker = "@" .. msg.role .. ":"
    local role_hl = roles.highlight_group("FlemmaRole", msg.role)
    local content_hl = roles.highlight_group("Flemma", msg.role)

    local chrome_width = strwidth(role_marker) + strwidth(" ") + strwidth(" ") + strwidth(suffix)
    local fold_preview = preview.format_message_fold_preview(msg, text_width - chrome_width, doc)
    return {
      { role_marker, role_hl },
      { " " .. fold_preview .. " ", content_hl },
      { suffix, "FlemmaFoldMeta" },
    }
  end

  return { { vim.fn.getline(foldstart_lnum), "Folded" } }
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
  vim.wo[winid].foldlevel = state.get_config().editing.foldlevel
end

---Force Neovim to re-evaluate all fold levels for a buffer.
---
---Incremental fold recalculation only updates changed lines, but tool_use
---fold levels depend on distant tool_result segments — resetting foldmethod
---forces a complete re-evaluation. The fold map cache is also invalidated
---so get_fold_level rebuilds from the current AST even when changedtick
---has not advanced (e.g., update_ui on the same event loop tick).
---@param bufnr integer
function M.invalidate_folds(bufnr)
  invalidate_cache()
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
  local fold_level_str = vim.fn.win_execute(winid, string.format("echo foldlevel(%d)", start_lnum))
  local fold_level = tonumber(vim.trim(fold_level_str))
  if not fold_level or fold_level <= 0 then
    return
  end
  local fold_closed_str = vim.fn.win_execute(winid, string.format("echo foldclosed(%d)", start_lnum))
  if tonumber(vim.trim(fold_closed_str)) ~= -1 then
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

  ensure_rules_loaded()
  for _, rule in ipairs(rules) do
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
