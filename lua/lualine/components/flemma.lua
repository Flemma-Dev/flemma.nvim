--- Lualine component for Flemma model display
local lualine_component = require("lualine.component")
local state = require("flemma.state")
local registry = require("flemma.provider.registry")
local models = require("flemma.models")

-- Create a new component for displaying the Flemma model
local flemma_model_component = lualine_component:extend()

-- Get the current reasoning setting if the provider and model support it
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

--- Updates the status of the component.
-- This function is called by lualine to get the text to display.
function flemma_model_component:update_status()
  -- Only show the model if the filetype is 'chat'
  if vim.bo.filetype == "chat" then
    local flemma_ok, flemma = pcall(require, "flemma")
    if flemma_ok and flemma then
      local model_name = flemma.get_current_model_name and flemma.get_current_model_name()
      if not model_name or model_name == "" then
        return "" -- No model, show nothing
      end

      local reasoning_setting = get_current_reasoning_setting()

      if reasoning_setting then
        return string.format("%s (%s)", model_name, reasoning_setting)
      else
        return model_name
      end
    end
    return "" -- Fallback if flemma module is not available
  end
  return "" -- Return empty string if not a 'chat' buffer
end

return flemma_model_component -- Return the component instance directly
