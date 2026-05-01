--- Formatting helpers for Flemma template environments.
---@class flemma.templating.builtins.Format : flemma.templating.Populator
---@field exports flemma.templating.builtins.format.Exports
local M = {}

local str = require("flemma.utilities.string")

M.name = "format"
M.priority = 150

---@class flemma.templating.builtins.format.Exports
local exports = {}

---Format a number with comma-separated thousands.
---@param value number
---@return string
function exports.number(value)
  return str.format_number(value)
end

---Format a token count for compact display.
---@param tokens number
---@return string
function exports.tokens(tokens)
  return str.format_tokens(tokens)
end

---Format a monetary value in USD with smart precision.
---@param amount number
---@return string
function exports.money(amount)
  return str.format_money(amount)
end

---Format a decimal ratio as a percentage string.
---For example, `format.percent(0.17, 1)` returns `"17.0%"`.
---@param ratio number
---@param decimals? integer
---@return string
function exports.percent(ratio, decimals)
  decimals = decimals or 0
  local pattern = "%." .. tostring(decimals) .. "f%%"
  return string.format(pattern, ratio * 100)
end

M.exports = exports

---Populate the environment with formatting helpers.
---@param env table
function M.populate(env)
  env.format = exports
end

return M
