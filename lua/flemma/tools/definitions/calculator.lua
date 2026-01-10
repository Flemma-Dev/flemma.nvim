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
}

return M
