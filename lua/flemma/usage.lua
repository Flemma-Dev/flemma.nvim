--- Usage and pricing functionality for Flemma plugin
--- Centralizes notification display for request and session costs

---@class flemma.Usage
local M = {}

---Format usage information for notification display
---@param request? flemma.session.Request Most recent completed request
---@param session? flemma.session.Session Session instance
---@return string
function M.format_notification(request, session)
  local state = require("flemma.state")
  local usage_lines = {}

  -- Request usage (most recent request)
  if request then
    local total_output_tokens = request:get_total_output_tokens()

    local config = state.get_config()
    local pricing_enabled = config.pricing.enabled

    table.insert(usage_lines, "Request:")
    -- Use model and provider from the request's own snapshot
    table.insert(usage_lines, string.format("  Model:  `%s` (%s)", request.model, request.provider))

    if pricing_enabled then
      table.insert(
        usage_lines,
        string.format("  Input:  %d tokens / $%.2f", request.input_tokens, request:get_input_cost())
      )
      -- Show cache line when tokens > 0
      if request.cache_read_input_tokens > 0 or request.cache_creation_input_tokens > 0 then
        table.insert(
          usage_lines,
          string.format(
            "  Cache:  %d read + %d write",
            request.cache_read_input_tokens,
            request.cache_creation_input_tokens
          )
        )
      end
      local output_display_string
      if request.thoughts_tokens > 0 then
        output_display_string = string.format(
          " Output:  %d tokens (⊂ %d thoughts) / $%.2f",
          total_output_tokens,
          request.thoughts_tokens,
          request:get_output_cost()
        )
      else
        output_display_string =
          string.format(" Output:  %d tokens / $%.2f", total_output_tokens, request:get_output_cost())
      end
      table.insert(usage_lines, output_display_string)
      table.insert(usage_lines, string.format("  Total:  $%.2f", request:get_total_cost()))
    else
      table.insert(usage_lines, string.format("  Input:  %d tokens", request.input_tokens))
      if request.cache_read_input_tokens > 0 or request.cache_creation_input_tokens > 0 then
        table.insert(
          usage_lines,
          string.format(
            "  Cache:  %d read + %d write",
            request.cache_read_input_tokens,
            request.cache_creation_input_tokens
          )
        )
      end
      local output_display_string
      if request.thoughts_tokens > 0 then
        output_display_string =
          string.format(" Output:  %d tokens (⊂ %d thoughts)", total_output_tokens, request.thoughts_tokens)
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
