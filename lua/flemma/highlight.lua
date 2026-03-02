--- Flemma syntax highlighting and theming functionality
--- Handles all highlight group definitions and syntax rules
---@class flemma.Highlight
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")
local roles = require("flemma.utilities.roles")

---@class flemma.highlight.RGB
---@field r integer 0-255
---@field g integer 0-255
---@field b integer 0-255

---Convert hex color string to RGB table
---@param hex? string Hex color (e.g., "#ff0000" or "ff0000")
---@return flemma.highlight.RGB|nil
local function hex_to_rgb(hex)
  if not hex then
    return nil
  end
  hex = hex:gsub("^#", "")
  if #hex ~= 6 then
    return nil
  end
  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)
  if not (r and g and b) then
    return nil
  end
  return { r = r, g = g, b = b }
end

---Convert RGB table to hex color string
---@param rgb flemma.highlight.RGB
---@return string hex Hex color (e.g., "#ff0000")
local function rgb_to_hex(rgb)
  return string.format("#%02x%02x%02x", math.floor(rgb.r), math.floor(rgb.g), math.floor(rgb.b))
end

---Blend two colors by adding their RGB values (clamped to 0-255)
---@param base_rgb flemma.highlight.RGB
---@param mod_rgb flemma.highlight.RGB
---@param direction "+" | "-"
---@return flemma.highlight.RGB
local function blend_colors(base_rgb, mod_rgb, direction)
  local clamp = function(v)
    return math.max(0, math.min(255, v))
  end
  if direction == "+" then
    return {
      r = clamp(base_rgb.r + mod_rgb.r),
      g = clamp(base_rgb.g + mod_rgb.g),
      b = clamp(base_rgb.b + mod_rgb.b),
    }
  else
    return {
      r = clamp(base_rgb.r - mod_rgb.r),
      g = clamp(base_rgb.g - mod_rgb.g),
      b = clamp(base_rgb.b - mod_rgb.b),
    }
  end
end

---Mix two colors by linear interpolation
---@param color_a flemma.highlight.RGB
---@param color_b flemma.highlight.RGB
---@param factor number 0.0 = all color_a, 1.0 = all color_b
---@return flemma.highlight.RGB
local function mix_colors(color_a, color_b, factor)
  return {
    r = math.floor(color_a.r * (1 - factor) + color_b.r * factor + 0.5),
    g = math.floor(color_a.g * (1 - factor) + color_b.g * factor + 0.5),
    b = math.floor(color_a.b * (1 - factor) + color_b.b * factor + 0.5),
  }
end

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

---Try to resolve a single highlight expression like "Normal+bg:#101010"
---@param expr string Single expression (no commas)
---@param use_defaults boolean Whether to use defaults when group lacks attribute
---@return flemma.highlight.ResolvedAttrs|nil
local function try_expression(expr, use_defaults)
  local base_group = expr:match("^(.-)[%+%-][fbs][gp]:")
  if not base_group or base_group == "" then
    return nil
  end

  local result = {}
  for op, attr, color in expr:gmatch("([%+%-])([fbs][gp]):(#%x%x%x%x%x%x)") do
    if VALID_ATTRIBUTES[attr] then
      local base_hex = get_hl_color(base_group, attr)
      if not base_hex then
        if not use_defaults then
          return nil
        end
        base_hex = get_default_color(attr)
      end
      local base_rgb = hex_to_rgb(base_hex)
      local mod_rgb = hex_to_rgb(color)
      if base_rgb and mod_rgb then
        result[attr] = rgb_to_hex(blend_colors(base_rgb, mod_rgb, op))
      end
    end
  end
  return next(result) and result or nil
end

---Parse a highlight expression string and return resolved highlight options.
---Format: "Group+attr:#color,FallbackGroup+attr:#color,...".
---Comma-separated expressions are tried in order; only last uses defaults.
---@param value string The highlight expression(s)
---@return flemma.highlight.ResolvedAttrs|nil
local function parse_highlight_expression(value)
  if not value:match("[%+%-][fbs][gp]:") then
    return nil
  end

  local expressions = {}
  for expr in value:gmatch("([^,]+)") do
    table.insert(expressions, expr:match("^%s*(.-)%s*$"))
  end

  for i, expr in ipairs(expressions) do
    local result = try_expression(expr, i == #expressions)
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
local function set_highlight(group_name, value, type_)
  if type(value) == "table" then
    if value.light ~= nil or value.dark ~= nil then
      -- Handle theme-specific definitions
      local is_dark = vim.o.background == "dark"
      local theme_value = is_dark and value.dark or value.light
      if theme_value then
        set_highlight(group_name, theme_value, type_)
      end
    else
      local hl_opts = vim.tbl_extend("force", {}, value)
      -- Add default = true to respect pre-existing user definitions
      hl_opts.default = true
      vim.api.nvim_set_hl(0, group_name, hl_opts)
    end
  elseif type(value) == "string" then
    if value:match("[%+%-][fbs][gp]:") then
      -- Highlight expression (e.g., "Normal+fg:#101010-bg:#303030")
      local hl_opts = parse_highlight_expression(value)
      if hl_opts then
        set_highlight(group_name, hl_opts, type_)
      else
        log.error(
          string.format("set_highlight(): Failed to parse highlight expression for group %s: %s", group_name, value)
        )
      end
    elseif value:sub(1, 1) == "#" then
      -- Bare hex color - use type_ to determine attribute (defaults to fg)
      local hl_opts = {}
      hl_opts[type_ or "fg"] = value
      set_highlight(group_name, hl_opts, type_)
    elseif type_ then
      -- Highlight group name with specific attribute requested (e.g., for line highlights)
      -- Extract only the specified attribute to avoid overriding other highlights
      local color = get_hl_color(value, type_)
      if not color then
        -- Group doesn't have the attribute - use default color (tries Normal first, then config defaults)
        color = get_default_color(type_)
      end
      local hl_opts = {}
      hl_opts[type_] = color
      set_highlight(group_name, hl_opts, type_)
    else
      -- Assume it's a highlight group name to link
      set_highlight(group_name, { link = value }, type_)
    end
  else
    log.error(string.format("set_highlight(): Invalid value type for group %s: %s", group_name, type(value)))
  end
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
  for _, role in ipairs(role_groups) do
    local fg = get_hl_color(role.source, "fg") or get_default_color("fg")
    ---@type vim.api.keyset.highlight
    local hl_opts = {}
    for style in syntax_config.role_style:gmatch("[^,]+") do
      hl_opts[vim.trim(style)] = true
    end
    hl_opts.fg = fg
    hl_opts.default = true
    vim.api.nvim_set_hl(0, role.target, hl_opts)
  end

  -- Set ruler highlight group
  set_highlight("FlemmaRuler", syntax_config.ruler.hl)

  -- Set per-role ruler highlights (ruler fg + role line highlight bg) for adopt_line_highlight
  if
    syntax_config.ruler.adopt_line_highlight
    and syntax_config.line_highlights
    and syntax_config.line_highlights.enabled
  then
    local ruler_fg = get_hl_color("FlemmaRuler", "fg") or get_default_color("fg")
    local ruler_roles = { "frontmatter", "user", "system", "assistant" }
    for _, role in ipairs(ruler_roles) do
      local line_hl_group = "FlemmaLine" .. roles.capitalize(role)
      local role_bg = get_hl_color(line_hl_group, "bg")
      local ruler_role_group = "FlemmaRuler" .. roles.capitalize(role)
      if role_bg then
        vim.api.nvim_set_hl(0, ruler_role_group, { fg = ruler_fg, bg = role_bg, default = true })
      else
        vim.api.nvim_set_hl(0, ruler_role_group, { link = "FlemmaRuler", default = true })
      end
    end
  end

  -- Set highlight for thinking tags and blocks
  set_highlight("FlemmaThinkingTag", syntax_config.highlights.thinking_tag)
  set_highlight("FlemmaThinkingBlock", syntax_config.highlights.thinking_block)

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
  -- Blend: Normal bg → mix 30% StatusLine bg → mix 20% DiffChange fg
  local normal_bg_hex = get_hl_color("Normal", "bg")
  local normal_fg_hex = get_hl_color("Normal", "fg")
  local statusline_bg_hex = get_hl_color("StatusLine", "bg")
  local diffchange_fg_hex = get_hl_color("DiffChange", "fg")

  local bar_bg_rgb
  local normal_bg_rgb = normal_bg_hex and hex_to_rgb(normal_bg_hex)
  if normal_bg_rgb then
    bar_bg_rgb = normal_bg_rgb
    local statusline_bg_rgb = statusline_bg_hex and hex_to_rgb(statusline_bg_hex)
    if statusline_bg_rgb then
      bar_bg_rgb = mix_colors(bar_bg_rgb, statusline_bg_rgb, 0.3)
    end
    local diffchange_fg_rgb = diffchange_fg_hex and hex_to_rgb(diffchange_fg_hex)
    if diffchange_fg_rgb then
      bar_bg_rgb = mix_colors(bar_bg_rgb, diffchange_fg_rgb, 0.2)
    end
    vim.api.nvim_set_hl(
      0,
      "FlemmaNotificationsBar",
      { bg = rgb_to_hex(bar_bg_rgb), fg = normal_fg_hex, default = true }
    )
  else
    vim.api.nvim_set_hl(0, "FlemmaNotificationsBar", { link = "StatusLine", default = true })
  end

  -- Derive border underline color from bar bg — shift to create visible contrast
  local border_sp
  if bar_bg_rgb then
    local is_dark = (bar_bg_rgb.r + bar_bg_rgb.g + bar_bg_rgb.b) < 384
    local shift = { r = 30, g = 30, b = 30 }
    local adjusted = blend_colors(bar_bg_rgb, shift, is_dark and "+" or "-")
    border_sp = tonumber(rgb_to_hex(adjusted):gsub("^#", ""), 16)
  end
  if not border_sp and normal_bg_hex then
    local fallback_bg_rgb = hex_to_rgb(normal_bg_hex)
    if fallback_bg_rgb then
      local is_dark = (fallback_bg_rgb.r + fallback_bg_rgb.g + fallback_bg_rgb.b) < 384
      local shift = { r = 40, g = 40, b = 40 }
      local adjusted = blend_colors(fallback_bg_rgb, shift, is_dark and "+" or "-")
      border_sp = tonumber(rgb_to_hex(adjusted):gsub("^#", ""), 16)
    end
  end
  if not border_sp then
    local fallback = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
    border_sp = fallback.fg
  end
  vim.api.nvim_set_hl(0, "FlemmaNotificationsBottom", { underline = true, sp = border_sp, default = true })
  vim.api.nvim_set_hl(0, "FlemmaNotificationsModel", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "FlemmaNotificationsProvider", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "FlemmaNotificationsSeparator", { fg = border_sp, default = true })
  vim.api.nvim_set_hl(0, "FlemmaNotificationsCost", { bold = true, default = true })
  vim.api.nvim_set_hl(0, "FlemmaNotificationsLabel", { link = "Type", default = true })
  vim.api.nvim_set_hl(0, "FlemmaNotificationsCacheGood", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "FlemmaNotificationsCacheBad", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "FlemmaNotificationsTokens", { link = "Comment", default = true })
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
