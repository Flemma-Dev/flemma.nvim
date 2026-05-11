--- Folding module for Flemma UI
--- Manages fold levels, fold text, fold setup, and auto-close behavior.
--- Uses a registry of fold rules following the BUILTIN_RULES pattern.
---@class flemma.ui.Folding
local M = {}

local config_facade = require("flemma.config")
local state = require("flemma.state")
local log = require("flemma.logging")
local loader = require("flemma.loader")
local notify = require("flemma.notify")
local parser = require("flemma.parser")
local roles = require("flemma.utilities.roles")
local str = require("flemma.utilities.string")
local preview = require("flemma.ui.preview")
local query = require("flemma.ast.query")

local CONTENT_PREVIEW_TRUNCATION_MARKER = "…"
local LABEL_DETAIL_SEPARATOR = " — "
local TOOL_USE_ICON = "⬡"
local TOOL_RESULT_ICON = "⬢"

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

---The frontmatter rule reads `vim.wo.conceallevel` in its populate() to decide
---whether to emit fold entries (see lua/flemma/ui/folding/rules/frontmatter.lua
---and docs/conceal.md "Folds and `conceal_lines`"). Include it in the cache
---key so a conceallevel toggle self-invalidates — the OptionSet autocmd in
---ui/init.lua handles the on-screen refold, but the cache key is what keeps
---get_fold_level() correct between eager triggers.
---@type { changedtick: integer, bufnr: integer, conceallevel: integer, map: table<integer, string> }
local fold_map_cache = { changedtick = -1, bufnr = -1, conceallevel = -1, map = {} }

---Invalidate the fold map cache so the next get_fold_level rebuilds it.
local function invalidate_cache()
  fold_map_cache = { changedtick = -1, bufnr = -1, conceallevel = -1, map = {} }
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

---Get fold level for a line number. O(1) lookup into the cached fold map.
---
---## Performance background
---
---Neovim calls this function for every visible line (~300 on a typical
---screen) each time foldexpr is re-evaluated. A naive implementation that
---re-parses on every changedtick change causes a full AST parse + fold map
---rebuild PER KEYSTROKE — ~3ms of Lua work that then triggers Neovim's
---C-level fold state recalculation across all visible lines. On a 5000-line
---buffer this compounds to 120ms+ per keystroke (profiled May 2025).
---
---## Strategy: defer during insert mode
---
---Buffer/conceallevel changes always rebuild (rare, needed for correctness).
---Changedtick changes (every keystroke) are handled in two paths:
---
--- - **Normal mode**: rebuild immediately. Needed for `:read`, undo, and
---   programmatic `nvim_buf_set_lines` (including test setups).
--- - **Insert mode**: return `"="` ("keep previous level") for every line.
---   This tells Neovim's fold engine "nothing changed" — a fast path that
---   skips fold state recalculation entirely. The fold map catches up on
---   CursorHold via invalidate_folds.
---
---The `"="` return during insert mode means folds are visually stale while
---typing. This is acceptable because fold boundaries (role markers, tool
---blocks) rarely change mid-keystroke, and any inaccuracy is corrected the
---moment the user pauses (CursorHold fires after `updatetime` ms).
---@param lnum integer
---@return string
function M.get_fold_level(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local conceal = vim.wo.conceallevel
  if fold_map_cache.bufnr ~= bufnr or fold_map_cache.conceallevel ~= conceal then
    local doc = parser.get_parsed_document(bufnr)
    fold_map_cache = { changedtick = tick, bufnr = bufnr, conceallevel = conceal, map = build_fold_map(doc) }
  elseif fold_map_cache.changedtick ~= tick then
    local mode = vim.api.nvim_get_mode().mode
    -- "=" tells Neovim "fold level unchanged from previous line evaluation",
    -- which it fast-paths without updating fold state. Returning the cached
    -- map value instead would force fold state recalculation for each line.
    if mode == "i" or mode == "ic" or mode == "ix" or mode == "R" or mode == "Rc" or mode == "Rx" then
      return "="
    end
    local doc = parser.get_parsed_document(bufnr)
    fold_map_cache = { changedtick = tick, bufnr = bufnr, conceallevel = conceal, map = build_fold_map(doc) }
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
        { TOOL_USE_ICON .. " ", "FlemmaToolIcon" },
        { "Tool Use: ", "FlemmaToolUseTitle" },
      }

      -- Pass generous available to get the untruncated structured preview;
      -- we compute actual available after knowing label width.
      local structured = get_tool_use_body(tool_seg, text_width)
      local label = structured.label
      local detail = structured.detail

      local fixed_chrome = str.strwidth(TOOL_USE_ICON .. " ")
        + str.strwidth("Tool Use: ")
        + str.strwidth(tool_seg.name)
        + str.strwidth(": ")
        + str.strwidth(" ") -- trailing space before suffix
        + str.strwidth(suffix)
      local separator_width = str.strwidth(LABEL_DETAIL_SEPARATOR)
      if detail then
        fixed_chrome = fixed_chrome + str.strwidth(detail) + separator_width
      end
      local available = text_width - fixed_chrome

      table.insert(chunks, { tool_seg.name, "FlemmaToolName" })

      if label or detail then
        table.insert(chunks, { ": ", "FlemmaToolName" })

        if detail then
          table.insert(chunks, { detail, "FlemmaToolDetail" })
          if label and available > 0 then
            local label_text = str.truncate(label, available, CONTENT_PREVIEW_TRUNCATION_MARKER)
            if label_text ~= "" then
              table.insert(chunks, { LABEL_DETAIL_SEPARATOR .. label_text, "FlemmaToolLabel" })
            end
          end
        else
          local label_text =
            str.truncate(label --[[@as string]], available + separator_width, CONTENT_PREVIEW_TRUNCATION_MARKER)
          table.insert(chunks, { label_text, "FlemmaToolLabel" })
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
      local effective_status = query.effective_tool_result_status(tool_seg, doc)

      local icon_hl = "FlemmaToolIcon"
      if effective_status == "error" then
        icon_hl = "FlemmaToolIconError"
      elseif not effective_status and tool_seg.content ~= "" then
        icon_hl = "FlemmaToolIconSuccess"
      end

      ---@type {[1]:string, [2]:string}[]
      local chunks = {
        { TOOL_RESULT_ICON .. " ", icon_hl },
        { "Tool Result: ", "FlemmaToolResultTitle" },
        { tool_name, "FlemmaToolName" },
      }

      local fixed_chrome = str.strwidth(TOOL_RESULT_ICON .. " ")
        + str.strwidth("Tool Result: ")
        + str.strwidth(tool_name)
        + str.strwidth(": ")
        + str.strwidth(" ") -- trailing space before suffix
        + str.strwidth(suffix)
      if effective_status == "error" then
        fixed_chrome = fixed_chrome + str.strwidth("(error) ")
      end
      local result_separator_width = str.strwidth(LABEL_DETAIL_SEPARATOR)
      local available = text_width - fixed_chrome

      table.insert(chunks, { ": ", "FlemmaFoldPreview" })
      if effective_status == "error" then
        table.insert(chunks, { "(error) ", "FlemmaToolResultError" })
      end

      local body = preview.format_content_preview(tool_seg.content, available)
      if tool_label then
        if body ~= "" then
          local body_text = str.truncate(body, available - result_separator_width, CONTENT_PREVIEW_TRUNCATION_MARKER)
          if body_text ~= "" then
            table.insert(chunks, { body_text, "FlemmaFoldPreview" })
            available = available - str.strwidth(body_text)
          end
          if available > result_separator_width then
            local label_text =
              str.truncate(tool_label, available - result_separator_width, CONTENT_PREVIEW_TRUNCATION_MARKER)
            if label_text ~= "" then
              table.insert(chunks, { LABEL_DETAIL_SEPARATOR .. label_text, "FlemmaToolLabel" })
            end
          end
        else
          local label_text = str.truncate(tool_label, available, CONTENT_PREVIEW_TRUNCATION_MARKER)
          if label_text ~= "" then
            table.insert(chunks, { label_text, "FlemmaToolLabel" })
          end
        end
      elseif body ~= "" then
        table.insert(chunks, { body, "FlemmaFoldPreview" })
      end

      table.insert(chunks, { " ", "FlemmaFoldPreview" })
      table.insert(chunks, { suffix, "FlemmaFoldMeta" })
      return chunks
    elseif tool_kind == "job_result" then
      ---@cast tool_seg flemma.ast.JobResultSegment
      local icon_hl = "FlemmaToolIcon"
      if tool_seg.status == "error" then
        icon_hl = "FlemmaToolIconError"
      elseif tool_seg.content ~= "" then
        icon_hl = "FlemmaToolIconSuccess"
      end

      ---@type {[1]:string, [2]:string}[]
      local chunks = {
        { TOOL_RESULT_ICON .. " ", icon_hl },
        { "Job Result: ", "FlemmaJobResultTitle" },
        { tool_seg.job_id, "FlemmaToolName" },
      }

      local fixed_chrome = str.strwidth(TOOL_RESULT_ICON .. " ")
        + str.strwidth("Job Result: ")
        + str.strwidth(tool_seg.job_id)
        + str.strwidth(": ")
        + str.strwidth(" ")
        + str.strwidth(suffix)
      if tool_seg.status == "error" then
        fixed_chrome = fixed_chrome + str.strwidth("(error) ")
      end
      local available = text_width - fixed_chrome

      table.insert(chunks, { ": ", "FlemmaFoldPreview" })
      if tool_seg.status == "error" then
        table.insert(chunks, { "(error) ", "FlemmaToolResultError" })
      end

      local body = preview.format_content_preview(tool_seg.content, available)
      if body ~= "" then
        table.insert(chunks, { body, "FlemmaFoldPreview" })
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
    -- FlemmaRole* is fg-only (highlight.lua), so line_hl_group's tint shows through
    -- uniformly across the fold. Using FlemmaUser/System/Assistant here would stamp
    -- Normal's bg (via link) over FlemmaLineUser/System/Assistant, creating stripes.
    local content_hl = role_hl

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
  vim.wo[winid].foldlevel = config_facade.get().editing.foldlevel
end

---Close all open sub-folds within a line range before closing the outer fold.
---Scans the cached fold map for fold-start markers (`>N`) and closes each one
---individually, skipping any that are already closed. Processing fold starts
---individually avoids the Vim limitation where a range `:foldclose` skips lines
---hidden inside an earlier closed fold.
---@param start_line integer First body line (after the outer fold's start line)
---@param end_line integer Last line of the outer fold
local function close_sub_folds(start_line, end_line)
  for lnum = start_line, end_line do
    local expr = fold_map_cache.map[lnum]
    if expr and expr:sub(1, 1) == ">" and vim.fn.foldclosed(lnum) == -1 then
      pcall(function()
        vim.cmd(lnum .. " foldclose")
      end)
    end
  end
end

---Toggle the message fold containing the cursor.
---Always operates on the level-1 message fold, not whatever fold is under the cursor.
---When closing, closes all nested folds first (thinking, tool blocks) so they
---remain tidy when the message is reopened.
---Falls back to toggling the frontmatter fold when the cursor is outside any message.
function M.toggle_message_fold()
  local lnum = vim.fn.line(".")
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = parser.get_parsed_document(bufnr)
  local msg = query.find_message_at_line(doc, lnum)

  if msg then
    local msg_start = msg.position.start_line
    if vim.fn.foldclosed(msg_start) ~= -1 then
      vim.cmd(msg_start .. " foldopen")
    else
      -- Ensure the fold map is fresh so close_sub_folds sees current fold starts
      M.get_fold_level(msg_start)
      close_sub_folds(msg_start + 1, msg.position.end_line)
      vim.cmd(msg_start .. " foldclose")
    end
    return
  end

  -- No message at cursor — check frontmatter. The AST-provided range is what
  -- proves the cursor is inside frontmatter; the conceallevel check below is
  -- then the specific reason we know there is no fold to toggle (rather than,
  -- say, a stale fold map).
  local fm = doc.frontmatter
  if fm and lnum >= fm.position.start_line and lnum <= fm.position.end_line then
    local fm_start = fm.position.start_line
    if vim.wo.conceallevel >= 1 then
      notify.info(
        string.format(
          "frontmatter isn't foldable with conceallevel=%d. This is a Neovim limitation.",
          vim.wo.conceallevel
        )
      )
      return
    end
    if vim.fn.foldclosed(fm_start) ~= -1 then
      vim.cmd(fm_start .. " foldopen")
    else
      vim.cmd(fm_start .. " foldclose")
    end
  end
end

---Rebuild the fold map and tell Neovim to re-evaluate fold levels.
---Called from update_ui on CursorHold/CursorHoldI.
---
---## Why `set foldmethod=expr` is expensive
---
---`set foldmethod=expr` forces Neovim to call the foldexpr callback for
---every visible line. Even if get_fold_level returns instantly, Neovim's
---C-level fold engine must process the returned level string, update the
---fold tree, and recalculate the display. On a 5000-line buffer with ~300
---visible lines, this costs 50-100ms (profiled May 2025). Doing it on
---every CursorHoldI (which fires every `updatetime` ms during pauses in
---insert mode) makes typing feel sluggish.
---
---## Strategy: skip redundant re-evaluations
---
--- 1. **Already current**: if changedtick hasn't advanced, the fold map is
---    already built — skip the rebuild AND the `set foldmethod=expr`. Only
---    re-assert foldmethod if something external switched it away from
---    `expr` (e.g., `:loadview` restoring `foldmethod=manual`).
---
--- 2. **Changed in insert mode**: rebuild the fold map (cheap, ~3ms) so
---    it's ready for the next normal-mode evaluation, but SKIP the
---    `set foldmethod=expr` re-assertion (expensive). get_fold_level is
---    already returning `"="` during insert mode, so Neovim's fold state
---    won't pick up the new map until the user leaves insert mode anyway.
---
--- 3. **Changed in normal mode**: full rebuild + re-assert. This handles
---    undo, `:read`, streaming content, and the first CursorHold after
---    leaving insert mode.
---@param bufnr integer
function M.invalidate_folds(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local conceal = vim.wo.conceallevel
  local foldmethod_ok = vim.wo[winid].foldmethod == "expr"
  -- Path 1: fold map already current — only fix foldmethod if overridden.
  if fold_map_cache.bufnr == bufnr and fold_map_cache.changedtick == tick and fold_map_cache.conceallevel == conceal then
    if not foldmethod_ok then
      vim.fn.win_execute(winid, "set foldmethod=expr")
    end
    return
  end
  -- Paths 2 & 3: rebuild fold map, conditionally re-assert foldmethod.
  local doc = parser.get_parsed_document(bufnr)
  fold_map_cache = { changedtick = tick, bufnr = bufnr, conceallevel = conceal, map = build_fold_map(doc) }
  local mode = vim.api.nvim_get_mode().mode
  if not foldmethod_ok or (mode ~= "i" and mode ~= "ic" and mode ~= "ix" and mode ~= "R" and mode ~= "Rc" and mode ~= "Rx") then
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
  -- All auto-closeable ranges are level-2 folds (tool blocks, thinking,
  -- job results, frontmatter). If foldlevel is only 1, the inner fold
  -- hasn't been established yet (foldexpr is lazy) and :foldclose would
  -- close the enclosing level-1 message fold instead.
  if not fold_level or fold_level < 2 then
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
  if buffer_state.fold_completed_tick ~= tick then
    buffer_state.pending_folds_retried = nil
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
  if not buffer_state.pending_folds then
    buffer_state.pending_folds_retried = nil
  end

  if #new_folds > 0 then
    log.debug("fold_completed_blocks(): Auto-closed " .. #new_folds .. " fold(s) in buffer " .. bufnr)
  end

  -- When folds fail because foldexpr hasn't been fully evaluated yet
  -- (newly inserted lines lack fold boundaries), schedule a single
  -- deferred retry. The :redraw forces Vim to evaluate foldexpr for all
  -- visible lines, establishing the fold boundaries that :foldclose needs.
  if buffer_state.pending_folds and not buffer_state.pending_folds_retried then
    buffer_state.pending_folds_retried = true
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local retry_winid = vim.fn.bufwinid(bufnr)
      if retry_winid ~= -1 then
        vim.fn.win_execute(retry_winid, "redraw")
      end
      M.fold_completed_blocks(bufnr)
    end)
  end
end

return M
