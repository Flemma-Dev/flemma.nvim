--- Usage cost formatting for Flemma plugin
--- Centralizes cost display and notification logic

local M = {}

-- Format usage information for notification display
function M.format_notification(current, session)
  local state = require("flemma.state")
  local pricing = require("flemma.pricing")
  local usage_lines = {}

  -- Request usage
  if
    current
    and (
      current.input_tokens > 0
      or current.output_tokens > 0
      or (current.thoughts_tokens and current.thoughts_tokens > 0)
    )
  then
    local config = state.get_config()
    local total_output_tokens_for_cost = (current.output_tokens or 0) + (current.thoughts_tokens or 0)
    local current_cost = config.pricing.enabled
      and pricing.calculate_cost(config.model, current.input_tokens, total_output_tokens_for_cost)
    table.insert(usage_lines, "Request:")
    -- Add model and provider information
    table.insert(usage_lines, string.format("  Model:  `%s` (%s)", config.model, config.provider))
    if current_cost then
      table.insert(
        usage_lines,
        string.format("  Input:  %d tokens / $%.2f", current.input_tokens or 0, current_cost.input)
      )
      local display_output_tokens = (current.output_tokens or 0) + (current.thoughts_tokens or 0)
      local output_display_string
      if current.thoughts_tokens and current.thoughts_tokens > 0 then
        output_display_string = string.format(
          " Output:  %d tokens (⊂ %d thoughts) / $%.2f",
          display_output_tokens,
          current.thoughts_tokens,
          current_cost.output
        )
      else
        output_display_string = string.format(" Output:  %d tokens / $%.2f", display_output_tokens, current_cost.output)
      end
      table.insert(usage_lines, output_display_string)
      table.insert(usage_lines, string.format("  Total:  $%.2f", current_cost.total))
    else
      table.insert(usage_lines, string.format("  Input:  %d tokens", current.input_tokens or 0))
      local display_output_tokens = (current.output_tokens or 0) + (current.thoughts_tokens or 0)
      local output_display_string
      if current.thoughts_tokens and current.thoughts_tokens > 0 then
        output_display_string =
          string.format(" Output:  %d tokens (⊂ %d thoughts)", display_output_tokens, current.thoughts_tokens)
      else
        output_display_string = string.format(" Output:  %d tokens", display_output_tokens)
      end
      table.insert(usage_lines, output_display_string)
    end
  end

  -- Session totals
  if session and (session.input_tokens > 0 or session.output_tokens > 0) then
    local config = state.get_config()
    local total_session_output_tokens_for_cost = (session.output_tokens or 0) + (session.thoughts_tokens or 0)
    local session_cost = config.pricing.enabled
      and pricing.calculate_cost(config.model, session.input_tokens, total_session_output_tokens_for_cost)
    if #usage_lines > 0 then
      table.insert(usage_lines, "")
    end
    table.insert(usage_lines, "Session:")
    if session_cost then
      table.insert(
        usage_lines,
        string.format("  Input:  %d tokens / $%.2f", session.input_tokens or 0, session_cost.input)
      )
      local display_session_output_tokens = (session.output_tokens or 0) + (session.thoughts_tokens or 0)
      table.insert(
        usage_lines,
        string.format(" Output:  %d tokens / $%.2f", display_session_output_tokens, session_cost.output)
      )
      table.insert(usage_lines, string.format("  Total:  $%.2f", session_cost.total))
    else
      table.insert(usage_lines, string.format("  Input:  %d tokens", session.input_tokens or 0))
      local display_session_output_tokens = (session.output_tokens or 0) + (session.thoughts_tokens or 0)
      table.insert(usage_lines, string.format(" Output:  %d tokens", display_session_output_tokens))
    end
  end
  return table.concat(usage_lines, "\n")
end

return M
