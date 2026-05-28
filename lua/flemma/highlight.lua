--- Flemma syntax highlighting and theming functionality
--- Handles all highlight group definitions and syntax rules
---@class flemma.Highlight
local M = {}

local config_facade = require("flemma.config")
local h = require("flemma.hl")
local preprocessor_syntax = require("flemma.preprocessor.syntax")
local roles = require("flemma.utilities.roles")

local FENCE_CURSORLINE_CONTRAST = 4.5

---@type table<string, table<string, string>>
local fence_cursorline_map = {}

---Walk a chain of highlight group names and return the first group whose
---resolved highlight definition provides BOTH a foreground and a background
---colour.
---@param chain string|string[] Comma-separated string or list of group names
---@return string|nil group The first complete group, or nil
function M.resolve_first_complete(chain)
  local names
  if type(chain) == "string" then
    names = {}
    for name in chain:gmatch("[^,]+") do
      table.insert(names, vim.trim(name))
    end
  else
    names = chain
  end
  for _, name in ipairs(names) do
    if name ~= "" then
      if h.from(name):expect("fg", "bg"):get() then
        return name
      end
    end
  end
  return nil
end

---Setup CursorLine blend highlight groups for line-highlighted chat buffers.
---Creates FlemmaLine*CursorLine variants that combine role backgrounds with CursorLine styling.
local function setup_cursorline_highlights()
  local current_config = config_facade.get()
  if not current_config.line_highlights or not current_config.line_highlights.enabled then
    return
  end

  if not h.from("CursorLine"):get() then
    return
  end

  local cl_delta = h.diff("Normal", "CursorLine", "bg")
  local cl_decorations = h.from("CursorLine"):omit("fg", "bg", "sp")

  local base_groups = {
    "FlemmaLineFrontmatter",
    "FlemmaLineSystem",
    "FlemmaLineUser",
    "FlemmaLineAssistant",
    "FlemmaThinkingBlock",
  }
  for _, base_group in ipairs(base_groups) do
    h.from(base_group):blend("bg", cl_delta):merge(cl_decorations):set(base_group .. "CursorLine", { default = false })
  end

  -- Precompute contrast-adjusted fence highlight groups for CursorLine overlays.
  fence_cursorline_map = {}
  local fence_source_groups = { "FlemmaFenceBar", "FlemmaFenceLabel" }
  for _, base_group in ipairs(base_groups) do
    local cl_group_name = base_group .. "CursorLine"
    local cl_bg = h.from(cl_group_name):pick("bg")

    ---@type table<string, string>
    local variants = {}
    for _, fence_group in ipairs(fence_source_groups) do
      local variant_name = fence_group .. "On" .. cl_group_name
      local variant_op = h.from(fence_group):contrast("fg", cl_bg, FENCE_CURSORLINE_CONTRAST):pick("fg")
      if variant_op:get() then
        variant_op:set(variant_name, { default = false })
        variants[fence_group] = variant_name
      end
    end

    if next(variants) then
      fence_cursorline_map[cl_group_name] = variants
    end
  end
end

---Setup line highlight groups for full-line background highlighting
local function setup_line_highlights()
  local current_config = config_facade.get()
  if not current_config.line_highlights or not current_config.line_highlights.enabled then
    return
  end

  local line_highlight_keys = { "frontmatter", "user", "system", "assistant" }
  for _, key in ipairs(line_highlight_keys) do
    ---@type flemma.hl.HlOp|nil
    local role_op = current_config.line_highlights[key]
    if role_op then
      local group_name = "FlemmaLine" .. roles.capitalize(key)
      h.coalesce(role_op:pick("bg"), h.default("bg")):set(group_name)
    end
  end
end

---Apply syntax highlighting and Tree-sitter configuration
M.apply_syntax = function()
  local syntax_config = config_facade.get()

  vim.cmd("runtime! syntax/chat.vim")

  -- Line highlights must be established before any group that reads FlemmaLine*
  setup_line_highlights()

  -- Config-driven highlight groups: each value is an HlOp, call :set() directly
  syntax_config.highlights.system:set("FlemmaSystem")
  syntax_config.highlights.user:set("FlemmaUser")
  syntax_config.highlights.assistant:set("FlemmaAssistant")
  syntax_config.highlights.lua_expression:set("FlemmaLuaExpression")
  syntax_config.highlights.lua_code_block:set("FlemmaLuaCodeBlock")
  syntax_config.highlights.lua_delimiter:set("FlemmaLuaDelimiter")

  -- Apply rewriter-owned syntax rules and highlights
  preprocessor_syntax.apply(syntax_config)

  -- Spinner: fg-only from resolved assistant group
  h.from("FlemmaAssistant"):pick("fg"):set("FlemmaAssistantSpinner")

  -- Role markers: fg extraction + role_name config merge
  local role_name_op = syntax_config.highlights.role_name
  local role_groups = {
    { source = "FlemmaSystem", target = "FlemmaRoleSystem" },
    { source = "FlemmaUser", target = "FlemmaRoleUser" },
    { source = "FlemmaAssistant", target = "FlemmaRoleAssistant" },
  }
  for _, role in ipairs(role_groups) do
    h.from(role.source):pick("fg"):set(role.target)
    h.from(role.source):pick("fg"):merge(role_name_op):set(role.target .. "Name")
  end

  -- Ruler
  syntax_config.ruler.hl:set("FlemmaRuler")

  -- Fence labels/bars
  syntax_config.highlights.fence_label:set("FlemmaFenceLabel")
  syntax_config.highlights.fence_bar:set("FlemmaFenceBar")

  -- Thinking: merge assistant line bg as fallback when line highlights are enabled,
  -- so folded thinking blocks show the assistant tint instead of Folded bg
  syntax_config.highlights.thinking_tag:set("FlemmaThinkingTag")
  local thinking_op = syntax_config.highlights.thinking_block
  if syntax_config.line_highlights and syntax_config.line_highlights.enabled then
    thinking_op:merge(h.from("FlemmaLineAssistant"):pick("bg")):set("FlemmaThinkingBlock")
  else
    thinking_op:set("FlemmaThinkingBlock")
  end

  -- Thinking fold preview: fg-only from thinking block or Comment
  h.coalesce(h.from("FlemmaThinkingBlock"):pick("fg"), h.from("Comment"):pick("fg"), h.link("Comment"))
    :set("FlemmaThinkingFoldPreview")

  -- Tool use and tool result highlights
  syntax_config.highlights.tool_icon:set("FlemmaToolIcon")
  syntax_config.highlights.tool_name:set("FlemmaToolName")
  syntax_config.highlights.tool_use_title:set("FlemmaToolUseTitle")
  syntax_config.highlights.tool_result_title:set("FlemmaToolResultTitle")
  syntax_config.highlights.tool_result_error:set("FlemmaToolResultError")
  syntax_config.highlights.tool_result_pending:set("FlemmaToolResultPending")
  syntax_config.highlights.tool_result_approved:set("FlemmaToolResultApproved")
  syntax_config.highlights.tool_result_rejected:set("FlemmaToolResultRejected")
  syntax_config.highlights.tool_result_denied:set("FlemmaToolResultDenied")
  syntax_config.highlights.tool_result_aborted:set("FlemmaToolResultAborted")
  syntax_config.highlights.tool_preview:set("FlemmaToolPreview")

  -- Job result highlights (linked to tool result counterparts)
  h.link("FlemmaToolResultTitle"):set("FlemmaJobResultTitle")
  h.link("FlemmaToolResultError"):set("FlemmaJobResultError")
  h.link("FlemmaToolResultPending"):set("FlemmaJobResultPending")
  h.link("FlemmaToolResultApproved"):set("FlemmaJobResultApproved")
  h.link("FlemmaToolResultRejected"):set("FlemmaJobResultRejected")
  h.link("FlemmaToolResultDenied"):set("FlemmaJobResultDenied")
  h.link("FlemmaToolResultAborted"):set("FlemmaJobResultAborted")

  -- Fold text segments
  syntax_config.highlights.fold_preview:set("FlemmaFoldPreview")
  syntax_config.highlights.fold_meta:set("FlemmaFoldMeta")

  -- Tool label: style for human-readable tool intent in folds
  syntax_config.highlights.tool_label:set("FlemmaToolLabel")

  -- Tool detail
  syntax_config.highlights.tool_detail:set("FlemmaToolDetail")

  -- Approval highlights
  local approval_bg_op = syntax_config.highlights.approval_line:pick("bg")
  h.coalesce(approval_bg_op, h.attrs({})):set("FlemmaApprovalLine", { default = false })
  local approval_sub_groups = {
    { "FlemmaApprovalIndicator", syntax_config.highlights.approval_indicator },
    { "FlemmaApprovalLabel", syntax_config.highlights.approval_label },
    { "FlemmaApprovalKey", syntax_config.highlights.approval_key },
    { "FlemmaApprovalAction", syntax_config.highlights.approval_action },
  }
  for _, entry in ipairs(approval_sub_groups) do
    entry[2]:merge(approval_bg_op):set(entry[1])
  end

  -- Tool indicator icon highlights
  h.link("DiagnosticInfo"):set("FlemmaToolIconPending")
  h.link("FlemmaToolResultTitle"):set("FlemmaToolIconExecuting")
  h.link("FlemmaToolResultTitle"):set("FlemmaToolIconSuccess")
  h.link("DiagnosticError"):set("FlemmaToolIconError")
  h.link("FlemmaToolResultRejected"):set("FlemmaToolIconRejected")
  h.link("FlemmaToolResultDenied"):set("FlemmaToolIconDenied")
  h.link("FlemmaToolResultAborted"):set("FlemmaToolIconAborted")
  -- Tool indicator status highlights
  h.link("DiagnosticHint"):set("FlemmaToolPending")
  h.link("DiagnosticInfo"):set("FlemmaToolExecuting")
  h.link("DiagnosticOk"):set("FlemmaToolSuccess")
  h.link("DiagnosticError"):set("FlemmaToolError")

  -- Integration busy indicator
  syntax_config.highlights.busy:set("FlemmaBusy")

  -- Turns column
  h.link("FlemmaRuler"):set("FlemmaTurn")

  -- Usage bar highlight groups
  local usage_ops = {}
  for name in syntax_config.ui.usage.highlight:gmatch("[^,]+") do
    table.insert(usage_ops, h.from(vim.trim(name)):expect("fg", "bg"))
  end
  table.insert(usage_ops, h.from("StatusLine"))
  local bar_base = h.coalesce(unpack(usage_ops))

  bar_base:set("FlemmaUsageBar")
  bar_base:mute("fg", "#222222"):set("FlemmaUsageBarSecondary")
  bar_base:mute("fg", "#444444"):set("FlemmaUsageBarMuted")

  -- Semantic cache highlights with contrast enforcement
  h.coalesce(h.from("DiagnosticOk"):contrast("fg", bar_base:pick("bg"), 4.5), h.link("DiagnosticOk"))
    :set("FlemmaUsageBarCacheGood")
  h.coalesce(h.from("DiagnosticWarn"):contrast("fg", bar_base:pick("bg"), 4.5), h.link("DiagnosticWarn"))
    :set("FlemmaUsageBarCacheBad")

  -- Progress bar highlight groups
  local progress_config = syntax_config.ui and syntax_config.ui.progress or { highlight = "StatusLine" }
  local progress_ops = {}
  for name in (progress_config.highlight or ""):gmatch("[^,]+") do
    table.insert(progress_ops, h.from(vim.trim(name)):expect("fg", "bg"))
  end
  table.insert(progress_ops, h.from("StatusLine"))
  local progress_base = h.coalesce(unpack(progress_ops))
  progress_base:set("FlemmaProgressBar")
  progress_base:merge(syntax_config.highlights.progress_accent):set("FlemmaProgressBarAccent")

  -- StatusTextMuted: themed StatusLine fg blend + StatusLine bg.
  -- Requires both fg and bg from StatusLine; falls back to Comment link.
  local statusline_base = h.from("StatusLine"):expect("fg", "bg")
  h.coalesce(statusline_base:mute("fg", "#666666"), h.link("Comment")):set("FlemmaStatusTextMuted")

  -- CursorLine highlights depend on FlemmaLine* groups established above
  setup_cursorline_highlights()
end

---Read and strip fenced code block conceal directives from a treesitter
---highlights query.
---@param lang string Treesitter language name
---@param query_name string Query name (e.g., "highlights")
---@return string|nil original, string|nil stripped
local function read_fence_conceal_directives(lang, query_name)
  local files = vim.treesitter.query.get_files(lang, query_name)
  if #files == 0 then
    return nil, nil
  end
  local parts = {}
  for _, file in ipairs(files) do
    local f = io.open(file, "r")
    if f then
      table.insert(parts, f:read("*a"))
      f:close()
    end
  end
  local text = table.concat(parts, "\n")
  if not text:find("conceal_lines") then
    return nil, nil
  end
  local stripped = text:gsub('%s*%(#set! conceal_lines ""%)', "")
  stripped = stripped:gsub('%s*%(#set! conceal ""%)', "")
  return text, stripped
end

local fence_conceal_patched = false

---@type string|nil
local original_markdown_query

---@type string|nil
local stripped_markdown_query

---@return boolean
function M.is_fence_conceal_patched()
  return fence_conceal_patched
end

---@return table<string, table<string, string>>
function M.get_fence_cursorline_map()
  return fence_cursorline_map
end

---Strip fenced code block conceal from the markdown treesitter highlights query.
---Idempotent — safe to call on every .chat BufRead; only patches once.
function M.strip_fence_conceal()
  if fence_conceal_patched then
    return
  end
  local cfg = config_facade.get()
  if cfg.experimental and cfg.experimental.patch_markdown_conceal == false then
    return
  end
  local original, stripped = read_fence_conceal_directives("markdown", "highlights")
  if not original or not stripped then
    return
  end
  fence_conceal_patched = true
  original_markdown_query = original
  stripped_markdown_query = stripped
  vim.treesitter.query.set("markdown", "highlights", stripped)
  for _, hl_obj in pairs(vim.treesitter.highlighter.active) do
    if hl_obj._conceal_line then
      hl_obj._conceal_line = false
      hl_obj._conceal_checked = {}
    end
  end
end

---Restore the original markdown highlights query for a non-chat buffer's
---treesitter highlighter.
---@param bufnr integer
function M.restore_highlighter_conceal(bufnr)
  if not fence_conceal_patched or not original_markdown_query or not stripped_markdown_query then
    return
  end
  local hl_obj = vim.treesitter.highlighter.active[bufnr]
  if not hl_obj or hl_obj._conceal_line then
    return
  end
  vim.treesitter.query.set("markdown", "highlights", original_markdown_query)
  vim.treesitter.stop(bufnr)
  vim.treesitter.start(bufnr)
  vim.treesitter.query.set("markdown", "highlights", stripped_markdown_query)
end

---Setup function to initialize highlighting functionality
M.setup = function()
  local augroup = vim.api.nvim_create_augroup("FlemmaHighlight", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    group = augroup,
    pattern = { "*.chat", "chat" },
    callback = function()
      M.apply_syntax()
    end,
  })
end

return M
