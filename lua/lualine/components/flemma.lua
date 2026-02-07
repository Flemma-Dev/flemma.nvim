--- Lualine component for Flemma model display
local lualine_component = require("lualine.component")
local state = require("flemma.state")
local registry = require("flemma.provider.registry")
local models = require("flemma.models")

-- Create a new component for displaying the Flemma model
local flemma_model_component = lualine_component:extend()

---Get the current reasoning setting if the provider and model support it
---@return string|nil reasoning "low"|"medium"|"high" or nil
local function get_current_reasoning_setting()
  local current_config = state.get_config()
  if not current_config or not current_config.provider or not current_config.model then
    return nil
  end

  -- Check if provider supports reasoning via registry
  local capabilities = registry.get_capabilities(current_config.provider)
  if not capabilities or not capabilities.supports_reasoning then
    return nil
  end

  -- Check if the specific model supports reasoning
  local model_info = models.providers[current_config.provider]
    and models.providers[current_config.provider].models
    and models.providers[current_config.provider].models[current_config.model]

  if not model_info or not model_info.supports_reasoning_effort then
    return nil
  end

  -- If both provider and model support reasoning, check if it's configured
  if current_config.parameters and current_config.parameters.reasoning then
    local reasoning = current_config.parameters.reasoning
    if reasoning == "low" or reasoning == "medium" or reasoning == "high" then
      return reasoning
    end
  end

  return nil
end

---Get the current thinking budget setting if the provider supports it
---@return number|nil budget
local function get_current_thinking_budget()
  local current_config = state.get_config()
  if not current_config or not current_config.provider then
    return nil
  end

  -- Check if provider supports thinking budget via registry
  local capabilities = registry.get_capabilities(current_config.provider)
  if not capabilities or not capabilities.supports_thinking_budget then
    return nil
  end

  -- Check if thinking_budget is configured and meets minimum requirements
  if current_config.parameters and current_config.parameters.thinking_budget then
    local budget = current_config.parameters.thinking_budget
    if type(budget) ~= "number" then
      return nil
    end

    -- Provider-specific minimum budget requirements
    local provider = current_config.provider
    if provider == "anthropic" and budget >= 1024 then
      return budget
    elseif provider == "vertex" and budget >= 1 then
      return budget
    end
  end

  return nil
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

      -- Get format strings from config
      local full_config = state.get_config() or {}
      local statusline_config = full_config.statusline or {}
      local reasoning_format = statusline_config.reasoning_format or "{model} ({level})"
      local thinking_format = statusline_config.thinking_format or "{model}  ✓ thinking"

      -- Check for reasoning setting (OpenAI o-series)
      local reasoning_setting = get_current_reasoning_setting()
      if reasoning_setting then
        local result = reasoning_format:gsub("{model}", model_name):gsub("{level}", reasoning_setting)
        return result
      end

      -- Check for thinking budget (Anthropic, Vertex)
      local thinking_budget = get_current_thinking_budget()
      if thinking_budget then
        local result = thinking_format:gsub("{model}", model_name)
        return result
      end

      return model_name
    end
    return "" -- Fallback if flemma module is not available
  end
  return "" -- Return empty string if not a 'chat' buffer
end

return flemma_model_component -- Return the component instance directly
