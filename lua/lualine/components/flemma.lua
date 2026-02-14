--- Lualine component for Flemma model display
local lualine_component = require("lualine.component")
local state = require("flemma.state")
local registry = require("flemma.provider.registry")

-- Create a new component for displaying the Flemma model
local flemma_model_component = lualine_component:extend()

---Get the current thinking/reasoning level (unified across providers).
---Reads from the provider's parameter proxy which includes frontmatter overrides.
---@return string|nil level "low"|"medium"|"high" or nil if thinking is not active
local function get_current_thinking_level()
  local current_config = state.get_config()
  if not current_config or not current_config.provider then
    return nil
  end

  local capabilities = registry.get_capabilities(current_config.provider)
  if not capabilities then
    return nil
  end

  -- For effort-based providers (OpenAI), check per-model reasoning support
  if capabilities.supports_reasoning and current_config.model then
    local models = require("flemma.models")
    local model_info = models.providers[current_config.provider]
      and models.providers[current_config.provider].models
      and models.providers[current_config.provider].models[current_config.model]
    if not model_info or not model_info.supports_reasoning_effort then
      return nil
    end
  end

  -- Read from the provider's parameter proxy (includes frontmatter overrides)
  local provider = state.get_provider()
  local params = provider and provider.parameters or current_config.parameters
  if not params then
    return nil
  end

  local base = require("flemma.provider.base")
  local thinking = base.resolve_thinking(params --[[@as flemma.provider.Parameters]], capabilities)
  if not thinking.enabled then
    return nil
  end

  return thinking.level
end

---Updates the status of the component.
---Called by lualine to get the text to display.
---@return string
function flemma_model_component:update_status()
  -- Only show the model if the filetype is 'chat'
  if vim.bo.filetype == "chat" then
    local flemma_ok, flemma = pcall(require, "flemma")
    if flemma_ok and flemma then
      local model_name = flemma.get_current_model_name and flemma.get_current_model_name()
      if not model_name or model_name == "" then
        return "" -- No model, show nothing
      end

      -- Get format string from config
      local full_config = state.get_config() or {}
      local statusline_config = full_config.statusline or {}
      local thinking_format = statusline_config.thinking_format or "{model} ({level})"

      local level = get_current_thinking_level()
      if level then
        local result = thinking_format:gsub("{model}", model_name):gsub("{level}", level)
        return result
      end

      return model_name
    end
    return "" -- Fallback if flemma module is not available
  end
  return "" -- Return empty string if not a 'chat' buffer
end

return flemma_model_component -- Return the component instance directly
