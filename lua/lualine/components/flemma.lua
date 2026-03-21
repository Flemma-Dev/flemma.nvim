--- Lualine component for Flemma status display with tmux-style format strings.
---
--- Uses lazy-evaluated variable resolvers — only variables referenced by the
--- format string trigger data lookups.  Variables are cached per render cycle.
local lualine_component = require("lualine.component")
local config_facade = require("flemma.config")
local config_manager = require("flemma.core.config.manager")
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

  vim.api.nvim_create_autocmd("User", {
    pattern = "FlemmaBootComplete",
    callback = function()
      local ok, lualine = pcall(require, "lualine")
      if ok then
        lualine.refresh()
      end
    end,
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
  if capabilities.supports_reasoning and config.model then
    local models = require("flemma.models")
    local model_info = models.providers[config.provider]
      and models.providers[config.provider].models
      and models.providers[config.provider].models[config.model]
    if not model_info or not model_info.supports_reasoning_effort then
      return ""
    end
  end

  -- Flatten provider-specific + general params for resolve_thinking()
  local params = config_manager.flatten_provider_params(config.provider, config)
  if not params then
    return ""
  end

  local base = require("flemma.provider.base")
  local thinking = base.resolve_thinking(params --[[@as flemma.provider.Parameters]], capabilities)
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
      return total > 0 and str.format_cost(total) or ""
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
      return total > 0 and str.format_cost(total) or ""
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
  -- required because flatten_provider_params uses pairs() and make_resolvers
  -- accesses dynamic keys. bufnr ensures frontmatter overrides are visible.
  local bufnr = vim.api.nvim_get_current_buf()
  local config = config_facade.materialize(bufnr)
  if not config or not config.model or config.model == "" then
    return ""
  end

  local fmt = (self.options and self.options.format) or config.statusline.format

  return format.expand(fmt, build_vars(config))
end

return flemma_component
