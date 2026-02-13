--- Calculator tool definition
--- Provides basic arithmetic calculation capability
---@class flemma.tools.definitions.Calculator
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

M.definitions = {
  {
    name = "calculator",
    description = "Evaluates a mathematical expression and returns the numeric result. "
      .. "Use this for any arithmetic calculations including addition, subtraction, "
      .. "multiplication, division, exponents, and common math functions.",
    strict = true,
    input_schema = {
      type = "object",
      properties = {
        expression = {
          type = "string",
          description = "The mathematical expression to evaluate (e.g., '2 + 2', '15 * 7', 'sqrt(16)', '2^10')",
        },
      },
      required = { "expression" },
      additionalProperties = false,
    },
    output_schema = {
      type = "object",
      properties = {
        result = {
          type = "number",
          description = "The numeric result of the calculation",
        },
      },
      required = { "result" },
    },
    async = false,
    execute = function(input)
      local expr = input.expression
      if not expr or expr == "" then
        return { success = false, error = "No expression provided" }
      end
      local fn, err = load("return " .. expr, "calc", "t", { math = math })
      if not fn then
        return { success = false, error = "Invalid expression: " .. err }
      end
      local ok, result = pcall(fn)
      if not ok then
        return { success = false, error = "Evaluation failed: " .. result }
      end
      return { success = true, output = tostring(result) }
    end,
  },
  {
    name = "calculator_async",
    enabled = false,
    description = "Evaluates a mathematical expression asynchronously and returns the numeric result. "
      .. "Use this for any arithmetic calculations including addition, subtraction, "
      .. "multiplication, division, exponents, and common math functions.",
    strict = true,
    input_schema = {
      type = "object",
      properties = {
        expression = {
          type = "string",
          description = "The mathematical expression to evaluate (e.g., '2 + 2', '15 * 7', 'sqrt(16)', '2^10')",
        },
        delay = {
          type = { "number", "null" },
          description = "Delay in milliseconds before returning the result (default: 1000)",
        },
      },
      required = { "expression", "delay" },
      additionalProperties = false,
    },
    output_schema = {
      type = "object",
      properties = {
        result = {
          type = "number",
          description = "The numeric result of the calculation",
        },
      },
      required = { "result" },
    },
    async = true,
    execute = function(input, callback)
      local expr = input.expression
      if not expr or expr == "" then
        callback({ success = false, error = "No expression provided" })
        return
      end
      local fn, err = load("return " .. expr, "calc", "t", { math = math })
      if not fn then
        callback({ success = false, error = "Invalid expression: " .. err })
        return
      end
      local ok, result = pcall(fn)
      if not ok then
        callback({ success = false, error = "Evaluation failed: " .. result })
        return
      end
      local delay = input.delay or 1000
      local timer = vim.uv.new_timer()
      if not timer then
        callback({ success = true, output = tostring(result) })
        return nil
      end
      timer:start(delay, 0, function()
        timer:stop()
        timer:close()
        callback({ success = true, output = tostring(result) })
      end)
      return function()
        timer:stop()
        timer:close()
      end
    end,
  },
}

return M
