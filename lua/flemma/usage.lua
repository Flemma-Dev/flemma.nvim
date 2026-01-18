--- Usage and pricing functionality for Flemma plugin
--- Centralizes cost calculation and notification display

local M = {}

-- Load models from centralized models.lua
local models_data = require("flemma.models")

-- Get all models with pricing (extract from data-only models.lua)
local function get_all_models_with_pricing()
  local all_models = {}

  for _, provider in pairs(models_data.providers) do
    for model_name, model in pairs(provider.models) do
      if model.pricing then
        all_models[model_name] = model.pricing
      end
    end
  end

  return all_models
end

-- Pricing information for models (USD per million tokens) - cached for performance
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
  local current = parts[1] -- Start with the first part (provider name)
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

-- Format usage information for notification display
function M.format_notification(current, session)
  local state = require("flemma.state")
  local usage_lines = {}

  -- Request usage (most recent request)
  if
    current
    and (
      current.input_tokens > 0
      or current.output_tokens > 0
      or (current.thoughts_tokens and current.thoughts_tokens > 0)
    )
  then
    local config = state.get_config()

    -- Get the flag from inflight_usage (set by the provider in core.lua)
    -- This tells us whether thoughts_tokens is already included in output_tokens
    local output_has_thoughts = current.output_has_thoughts or false

    -- Calculate total output tokens for cost/display
    local total_output_tokens
    if output_has_thoughts then
      -- Provider reports thoughts are already counted in output_tokens (e.g., OpenAI, Anthropic)
      total_output_tokens = current.output_tokens or 0
    else
      -- Provider reports thoughts are separate from output tokens (e.g., Vertex)
      total_output_tokens = (current.output_tokens or 0) + (current.thoughts_tokens or 0)
    end

    local current_cost = config.pricing.enabled
      and M.calculate_cost(config.model, current.input_tokens, total_output_tokens)
    table.insert(usage_lines, "Request:")
    -- Add model and provider information
    table.insert(usage_lines, string.format("  Model:  `%s` (%s)", config.model, config.provider))
    if current_cost then
      table.insert(
        usage_lines,
        string.format("  Input:  %d tokens / $%.2f", current.input_tokens or 0, current_cost.input)
      )
      local output_display_string
      if current.thoughts_tokens and current.thoughts_tokens > 0 then
        output_display_string = string.format(
          " Output:  %d tokens (⊂ %d thoughts) / $%.2f",
          total_output_tokens,
          current.thoughts_tokens,
          current_cost.output
        )
      else
        output_display_string = string.format(" Output:  %d tokens / $%.2f", total_output_tokens, current_cost.output)
      end
      table.insert(usage_lines, output_display_string)
      table.insert(usage_lines, string.format("  Total:  $%.2f", current_cost.total))
    else
      table.insert(usage_lines, string.format("  Input:  %d tokens", current.input_tokens or 0))
      local output_display_string
      if current.thoughts_tokens and current.thoughts_tokens > 0 then
        output_display_string =
          string.format(" Output:  %d tokens (⊂ %d thoughts)", total_output_tokens, current.thoughts_tokens)
      else
        output_display_string = string.format(" Output:  %d tokens", total_output_tokens)
      end
      table.insert(usage_lines, output_display_string)
    end
  end

  -- Session totals (calculated from all requests in session)
  if session and session:get_request_count() > 0 then
    local config = state.get_config()
    local total_input_tokens = session:get_total_input_tokens()
    local total_output_tokens = session:get_total_output_tokens()

    if #usage_lines > 0 then
      table.insert(usage_lines, "")
    end
    table.insert(usage_lines, "Session:")

    if config.pricing.enabled then
      -- Calculate total costs from all requests (each with their own pricing)
      local total_input_cost = session:get_total_input_cost()
      local total_output_cost = session:get_total_output_cost()
      local total_cost = session:get_total_cost()

      table.insert(
        usage_lines,
        string.format("  Input:  %d tokens / $%.2f", total_input_tokens, math.ceil(total_input_cost * 100) / 100)
      )
      table.insert(
        usage_lines,
        string.format(" Output:  %d tokens / $%.2f", total_output_tokens, math.ceil(total_output_cost * 100) / 100)
      )
      table.insert(usage_lines, string.format("  Total:  $%.2f", math.ceil(total_cost * 100) / 100))
    else
      table.insert(usage_lines, string.format("  Input:  %d tokens", total_input_tokens))
      table.insert(usage_lines, string.format(" Output:  %d tokens", total_output_tokens))
    end
  end
  return table.concat(usage_lines, "\n")
end

return M
