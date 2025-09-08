--- Lualine component for Flemma model display
local lualine_component = require("lualine.component")

-- Create a new component for displaying the Flemma model
local flemma_model_component = lualine_component:extend()

-- Get the current reasoning setting if applicable for OpenAI
local function get_current_reasoning_setting()
  local state_ok, state = pcall(require, "flemma.state")
  if not state_ok or not state then
    return nil
  end

  local current_config = state.get_config()
  if
    current_config
    and current_config.provider == "openai"
    and current_config.parameters
    and current_config.parameters.reasoning
  then
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

      local provider_name = flemma.get_current_provider_name and flemma.get_current_provider_name()
      local reasoning_setting = get_current_reasoning_setting()

      if
        provider_name == "openai"
        and model_name:sub(1, 1) == "o"
        and reasoning_setting -- This will be "low", "medium", or "high" if valid
      then
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
