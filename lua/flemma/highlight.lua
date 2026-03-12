--- Flemma syntax highlighting and theming functionality
--- Handles all highlight group definitions and syntax rules
---@class flemma.Highlight
local M = {}

local color = require("flemma.utilities.color")
local log = require("flemma.logging")
local state = require("flemma.state")
local str = require("flemma.utilities.string")
local roles = require("flemma.utilities.roles")

---Get color from a highlight group attribute
---@param group_name string Highlight group name (e.g., "Normal")
---@param attr string Attribute to get ("fg" or "bg")
---@return string|nil hex Hex color or nil if not defined
local function get_hl_color(group_name, attr)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group_name, link = false })
  if not ok or not hl then
    return nil
  end
  -- nvim_get_hl returns 'fg' and 'bg' as integers
  local value = hl[attr]
  if value then
    return string.format("#%06x", value)
  end
  return nil
end

---Get the default fallback color for an attribute.
---First tries the Normal highlight group, then falls back to config defaults.
---@param attr string "fg" or "bg"
---@return string hex Hex color
local function get_default_color(attr)
  -- First try Normal group (what Neovim actually uses as default)
  local normal_color = get_hl_color("Normal", attr)
  if normal_color then
    return normal_color
  end

  -- Fall back to config defaults
  local config = state.get_config()
  local is_dark = vim.o.background == "dark"
  local defaults = config.defaults
  if defaults then
    local theme_defaults = is_dark and defaults.dark or defaults.light
    if theme_defaults and theme_defaults[attr] then
      return theme_defaults[attr]
    end
  end
  -- Hardcoded fallback if config.defaults is missing
  if attr == "bg" then
    return is_dark and "#000000" or "#ffffff"
  else
    return is_dark and "#ffffff" or "#000000"
  end
end

-- Valid attribute names for highlight expressions
local VALID_ATTRIBUTES = {
  fg = true,
  bg = true,
  sp = true,
}

---@class flemma.highlight.ResolvedAttrs
---@field fg? string Hex color
---@field bg? string Hex color
---@field sp? string Hex color

---Try to resolve a single highlight expression like "Normal+bg:#101010" or "DiagnosticOk^fg:4.5"
---@param expr string Single expression (no commas)
---@param use_defaults boolean Whether to use defaults when group lacks attribute
---@param contrast_bg? string Hex bg color for ^ contrast enforcement (nil = ignore ^ operators)
---@return flemma.highlight.ResolvedAttrs|nil
local function try_expression(expr, use_defaults, contrast_bg)
  -- Match base group: everything before the first operator (+, -, or ^)
  local base_group = expr:match("^(.-)[%+%-^][fbs][gp]:")
  if not base_group or base_group == "" then
    return nil
  end

  local result = {}

  -- Pass 1: process +/- blend operations
  for op, attr, hex_value in expr:gmatch("([%+%-])([fbs][gp]):(#%x%x%x%x%x%x)") do
    if VALID_ATTRIBUTES[attr] then
      local base_hex = get_hl_color(base_group, attr)
      if not base_hex then
        if not use_defaults then
          return nil
        end
        base_hex = get_default_color(attr)
      end
      local base_rgb = color.hex_to_rgb(base_hex)
      local mod_rgb = color.hex_to_rgb(hex_value)
      if base_rgb and mod_rgb then
        result[attr] = color.rgb_to_hex(color.blend(base_rgb, mod_rgb, op))
      end
    end
  end

  -- Pass 2: process ^ contrast operations (applied after blending)
  for attr, ratio_str in expr:gmatch("%^([fbs][gp]):([%d%.]+)") do
    if VALID_ATTRIBUTES[attr] then
      local target_ratio = tonumber(ratio_str)
      if target_ratio then
        -- Use already-blended result, or fall back to base group's attribute
        local current_hex = result[attr] or get_hl_color(base_group, attr)
        if not current_hex then
          if use_defaults then
            current_hex = get_default_color(attr)
          end
        end
        if current_hex then
          if contrast_bg then
            result[attr] = color.ensure_contrast(current_hex, contrast_bg, target_ratio)
          else
            -- No contrast context: resolve attribute but skip adjustment
            result[attr] = current_hex
          end
        end
      end
    end
  end

  return next(result) and result or nil
end

---Parse a highlight expression string and return resolved highlight options.
---Format: "Group+attr:#color,FallbackGroup+attr:#color,...".
---Comma-separated expressions are tried in order; only last uses defaults.
---@param value string The highlight expression(s)
---@param contrast_bg? string Hex bg color for ^ contrast enforcement
---@return flemma.highlight.ResolvedAttrs|nil
local function parse_highlight_expression(value, contrast_bg)
  if not value:match("[%+%-^][fbs][gp]:") then
    return nil
  end

  local expressions = {}
  for expr in value:gmatch("([^,]+)") do
    table.insert(expressions, expr:match("^%s*(.-)%s*$"))
  end

  for i, expr in ipairs(expressions) do
    local result = try_expression(expr, i == #expressions, contrast_bg)
    if result then
      return result
    end
  end
  return nil
end

---Set highlight groups.
---Accepts a highlight group name to link to, a hex color string,
---a highlight expression, or a table with highlight attributes.
---@param group_name string
---@param value string|table
---@param type_? string For bare hex colors, which attribute to use ("fg" or "bg")
---@param contrast_bg? string Hex bg color for ^ contrast enforcement in expressions
local function set_highlight(group_name, value, type_, contrast_bg)
  if type(value) == "table" then
    if value.light ~= nil or value.dark ~= nil then
      -- Handle theme-specific definitions
      local is_dark = vim.o.background == "dark"
      local theme_value = is_dark and value.dark or value.light
      if theme_value then
        set_highlight(group_name, theme_value, type_, contrast_bg)
      end
    else
      local hl_opts = vim.tbl_extend("force", {}, value)
      -- Add default = true to respect pre-existing user definitions
      hl_opts.default = true
      vim.api.nvim_set_hl(0, group_name, hl_opts)
    end
  elseif type(value) == "string" then
    if value:match("[%+%-^][fbs][gp]:") then
      -- Highlight expression (e.g., "Normal+fg:#101010-bg:#303030" or "Group^fg:4.5")
      local hl_opts = parse_highlight_expression(value, contrast_bg)
      if hl_opts then
        set_highlight(group_name, hl_opts, type_, contrast_bg)
      else
        log.error(
          string.format("set_highlight(): Failed to parse highlight expression for group %s: %s", group_name, value)
        )
      end
    elseif value:sub(1, 1) == "#" then
      -- Bare hex color - use type_ to determine attribute (defaults to fg)
      local hl_opts = {}
      hl_opts[type_ or "fg"] = value
      set_highlight(group_name, hl_opts, type_, contrast_bg)
    elseif type_ then
      -- Highlight group name with specific attribute requested (e.g., for line highlights)
      -- Extract only the specified attribute to avoid overriding other highlights
      local resolved_color = get_hl_color(value, type_)
      if not resolved_color then
        -- Group doesn't have the attribute - use default color (tries Normal first, then config defaults)
        resolved_color = get_default_color(type_)
      end
      local hl_opts = {}
      hl_opts[type_] = resolved_color
      set_highlight(group_name, hl_opts, type_, contrast_bg)
    else
      -- Assume it's a highlight group name to link
      set_highlight(group_name, { link = value }, type_, contrast_bg)
    end
  else
    log.error(string.format("set_highlight(): Invalid value type for group %s: %s", group_name, type(value)))
  end
end

---Public API for resolving a highlight expression with optional contrast context.
---Primarily for testing; internal code uses set_highlight() which calls this indirectly.
---@param value string Highlight expression string
---@param contrast_bg? string Hex bg color for ^ contrast enforcement
---@return flemma.highlight.ResolvedAttrs|nil
function M.resolve_expression(value, contrast_bg)
  return parse_highlight_expression(value, contrast_bg)
end

---Setup CursorLine blend highlight groups for line-highlighted chat buffers.
---Creates FlemmaLine*CursorLine variants that combine role backgrounds with CursorLine styling,
---so the cursor line remains visible on top of role-based line highlights.
local function setup_cursorline_highlights()
  local current_config = state.get_config()
  if not current_config.line_highlights or not current_config.line_highlights.enabled then
    return
  end

  local cl_hl = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false })
  if not cl_hl or not next(cl_hl) then
    return
  end

  -- Compute the bg delta: how CursorLine differs from Normal
  local cl_bg_hex = cl_hl.bg and string.format("#%06x", cl_hl.bg)
  local normal_bg_hex = get_hl_color("Normal", "bg") or get_default_color("bg")

  ---@type {r: integer, g: integer, b: integer}|nil
  local delta_rgb
  if cl_bg_hex then
    local cl_rgb = color.hex_to_rgb(cl_bg_hex)
    local normal_rgb = color.hex_to_rgb(normal_bg_hex)
    if cl_rgb and normal_rgb then
      -- Delta = CursorLine_bg - Normal_bg (per channel, may be negative)
      delta_rgb = {
        r = cl_rgb.r - normal_rgb.r,
        g = cl_rgb.g - normal_rgb.g,
        b = cl_rgb.b - normal_rgb.b,
      }
    end
  end

  -- Collect non-color CursorLine attributes (bold, underline, italic, etc.)
  ---@type table<string, boolean|integer>
  local cl_decorations = {}
  for attr, value in pairs(cl_hl) do
    if attr ~= "bg" and attr ~= "fg" and attr ~= "sp" and attr ~= "link" then
      cl_decorations[attr] = value
    end
  end

  -- Create CursorLine variant for each line highlight group
  local base_groups = {
    "FlemmaLineFrontmatter",
    "FlemmaLineSystem",
    "FlemmaLineUser",
    "FlemmaLineAssistant",
    "FlemmaThinkingBlock",
  }
  for _, base_group in ipairs(base_groups) do
    local role_bg_hex = get_hl_color(base_group, "bg")
    local cl_group_name = base_group .. "CursorLine"

    ---@type vim.api.keyset.highlight
    local hl_opts = vim.tbl_extend("force", {}, cl_decorations)

    if role_bg_hex and delta_rgb then
      -- Blend: apply CursorLine's bg delta onto the role bg
      local role_rgb = color.hex_to_rgb(role_bg_hex)
      if role_rgb then
        local clamp = function(v)
          return math.max(0, math.min(255, v))
        end
        hl_opts.bg = color.rgb_to_hex({
          r = clamp(role_rgb.r + delta_rgb.r),
          g = clamp(role_rgb.g + delta_rgb.g),
          b = clamp(role_rgb.b + delta_rgb.b),
        })
      end
    elseif cl_bg_hex then
      -- No role bg or no delta; use CursorLine bg directly
      hl_opts.bg = cl_bg_hex
    end

    hl_opts.default = true
    vim.api.nvim_set_hl(0, cl_group_name, hl_opts)
  end
end

-- Valid boolean style attributes for nvim_set_hl (used in role_style validation)
local VALID_STYLE_ATTRIBUTES = {
  bold = true,
  italic = true,
  underline = true,
  undercurl = true,
  underdouble = true,
  underdotted = true,
  underdashed = true,
  strikethrough = true,
  reverse = true,
  standout = true,
  nocombine = true,
  altfont = true,
}

---Parse and validate a role_style string, warning about invalid attributes.
---@param role_style string Comma-separated style attributes (e.g., "bold,underline")
---@return table<string, boolean>
local function validate_role_style(role_style)
  ---@type table<string, boolean>
  local attrs = {}
  for token in role_style:gmatch("[^,]+") do
    local style = vim.trim(token)
    if style ~= "" then
      if VALID_STYLE_ATTRIBUTES[style] then
        attrs[style] = true
      else
        local msg = string.format("flemma: invalid role_style '%s'", style)
        local suggestion = str.closest_match(style, VALID_STYLE_ATTRIBUTES)
        if suggestion then
          msg = msg .. string.format(". Did you mean '%s'?", suggestion)
        end
        vim.notify_once(msg, vim.log.levels.WARN)
      end
    end
  end
  return attrs
end

---Apply syntax highlighting and Tree-sitter configuration
M.apply_syntax = function()
  local syntax_config = state.get_config()

  -- Explicitly load our syntax file
  vim.cmd("runtime! syntax/chat.vim")

  -- Set highlights based on user config (link or hex color)
  set_highlight("FlemmaSystem", syntax_config.highlights.system)
  set_highlight("FlemmaUser", syntax_config.highlights.user)
  set_highlight("FlemmaAssistant", syntax_config.highlights.assistant)
  set_highlight("FlemmaUserLuaExpression", syntax_config.highlights.user_lua_expression) -- Highlight for {{expression}} in user messages
  set_highlight("FlemmaUserFileReference", syntax_config.highlights.user_file_reference) -- Highlight for @./file in user messages

  -- Set up spinner highlight with fg-only (no bg) so hl_mode="combine" inherits line highlight bg
  local spinner_fg = get_hl_color("FlemmaAssistant", "fg") or get_default_color("fg")
  vim.api.nvim_set_hl(0, "FlemmaAssistantSpinner", { fg = spinner_fg, default = true })

  -- Set up role marker highlights (e.g., @You:, @System:)
  -- Extract fg from the resolved highlight group, falling back to Normal/defaults.
  -- Parse role_style string into nvim_set_hl attributes (e.g., "bold,underline" -> { bold = true, underline = true }).
  local role_groups = {
    { source = "FlemmaSystem", target = "FlemmaRoleSystem" },
    { source = "FlemmaUser", target = "FlemmaRoleUser" },
    { source = "FlemmaAssistant", target = "FlemmaRoleAssistant" },
  }
  local role_style_attrs = validate_role_style(syntax_config.role_style)
  for _, role in ipairs(role_groups) do
    local fg = get_hl_color(role.source, "fg") or get_default_color("fg")
    -- Syntax group: fg-only (covers whole @Role: line; style would bleed into ruler via hl_mode=combine)
    vim.api.nvim_set_hl(0, role.target, { fg = fg, default = true })
    -- Name group: fg + style (applied via extmark on just the role name text)
    ---@type vim.api.keyset.highlight
    local name_opts = vim.tbl_extend("force", {}, role_style_attrs)
    name_opts.fg = fg
    name_opts.default = true
    vim.api.nvim_set_hl(0, role.target .. "Name", name_opts)
  end

  -- Set ruler highlight group
  set_highlight("FlemmaRuler", syntax_config.ruler.hl)

  -- Set highlight for thinking tags and blocks
  set_highlight("FlemmaThinkingTag", syntax_config.highlights.thinking_tag)
  set_highlight("FlemmaThinkingBlock", syntax_config.highlights.thinking_block)

  -- fg-only variant for fold text preview: bg comes from line_hl_group extmarks,
  -- allowing CursorLine overlay to blend correctly on folded thinking blocks
  local thinking_fg = get_hl_color("FlemmaThinkingBlock", "fg") or get_hl_color("Comment", "fg")
  if thinking_fg then
    vim.api.nvim_set_hl(0, "FlemmaThinkingFoldPreview", { fg = thinking_fg, default = true })
  else
    vim.api.nvim_set_hl(0, "FlemmaThinkingFoldPreview", { link = "Comment", default = true })
  end

  -- Set highlight for tool use and tool result syntax
  -- Note: Tool names and IDs in backticks are handled by treesitter markdown_inline
  set_highlight("FlemmaToolIcon", syntax_config.highlights.tool_icon)
  set_highlight("FlemmaToolName", syntax_config.highlights.tool_name)
  set_highlight("FlemmaToolUseTitle", syntax_config.highlights.tool_use_title)
  set_highlight("FlemmaToolResultTitle", syntax_config.highlights.tool_result_title)
  set_highlight("FlemmaToolResultError", syntax_config.highlights.tool_result_error)
  set_highlight("FlemmaToolPreview", syntax_config.highlights.tool_preview)

  -- Set highlight for fold text segments
  set_highlight("FlemmaFoldPreview", syntax_config.highlights.fold_preview)
  set_highlight("FlemmaFoldMeta", syntax_config.highlights.fold_meta)

  -- Tool execution indicator highlights
  set_highlight("FlemmaToolPending", { link = "DiagnosticInfo", default = true })
  set_highlight("FlemmaToolSuccess", { link = "DiagnosticOk", default = true })
  set_highlight("FlemmaToolError", { link = "DiagnosticError", default = true })

  -- Notification bar highlight groups
  -- Derived from the first group in notifications.hl that provides both fg and bg
  local bar_bg_hex, bar_fg_hex, notification_base_group
  for candidate in syntax_config.notifications.highlight:gmatch("[^,]+") do
    candidate = vim.trim(candidate)
    local bg = get_hl_color(candidate, "bg")
    local fg = get_hl_color(candidate, "fg")
    if bg and fg then
      bar_bg_hex = bg
      bar_fg_hex = fg
      notification_base_group = candidate
      break
    end
  end

  if bar_bg_hex and bar_fg_hex then
    -- Primary tier: base group fg + bg as-is (model name, cost)
    vim.api.nvim_set_hl(0, "FlemmaNotificationsBar", { bg = bar_bg_hex, fg = bar_fg_hex, default = true })

    -- Secondary tier: slightly dimmed fg (cache label, token counts, request count)
    local is_dark = vim.o.background == "dark"
    local secondary_expr = notification_base_group .. (is_dark and "-fg:#222222" or "+fg:#222222")
    local secondary_resolved = parse_highlight_expression(secondary_expr)
    if secondary_resolved and secondary_resolved.fg then
      vim.api.nvim_set_hl(
        0,
        "FlemmaNotificationsSecondary",
        { bg = bar_bg_hex, fg = secondary_resolved.fg, default = true }
      )
    end

    -- Muted tier: more dimmed fg (provider, separators, session label)
    local muted_expr = notification_base_group .. (is_dark and "-fg:#444444" or "+fg:#444444")
    local muted_resolved = parse_highlight_expression(muted_expr)
    if muted_resolved and muted_resolved.fg then
      vim.api.nvim_set_hl(0, "FlemmaNotificationsMuted", { bg = bar_bg_hex, fg = muted_resolved.fg, default = true })
    end

    -- Semantic cache highlights with contrast enforcement
    local cache_good_fg = get_hl_color("DiagnosticOk", "fg")
    if cache_good_fg then
      cache_good_fg = color.ensure_contrast(cache_good_fg, bar_bg_hex, 4.5)
      vim.api.nvim_set_hl(0, "FlemmaNotificationsCacheGood", { bg = bar_bg_hex, fg = cache_good_fg, default = true })
    else
      vim.api.nvim_set_hl(0, "FlemmaNotificationsCacheGood", { link = "DiagnosticOk", default = true })
    end

    local cache_bad_fg = get_hl_color("DiagnosticWarn", "fg")
    if cache_bad_fg then
      cache_bad_fg = color.ensure_contrast(cache_bad_fg, bar_bg_hex, 4.5)
      vim.api.nvim_set_hl(0, "FlemmaNotificationsCacheBad", { bg = bar_bg_hex, fg = cache_bad_fg, default = true })
    else
      vim.api.nvim_set_hl(0, "FlemmaNotificationsCacheBad", { link = "DiagnosticWarn", default = true })
    end

    -- Bottom border: sp matches the muted fg so │ separators and border look uniform
    local border_style = syntax_config.notifications.border
    if border_style then
      local muted_fg = get_hl_color("FlemmaNotificationsMuted", "fg")
      if muted_fg then
        vim.api.nvim_set_hl(0, "FlemmaNotificationsBottom", { [border_style] = true, sp = muted_fg, default = true })
      end
    end
  else
    -- Fallback when no candidate group provides both bg and fg: link to StatusLine
    vim.api.nvim_set_hl(0, "FlemmaNotificationsBar", { link = "StatusLine", default = true })
    vim.api.nvim_set_hl(0, "FlemmaNotificationsSecondary", { link = "StatusLine", default = true })
    vim.api.nvim_set_hl(0, "FlemmaNotificationsMuted", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "FlemmaNotificationsCacheGood", { link = "DiagnosticOk", default = true })
    vim.api.nvim_set_hl(0, "FlemmaNotificationsCacheBad", { link = "DiagnosticWarn", default = true })
    local fallback_border_style = syntax_config.notifications.border
    if fallback_border_style then
      local muted_fallback = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
      vim.api.nvim_set_hl(
        0,
        "FlemmaNotificationsBottom",
        { [fallback_border_style] = true, sp = muted_fallback.fg, default = true }
      )
    end
  end

  -- Progress bar highlight groups
  -- Derived from the first group in progress.highlight that provides both fg and bg
  local progress_config = syntax_config.progress or { highlight = "@text.note,PmenuSel" }
  local progress_bg_hex, progress_fg_hex
  for candidate in (progress_config.highlight or ""):gmatch("[^,]+") do
    candidate = vim.trim(candidate)
    local bg = get_hl_color(candidate, "bg")
    local fg = get_hl_color(candidate, "fg")
    if bg and fg then
      progress_bg_hex = bg
      progress_fg_hex = fg
      break
    end
  end

  if progress_bg_hex and progress_fg_hex then
    vim.api.nvim_set_hl(0, "FlemmaProgressBar", { bg = progress_bg_hex, fg = progress_fg_hex, default = true })
  else
    -- Fallback: link to StatusLine
    vim.api.nvim_set_hl(0, "FlemmaProgressBar", { link = "StatusLine", default = true })
  end

  -- Create CursorLine blend variants after all base groups are defined
  setup_cursorline_highlights()
end

---Setup line highlight groups for full-line background highlighting
local function setup_line_highlights()
  local current_config = state.get_config()
  if not current_config.line_highlights or not current_config.line_highlights.enabled then
    return
  end

  local line_highlight_keys = { "frontmatter", "user", "system", "assistant" }
  for _, key in ipairs(line_highlight_keys) do
    local role_config = current_config.line_highlights[key]
    if role_config then
      local group_name = "FlemmaLine" .. roles.capitalize(key)
      set_highlight(group_name, role_config, "bg")
    end
  end
end

---Setup signs for different roles
local function setup_signs()
  local current_config = state.get_config()
  if current_config.signs.enabled then
    -- Define signs using internal keys ('user', 'system', 'assistant')
    local signs = {
      ["user"] = { config = current_config.signs.user, highlight = current_config.highlights.user },
      ["system"] = { config = current_config.signs.system, highlight = current_config.highlights.system },
      ["assistant"] = { config = current_config.signs.assistant, highlight = current_config.highlights.assistant },
    }
    -- Iterate using internal keys
    for internal_role_key, sign_data in pairs(signs) do
      -- Define the specific highlight group name for the sign (e.g., FlemmaSignUser)
      local sign_hl_group = "FlemmaSign" .. roles.capitalize(internal_role_key)

      -- Set the sign highlight group if highlighting is enabled
      if sign_data.config.hl ~= false then
        local target_hl = sign_data.config.hl == true and sign_data.highlight or sign_data.config.hl
        set_highlight(sign_hl_group, target_hl --[[@as string|table]]) -- Use the helper function

        -- Define the sign using the internal key (e.g., flemma_user)
        local sign_name = "flemma_" .. internal_role_key
        vim.fn.sign_define(sign_name, {
          text = sign_data.config.char or current_config.signs.char,
          texthl = sign_hl_group, -- Use the linked group
        })
      else
        -- Define the sign without a highlight group if hl is false
        local sign_name = "flemma_" .. internal_role_key
        vim.fn.sign_define(sign_name, {
          text = sign_data.config.char or current_config.signs.char,
          -- texthl is omitted
        })
      end
    end
  end
end

---Setup function to initialize highlighting functionality
M.setup = function()
  -- Create or clear the augroup for highlight-related autocmds
  local augroup = vim.api.nvim_create_augroup("FlemmaHighlight", { clear = true })

  -- Set up line highlights for full-line background colors
  setup_line_highlights()

  -- Set up signs
  setup_signs()

  -- Set up autocmd for the chat filetype
  -- NOTE: Only apply_syntax() here — update_ui is handled by the FlemmaUI augroup
  -- (BufEnter/BufWinEnter/CursorHold) to avoid redundant fold/sign/ruler work.
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    group = augroup,
    pattern = { "*.chat", "chat" },
    callback = function()
      M.apply_syntax()
    end,
  })
end

return M
