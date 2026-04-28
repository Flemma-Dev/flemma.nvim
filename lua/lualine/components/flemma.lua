--- Lualine component for Flemma status display with Lua template strings.
---
--- Uses lazy-evaluated variable resolvers — only variables referenced by the
--- format string trigger data lookups.  Variables are cached per render cycle.
local lualine_component = require("lualine.component")
local config_facade = require("flemma.config")
local normalize = require("flemma.provider.normalize")
local prefetch = require("flemma.usage.prefetch")
local readiness = require("flemma.readiness")
local registry = require("flemma.provider.registry")
local renderer = require("flemma.templating.renderer")
local session = require("flemma.session")
local templating = require("flemma.templating")
local tools = require("flemma.tools")

---@alias flemma.statusline.FormatFunction fun(env: table): string

-- Create a new component for displaying Flemma status
local flemma_component = lualine_component:extend()

---@type table<string, true>
local pending_refreshes = {}

---@type table<string, flemma.templating.RenderFunction>
local compiled_formats = {}

local function refresh_lualine()
  local ok, lualine = pcall(require, "lualine")
  if ok then
    lualine.refresh()
  end
end

---@param options table Lualine component options
function flemma_component:init(options)
  lualine_component.init(self, options)

  local group = vim.api.nvim_create_augroup("FlemmaLualineIntegration", { clear = true })

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

---@alias flemma.lualine.Resolver fun(): any
---@alias flemma.lualine.ResolverTree table<string, flemma.lualine.Resolver|flemma.lualine.ResolverTree>

---Return nil for zero-like statusline counters so Lua conditionals stay concise.
---@param value number
---@return number|nil
local function nonzero(value)
  return value > 0 and value or nil
end

---Build resolver functions that close over a single config snapshot.
---@param config flemma.Config
---@return flemma.lualine.ResolverTree
local function make_resolvers(config)
  local model_info_loaded = false
  local model_info = nil ---@type flemma.models.ModelInfo|nil
  local thinking_loaded = false
  local thinking_level = nil ---@type string|nil

  ---@return flemma.models.ModelInfo|nil
  local function get_model_info()
    if not model_info_loaded then
      model_info_loaded = true
      if config.provider and config.model then
        model_info = registry.get_model_info(config.provider, config.model)
      end
    end
    return model_info
  end

  ---@return string|nil
  local function get_thinking_level()
    if not thinking_loaded then
      thinking_loaded = true
      local level = resolve_thinking(config)
      thinking_level = level ~= "" and level or nil
    end
    return thinking_level
  end

  return {
    model = {
      name = function()
        return config.model
      end,
      max_input_tokens = function()
        local info = get_model_info()
        return info and info.max_input_tokens or nil
      end,
      max_output_tokens = function()
        local info = get_model_info()
        return info and info.max_output_tokens or nil
      end,
    },

    provider = {
      name = function()
        return config.provider
      end,
    },

    thinking = {
      enabled = function()
        return get_thinking_level() ~= nil
      end,
      level = function()
        return get_thinking_level()
      end,
    },

    session = {
      cost = function()
        return nonzero(session.get():get_total_cost())
      end,
      requests = function()
        return nonzero(session.get():get_request_count())
      end,
      tokens = {
        input = function()
          return nonzero(session.get():get_total_input_tokens())
        end,
        output = function()
          return nonzero(session.get():get_total_output_tokens())
        end,
      },
    },

    last = {
      cost = function()
        local request = session.get():get_latest_request()
        if not request then
          return nil
        end
        return nonzero(request:get_total_cost())
      end,
      tokens = {
        input = function()
          local request = session.get():get_latest_request()
          if not request then
            return nil
          end
          return nonzero(request.input_tokens)
        end,
        output = function()
          local request = session.get():get_latest_request()
          if not request then
            return nil
          end
          return nonzero(request:get_total_output_tokens())
        end,
      },
    },

    buffer = {
      tokens = {
        input = function()
          local bufnr = vim.api.nvim_get_current_buf()
          prefetch.start_tracking(bufnr)
          return prefetch.get_tokens(bufnr)
        end,
      },
    },
  }
end

---Build a lazy table node for a single render cycle.
---@param resolvers flemma.lualine.ResolverTree
---@return table
local function make_lazy_table(resolvers)
  local values = {}
  local resolved = {}

  return setmetatable({}, {
    __index = function(_, key)
      if type(key) ~= "string" then
        return nil
      end
      if resolved[key] then
        return values[key]
      end
      local resolver = resolvers[key]
      if resolver == nil then
        return nil
      end
      local value
      if type(resolver) == "function" then
        value = resolver()
      else
        value = make_lazy_table(resolver)
      end
      values[key] = value
      resolved[key] = true
      return value
    end,
  })
end

---Escape percent signs for Vim statusline context.
---@param text string
---@return string
local function escape_statusline_percent(text)
  return (text:gsub("%%", "%%%%"))
end

---Build a lazy variable table for a single render cycle.
---Variables are resolved on first access and cached for the remainder of the cycle.
---@param config flemma.Config
---@return table
local function build_env(config)
  local env = templating.create_env()
  local vars = make_lazy_table(make_resolvers(config))

  env.booting = not tools.is_ready()
  env.model = vars.model
  env.provider = vars.provider
  env.thinking = vars.thinking
  env.session = vars.session
  env.last = vars.last
  env.buffer = vars.buffer
  env.__expr_transform = escape_statusline_percent

  return env
end

---Trim incidental outer whitespace from multiline statusline templates.
---@param fmt string
---@return string
local function trim_statusline_format(fmt)
  return fmt:match("^%s*(.-)%s*$") or ""
end

---Render a statusline format string or function.
---@param fmt string|flemma.statusline.FormatFunction
---@param env table
---@return string
local function render_statusline_format(fmt, env)
  if type(fmt) == "function" then
    local ok, result = pcall(fmt, env)
    if not ok then
      if readiness.is_suspense(result) then
        error(result)
      end
      return ""
    end
    return result and tostring(result) or ""
  end

  if type(fmt) ~= "string" then
    return ""
  end

  fmt = trim_statusline_format(fmt)
  local render = compiled_formats[fmt]
  if not render then
    render = renderer.compile(fmt)
    compiled_formats[fmt] = render
  end
  return renderer.parts_to_text(render(env))
end

---@return string
function flemma_component:_do_update_status()
  -- materialize(bufnr) returns a plain table with per-buffer resolution —
  -- required because flatten_parameters uses pairs() and make_resolvers
  -- accesses dynamic keys. bufnr ensures frontmatter overrides are visible.
  local bufnr = vim.api.nvim_get_current_buf()
  local config = normalize.resolve_preset(config_facade.materialize(bufnr))
  if not config or not config.model or config.model == "" then
    return ""
  end

  local fmt = (self.options and self.options.format) or config.statusline.format
  local status = render_statusline_format(fmt, build_env(config))

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

---@return string
function flemma_component:update_status()
  if vim.bo.filetype ~= "chat" then
    return ""
  end

  local ok, result = pcall(self._do_update_status, self)
  if ok then
    return result
  end

  local err = result --[[@as any]]
  if readiness.is_suspense(err) then
    ---@cast err flemma.readiness.Suspense
    local key = err.boundary.key
    if not pending_refreshes[key] then
      pending_refreshes[key] = true
      err.boundary:subscribe(function(boundary_result)
        pending_refreshes[key] = nil
        if boundary_result and boundary_result.ok then
          refresh_lualine()
        end
      end)
    end
  end

  return ""
end

---@private
function flemma_component._reset_pending_refreshes()
  pending_refreshes = {}
end

---@private
function flemma_component._reset_compiled_formats()
  compiled_formats = {}
end

return flemma_component
