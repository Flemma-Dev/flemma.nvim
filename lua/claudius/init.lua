--- Compatibility layer for Claudius -> Flemma migration
--- This module provides backward compatibility for users still requiring "claudius"
---
--- @deprecated Use require("flemma") instead
local M = {}

-- Show deprecation warning on first use
local warning_shown = false

local function show_deprecation_warning()
  if not warning_shown then
    warning_shown = true
    vim.notify( ---@diagnostic disable-line: redundant-parameter
      "Claudius has been renamed to Flemma! Update your config to use require('flemma') instead of require('claudius').",
      vim.log.levels.WARN,
      {
        title = "Deprecated: Claudius → Flemma",
        timeout = 5000,
      }
    )
  end
end

-- Defer all functionality to the new flemma module
return setmetatable(M, {
  __index = function(_, key)
    show_deprecation_warning()
    local flemma = require("flemma")
    return flemma[key]
  end,
  __call = function(_, ...)
    show_deprecation_warning()
    local flemma = require("flemma")
    return flemma(...)
  end,
})
