--- Lualine component for Flemma status display with tmux-style format strings.
---
--- Uses lazy-evaluated variable resolvers — only variables referenced by the
--- format string trigger data lookups.  Variables are cached per render cycle.
local lualine_component = require("lualine.component")
local config_facade = require("flemma.config")
local normalize = require("flemma.provider.normalize")
local prefetch = require("flemma.usage.prefetch")
local registry = require("flemma.provider.registry")
local format = require("flemma.utilities.format")
local session = require("flemma.session")
local str = require("flemma.utilities.string")
local tools = require("flemma.tools")

-- Create a new component for displaying Flemma status
local flemma_component = lualine_component:extend()

---@param options table Lualine component options
function flemma_component:init(options)
  lualine_component.init(self, options)

  local group = vim.api.nvim_create_augroup("FlemmaLualineIntegration", { clear = true })

  local function refresh_lualine()
    local ok, lualine = pcall(require, "lualine")
    if ok then
      lualine.refresh()
    end
  end

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "FlemmaBootComplete", "FlemmaConfigUpdated", "FlemmaUsageEstimated" },
    callback = refresh_lualine,
  })
end

---Resolve the current thinking/reasoning level (unified across providers).
---Reads from the provider's parameter proxy which includes frontmatter overrides.
---@param config flemma.Config
---@return string level "low"|"medium"|"high" or "" if thinking is not active
local function resolve_thinking(config)
  local capabilities = registry.get_capabilities(config.provider)
  if not capabilities then
    return ""
  end

  -- For effort-based providers (OpenAI), check per-model reasoning support
  -- via meta.reasoning_effort on the model info.
  if capabilities.supports_reasoning and config.model then
    local model_info = registry.get_model_info(config.provider, config.model)
    if not model_info or not (model_info.meta and model_info.meta.reasoning_effort) then
      return ""
    end
  end

  -- Flatten provider-specific + general params for resolve_thinking()
  local params = normalize.flatten_parameters(config.provider, config)
  if not params then
    return ""
  end

  local thinking = normalize.resolve_thinking(params --[[@as flemma.provider.Parameters]], capabilities)
  if not thinking.enabled then
    return ""
  end

  return thinking.level or ""
end

---Build resolver functions that close over a single config snapshot.
---@param config flemma.Config
---@return table<string, fun(): string>
local function make_resolvers(config)
  return {
    -- Boot state
    booting = function()
      return tools.is_ready() and "" or "1"
    end,

    -- Identity
    model = function()
      return config.model or ""
    end,
    provider = function()
      return config.provider or ""
    end,
    thinking = function()
      return resolve_thinking(config)
    end,

    -- Session totals
    ["session.cost"] = function()
      local s = session.get()
      local total = s:get_total_cost()
      return total > 0 and str.format_money(total) or ""
    end,
    ["session.requests"] = function()
      local s = session.get()
      local count = s:get_request_count()
      return count > 0 and tostring(count) or ""
    end,
    ["session.tokens.input"] = function()
      local s = session.get()
      local total = s:get_total_input_tokens()
      return total > 0 and str.format_tokens(total) or ""
    end,
    ["session.tokens.output"] = function()
      local s = session.get()
      local total = s:get_total_output_tokens()
      return total > 0 and str.format_tokens(total) or ""
    end,

    -- Last request
    ["last.cost"] = function()
      local s = session.get()
      local request = s:get_latest_request()
      if not request then
        return ""
      end
      local total = request:get_total_cost()
      return total > 0 and str.format_money(total) or ""
    end,
    ["last.tokens.input"] = function()
      local s = session.get()
      local request = s:get_latest_request()
      if not request then
        return ""
      end
      return request.input_tokens > 0 and str.format_tokens(request.input_tokens) or ""
    end,
    ["last.tokens.output"] = function()
      local s = session.get()
      local request = s:get_latest_request()
      if not request then
        return ""
      end
      local total = request:get_total_output_tokens()
      return total > 0 and str.format_tokens(total) or ""
    end,

    -- Buffer estimate
    ["buffer.tokens.input"] = function()
      local bufnr = vim.api.nvim_get_current_buf()
      prefetch.start_tracking(bufnr)
      local n = prefetch.get_tokens(bufnr)
      return n and str.format_number(n) or ""
    end,
  }
end

---Build a lazy variable table for a single render cycle.
---Variables are resolved on first access and cached for the remainder of the cycle.
---@param config flemma.Config
---@return table
local function build_vars(config)
  local resolvers = make_resolvers(config)
  return setmetatable({}, {
    __index = function(self, key)
      local resolver = resolvers[key]
      if not resolver then
        return ""
      end
      local value = resolver()
      rawset(self, key, value)
      return value
    end,
  })
end

---Updates the status of the component.
---Called by lualine to get the text to display.
---@return string
function flemma_component:update_status()
  if vim.bo.filetype ~= "chat" then
    return ""
  end

  -- materialize(bufnr) returns a plain table with per-buffer resolution —
  -- required because flatten_parameters uses pairs() and make_resolvers
  -- accesses dynamic keys. bufnr ensures frontmatter overrides are visible.
  local bufnr = vim.api.nvim_get_current_buf()
  local config = normalize.resolve_preset(config_facade.materialize(bufnr))
  if not config or not config.model or config.model == "" then
    return ""
  end

  local fmt = (self.options and self.options.format) or config.statusline.format
  if type(fmt) == "table" then
    fmt = table.concat(fmt, "")
  end

  local status = format.expand(fmt, build_vars(config))

  -- When rendered via lualine, rewrite escapes so they anchor to the active
  -- section hl (which differs from StatusLine when lualine tints sections):
  --
  --   %*                       → section's default hl (restores section tint)
  --   %#FlemmaStatusTextMuted# → %#FlemmaStatusTextMuted2#, a render-time
  --                              group combining the section's bg with
  --                              FlemmaStatusTextMuted's fg, so embedded
  --                              muted text keeps bg continuity
  --
  -- Outside lualine, `self.get_default_hl` is absent and both escapes pass
  -- through: vim handles `%*` natively and the static FlemmaStatusTextMuted
  -- group (anchored to StatusLine.bg) is used directly.
  if self.get_default_hl then
    local default_hl = self:get_default_hl()
    if default_hl and default_hl ~= "" then
      status = status:gsub("%%%*", function()
        return default_hl
      end)

      -- The FlemmaStatusTextMuted → FlemmaStatusTextMuted2 rewrite is the only
      -- reason we parse default_hl and touch the hl API here. Short-circuit
      -- when the escape isn't in the format so redraws pay nothing for it.
      if status:find("%#FlemmaStatusTextMuted#", 1, true) then
        -- default_hl is always a lualine section escape — "%#lualine_c_normal#",
        -- "%#lualine_x_insert#", etc. Anchoring to the lualine_ prefix both
        -- self-documents the intent and lets unexpected shapes fall through to
        -- the no-op path instead of feeding a garbage name to nvim_get_hl.
        local section_group = default_hl:match("^%%#(lualine_[%w_]+)#$")
        if section_group then
          local section_hl = vim.api.nvim_get_hl(0, { name = section_group, link = false })
          local muted_hl = vim.api.nvim_get_hl(0, { name = "FlemmaStatusTextMuted", link = false })
          if section_hl and section_hl.bg and muted_hl and muted_hl.fg then
            -- Lualine redraws the statusline on every CursorMoved / ModeChanged
            -- etc., so update_status runs frequently. Skip nvim_set_hl unless the
            -- inputs have actually changed (only on mode switch or colorscheme).
            if self._muted_section_bg ~= section_hl.bg or self._muted_fg ~= muted_hl.fg then
              vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted2", {
                bg = section_hl.bg,
                fg = muted_hl.fg,
              })
              self._muted_section_bg = section_hl.bg
              self._muted_fg = muted_hl.fg
            end
            status = status:gsub("%%#FlemmaStatusTextMuted#", function()
              return "%#FlemmaStatusTextMuted2#"
            end)
          end
        end
      end
    end
  end

  return status
end

return flemma_component
