--- Calculator tool definition
--- Provides basic arithmetic calculation capability
local M = {}

M.definition = {
  name = "calculator",
  description = "Evaluates a mathematical expression and returns the numeric result. "
    .. "Use this for any arithmetic calculations including addition, subtraction, "
    .. "multiplication, division, exponents, and common math functions.",
  input_schema = {
    type = "object",
    properties = {
      expression = {
        type = "string",
        description = "The mathematical expression to evaluate (e.g., '2 + 2', '15 * 7', 'sqrt(16)', '2^10')",
      },
    },
    required = { "expression" },
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
}

return M
