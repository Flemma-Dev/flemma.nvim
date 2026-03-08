--- Lualine component for Flemma status display with tmux-style format strings.
---
--- Uses lazy-evaluated variable resolvers — only variables referenced by the
--- format string trigger data lookups.  Variables are cached per render cycle.
local lualine_component = require("lualine.component")
local state = require("flemma.state")
local registry = require("flemma.provider.registry")
local format = require("flemma.utilities.format")
local session = require("flemma.session")

--- Default format: model name, with thinking level in parens when active.
local DEFAULT_FORMAT = "#{model}#{?#{thinking}, (#{thinking}),}"

-- Create a new component for displaying Flemma status
local flemma_component = lualine_component:extend()

---Format a cost value as a dollar string.
---Uses 4 decimal places for sub-cent values, 2 otherwise.
---@param cost number Cost in USD
---@return string
local function format_cost(cost)
  if cost < 0.01 and cost > 0 then
    return string.format("$%.4f", cost)
  end
  return string.format("$%.2f", cost)
end

---Format a token count as a compact string (e.g. 1500 → "1.5K", 2000000 → "2M").
---@param tokens number
---@return string
local function format_tokens(tokens)
  if tokens >= 1000000 then
    local m = tokens / 1000000
    if m == math.floor(m) then
      return string.format("%dM", m)
    end
    return string.format("%.1fM", m)
  elseif tokens >= 1000 then
    local k = tokens / 1000
    if k == math.floor(k) then
      return string.format("%dK", k)
    end
    return string.format("%.1fK", k)
  end
  return tostring(tokens)
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

  -- Read from the provider's parameter proxy (includes frontmatter overrides)
  local provider = state.get_provider()
  local params = provider and provider.parameters or config.parameters
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
      return total > 0 and format_cost(total) or ""
    end,
    ["session.requests"] = function()
      local s = session.get()
      local count = s:get_request_count()
      return count > 0 and tostring(count) or ""
    end,
    ["session.tokens.input"] = function()
      local s = session.get()
      local total = s:get_total_input_tokens()
      return total > 0 and format_tokens(total) or ""
    end,
    ["session.tokens.output"] = function()
      local s = session.get()
      local total = s:get_total_output_tokens()
      return total > 0 and format_tokens(total) or ""
    end,

    -- Last request
    ["last.cost"] = function()
      local s = session.get()
      local request = s:get_latest_request()
      if not request then
        return ""
      end
      local total = request:get_total_cost()
      return total > 0 and format_cost(total) or ""
    end,
    ["last.tokens.input"] = function()
      local s = session.get()
      local request = s:get_latest_request()
      if not request then
        return ""
      end
      return request.input_tokens > 0 and format_tokens(request.input_tokens) or ""
    end,
    ["last.tokens.output"] = function()
      local s = session.get()
      local request = s:get_latest_request()
      if not request then
        return ""
      end
      local total = request:get_total_output_tokens()
      return total > 0 and format_tokens(total) or ""
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

  local config = state.get_config()
  if not config or not config.model or config.model == "" then
    return ""
  end

  local statusline_config = config.statusline or {}
  local fmt = statusline_config.format or DEFAULT_FORMAT

  return format.expand(fmt, build_vars(config))
end

return flemma_component
