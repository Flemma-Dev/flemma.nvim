--- Claudius pricing functionality
local M = {}

-- Load models from centralized models.lua
local models_data = require("claudius.models")

-- Get all models with pricing (extract from data-only models.lua)
local function get_all_models_with_pricing()
  local all_models = {}

  for provider_name, provider in pairs(models_data.providers) do
    for model_name, model in pairs(provider.models) do
      if model.pricing then
        all_models[model_name] = model.pricing
      end
    end
  end

  return all_models
end

-- Get pricing information for models (USD per million tokens) - cached for performance
M.models = get_all_models_with_pricing()

-- Find the closest matching model name
local function find_matching_model(model_name)
  -- Try exact match first
  if M.models[model_name] then
    return model_name
  end

  -- Split the model name by both - and . delimiters
  local parts = {}
  for part in model_name:gmatch("[^-%.]+") do
    table.insert(parts, part)
  end

  -- Try progressively shorter combinations from the start
  local current = parts[1] -- Start with "claude"
  for i = 2, #parts do
    current = current .. "-" .. parts[i]
    if M.models[current] then
      return current
    end
  end

  return nil
end

-- Calculate cost for tokens
function M.calculate_cost(model, input_tokens, output_tokens)
  local matching_model = find_matching_model(model)
  if not matching_model then
    return nil
  end

  local pricing = M.models[matching_model]

  -- Calculate costs (per million tokens)
  local input_cost = (input_tokens / 1000000) * pricing.input
  local output_cost = (output_tokens / 1000000) * pricing.output

  -- Round to 2 decimal places
  return {
    input = math.ceil(input_cost * 100) / 100,
    output = math.ceil(output_cost * 100) / 100,
    total = math.ceil((input_cost + output_cost) * 100) / 100,
  }
end

return M
