--- Folding module for Flemma UI
--- Manages fold levels, fold text, fold setup, and auto-close behavior.
--- Uses a registry of fold rules following the BUILTIN_RULES pattern.
---@class flemma.ui.Folding
local M = {}

local config_facade = require("flemma.config")
local state = require("flemma.state")
local log = require("flemma.logging")
local loader = require("flemma.loader")
local parser = require("flemma.parser")
local roles = require("flemma.utilities.roles")
local str = require("flemma.utilities.string")
local preview = require("flemma.ui.preview")
local query = require("flemma.ast.query")

local CONTENT_PREVIEW_TRUNCATION_MARKER = "…"
local LABEL_DETAIL_SEPARATOR = " — "

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
  return parser.get_parsed_document(bufnr)
end

---Get the structured preview for a tool use fold.
---Delegates to the shared preview helper.
---@param tool_seg flemma.ast.ToolUseSegment
---@param available integer Available width for the body
---@return { label?: string, detail?: string }
local function get_tool_use_body(tool_seg, available)
  return preview.get_tool_use_body(tool_seg.name, tool_seg.input, available)
end

---Get fold text for display.
---Returns a list of {text, highlight_group} tuples for per-segment highlighting.
---@return {[1]:string, [2]:string}[]
function M.get_fold_text()
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
    local fold_preview =
      preview.format_content_preview(fm.code, text_width - str.strwidth(prefix) - str.strwidth(suffix_full))
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
    local chrome_width = str.strwidth("<thinking")
      + (provider and str.strwidth(" " .. provider) or 0)
      + str.strwidth("> ")
      + str.strwidth(" </thinking> ")
      + str.strwidth(suffix)
    local fold_preview = preview.format_content_preview(thinking_seg.content, text_width - chrome_width)

    if fold_preview ~= "" then
      table.insert(chunks, { fold_preview .. " ", "FlemmaThinkingFoldPreview" })
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

      -- Pass generous available to get the untruncated structured preview;
      -- we compute actual available after knowing label width.
      local structured = get_tool_use_body(tool_seg, text_width)
      local label = structured.label
      local detail = structured.detail

      local fixed_chrome = str.strwidth("◆ ")
        + str.strwidth("Tool Use: ")
        + str.strwidth(tool_seg.name)
        + str.strwidth(": ")
        + str.strwidth(" ") -- trailing space before suffix
        + str.strwidth(suffix)
      local separator_width = str.strwidth(LABEL_DETAIL_SEPARATOR)
      if label then
        fixed_chrome = fixed_chrome + str.strwidth(label) + separator_width -- label + em-dash separator
      end
      local available = text_width - fixed_chrome

      table.insert(chunks, { tool_seg.name, "FlemmaToolName" })

      if label or detail then
        table.insert(chunks, { ": ", "FlemmaToolName" })

        if label then
          table.insert(chunks, { label, "FlemmaToolLabel" })
          if detail and available > 0 then
            local detail_text = str.truncate(detail, available, CONTENT_PREVIEW_TRUNCATION_MARKER)
            if detail_text ~= "" then
              table.insert(chunks, { LABEL_DETAIL_SEPARATOR .. detail_text, "FlemmaToolDetail" })
            end
          end
        else
          -- No label: show detail only (reclaim separator space)
          local detail_text =
            str.truncate(detail --[[@as string]], available + separator_width, CONTENT_PREVIEW_TRUNCATION_MARKER)
          table.insert(chunks, { detail_text, "FlemmaToolDetail" })
        end
        table.insert(chunks, { " ", "FlemmaFoldPreview" })
      else
        table.insert(chunks, { " ", "FlemmaToolName" })
      end
      table.insert(chunks, { suffix, "FlemmaFoldMeta" })
      return chunks
    elseif tool_kind == "tool_result" then
      ---@cast tool_seg flemma.ast.ToolResultSegment
      local tool_use_index = query.build_tool_use_index(doc)
      local tool_info = tool_use_index[tool_seg.tool_use_id]
      local tool_name = tool_info and tool_info.name or "result"
      local tool_label = tool_info and tool_info.label

      ---@type {[1]:string, [2]:string}[]
      local chunks = {
        { "◆ ", "FlemmaToolIcon" },
        { "Tool Result: ", "FlemmaToolResultTitle" },
        { tool_name, "FlemmaToolName" },
      }

      local fixed_chrome = str.strwidth("◆ ")
        + str.strwidth("Tool Result: ")
        + str.strwidth(tool_name)
        + str.strwidth(": ")
        + str.strwidth(" ") -- trailing space before suffix
        + str.strwidth(suffix)
      if tool_seg.is_error then
        fixed_chrome = fixed_chrome + str.strwidth("(error) ")
      end
      local result_separator_width = str.strwidth(LABEL_DETAIL_SEPARATOR)
      if tool_label then
        fixed_chrome = fixed_chrome + str.strwidth(tool_label) + result_separator_width -- label + em-dash separator
      end
      local available = text_width - fixed_chrome

      table.insert(chunks, { ": ", "FlemmaFoldPreview" })
      if tool_seg.is_error then
        table.insert(chunks, { "(error) ", "FlemmaToolResultError" })
      end

      if tool_label then
        table.insert(chunks, { tool_label, "FlemmaToolLabel" })
        if available > 0 then
          local body = preview.format_content_preview(tool_seg.content, available)
          if body ~= "" then
            table.insert(chunks, { LABEL_DETAIL_SEPARATOR .. body, "FlemmaToolDetail" })
          end
        end
      else
        local body = preview.format_content_preview(tool_seg.content, available)
        if body ~= "" then
          table.insert(chunks, { body, "FlemmaFoldPreview" })
        end
      end

      table.insert(chunks, { " ", "FlemmaFoldPreview" })
      table.insert(chunks, { suffix, "FlemmaFoldMeta" })
      return chunks
    end
  end

  -- Message folds (level 1)
  local msg = query.find_message_at_line(doc, foldstart_lnum)
  if msg then
    local role_hl = roles.highlight_group("FlemmaRole", msg.role)
    local role_name_hl = role_hl .. "Name"
    local content_hl = roles.highlight_group("Flemma", msg.role)

    -- When rulers are enabled, match the unfolded visual: ─ Role content (N lines)
    -- Otherwise fall back to the standard @Role: prefix
    local ruler_config = config_facade.get().ruler
    local use_ruler_prefix = ruler_config and ruler_config.enabled ~= false

    ---@type {[1]:string, [2]:string}[]
    local chunks
    local chrome_width
    if use_ruler_prefix then
      local ruler_hl = "FlemmaRuler"
      local ruler_prefix = ruler_config.char .. " "
      chunks = {
        { ruler_prefix, ruler_hl },
        { msg.role, role_name_hl },
        { " ", content_hl },
      }
      chrome_width = str.strwidth(ruler_prefix)
        + str.strwidth(msg.role)
        + str.strwidth(" ")
        + str.strwidth(" ")
        + str.strwidth(suffix)
    else
      local role_marker = "@" .. msg.role .. ":"
      chunks = {
        { role_marker, role_name_hl },
        { " ", content_hl },
      }
      chrome_width = str.strwidth(role_marker) + str.strwidth(" ") + str.strwidth(" ") + str.strwidth(suffix)
    end
    local preview_chunks = preview.format_message_fold_preview(msg, text_width - chrome_width, doc, content_hl)
    vim.list_extend(chunks, preview_chunks)
    table.insert(chunks, { " ", content_hl })
    table.insert(chunks, { suffix, "FlemmaFoldMeta" })
    return chunks
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
  vim.wo[winid].foldlevel = config_facade.get(bufnr).editing.foldlevel
end

---Force Neovim to re-evaluate all fold levels for a buffer.
---
---Incremental fold recalculation only updates changed lines, but tool_use
---fold levels depend on distant tool_result segments — resetting foldmethod
---forces a complete re-evaluation. The fold map cache is also invalidated
---so get_fold_level rebuilds from the current AST even when changedtick
---has not advanced (e.g., update_ui on the same event loop tick).
---
---Unconditionally sets foldmethod=expr rather than guarding on the current
---value: external view restoration (`:loadview` when `viewoptions` includes
---`folds`) silently switches foldmethod to `manual`, which would prevent
---foldexpr from being evaluated for new content. Re-asserting expr on every
---UI cycle ensures self-healing regardless of session/view persistence.
---@param bufnr integer
function M.invalidate_folds(bufnr)
  invalidate_cache()
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    vim.fn.win_execute(winid, "set foldmethod=expr")
  end
end

-- ============================================================================
-- Auto-Close
-- ============================================================================

---Close a fold range in a buffer's window, guarding against already-closed folds.
---Returns true only if the fold was verified as closed after the attempt.
---@param winid integer
---@param start_lnum integer 1-indexed start line
---@param end_lnum integer 1-indexed end line
---@return boolean closed True if the fold is confirmed closed
local function safe_foldclose(winid, start_lnum, end_lnum)
  local fold_level = vim.api.nvim_win_call(winid, function()
    return vim.fn.foldlevel(start_lnum)
  end)
  if not fold_level or fold_level <= 0 then
    return false
  end
  local fold_closed = vim.api.nvim_win_call(winid, function()
    return vim.fn.foldclosed(start_lnum)
  end)
  if fold_closed ~= -1 then
    return true -- Already closed (possibly inside a parent fold)
  end
  vim.fn.win_execute(winid, string.format("%d,%d foldclose", start_lnum, end_lnum))
  -- Verify the fold actually closed
  local verified = vim.api.nvim_win_call(winid, function()
    return vim.fn.foldclosed(start_lnum)
  end)
  return verified ~= -1
end

---Fold all completed/terminal blocks using rules and auto_close configuration.
---Uses ephemeral auto_closed_folds set for new-fold detection.
---Skips when the buffer has not changed since the last call, unless there
---are pending folds that failed to close on a previous attempt.
---@param bufnr integer
function M.fold_completed_blocks(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local has_pending = buffer_state.pending_folds and next(buffer_state.pending_folds) ~= nil
  if buffer_state.fold_completed_tick == tick and not has_pending then
    return
  end

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    log.debug("fold_completed_blocks(): Buffer " .. bufnr .. " has no window. Cannot close folds.")
    return
  end
  buffer_state.fold_completed_tick = tick

  local doc = parser.get_parsed_document(bufnr)

  if #doc.messages == 0 then
    return
  end

  local current_config = config_facade.get(bufnr)
  local auto_close_config = current_config.editing and current_config.editing.auto_close or {}

  if not buffer_state.auto_closed_folds then
    buffer_state.auto_closed_folds = {}
  end

  local new_folds = {}
  local pending = {}

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
        if safe_foldclose(winid, range.start_line, range.end_line) then
          buffer_state.auto_closed_folds[range.id] = true
          table.insert(new_folds, range.id)
        else
          pending[range.id] = true
        end
      end
    end
  end

  -- Track pending folds for retry on subsequent calls
  buffer_state.pending_folds = next(pending) ~= nil and pending or nil

  if #new_folds > 0 then
    log.debug("fold_completed_blocks(): Auto-closed " .. #new_folds .. " fold(s) in buffer " .. bufnr)
  end
end

return M
