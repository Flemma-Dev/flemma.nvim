--- Syntax rule generation and application for preprocessor rewriters.
--- Maps declarative SyntaxRule tables to Vim syntax commands and applies
--- highlight groups. Called by highlight.lua during apply_syntax().
---@class flemma.preprocessor.Syntax
local M = {}

local preprocessor = require("flemma.preprocessor")

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

--- Maps semantic role names to Vim syntax group names.
---@type table<string, string>
local REGION_MAP = {
  user = "FlemmaUser",
  system = "FlemmaSystem",
  assistant = "FlemmaAssistant",
}

--- All content region group names, comma-joined (used for "*" expansion).
---@type string
local ALL_CONTENT_REGIONS = "FlemmaUser,FlemmaSystem,FlemmaAssistant"

--------------------------------------------------------------------------------
-- Public helpers (exported for testing)
--------------------------------------------------------------------------------

--- Resolve a semantic containedin value to a comma-separated Vim syntax group string.
---@param containedin? string|string[]
---@return string
function M.resolve_containedin(containedin)
  if containedin == nil or containedin == "*" then
    return ALL_CONTENT_REGIONS
  end

  if type(containedin) == "string" then
    return REGION_MAP[containedin] or containedin
  end

  ---@cast containedin string[]
  local groups = {}
  for _, name in ipairs(containedin) do
    table.insert(groups, REGION_MAP[name] or name)
  end
  return table.concat(groups, ",")
end

--- Generate a Vim syntax command string from a declarative SyntaxRule.
---@param rule flemma.preprocessor.SyntaxRule
---@return string
function M.generate_command(rule)
  if rule.raw then
    return rule.raw
  end

  local resolved = M.resolve_containedin(rule.containedin)

  if rule.kind == "match" then
    local parts = { "syntax match", rule.group, string.format('"%s"', rule.pattern) }
    if rule.options then
      table.insert(parts, rule.options)
    end
    table.insert(parts, "contained")
    table.insert(parts, "containedin=" .. resolved)
    return table.concat(parts, " ")
  end

  if rule.kind == "region" then
    local parts = {
      "syntax region",
      rule.group,
      string.format('start="%s"', rule.start),
      string.format('end="%s"', rule.end_),
    }
    if rule.options then
      table.insert(parts, rule.options)
    end
    if rule.contains then
      table.insert(parts, "contains=" .. rule.contains)
    end
    table.insert(parts, "contained")
    table.insert(parts, "containedin=" .. resolved)
    return table.concat(parts, " ")
  end

  return ""
end

--------------------------------------------------------------------------------
-- Main entry point
--------------------------------------------------------------------------------

--- Apply syntax rules and highlights from all registered rewriters.
--- Iterates rewriters that define get_vim_syntax, generates Vim syntax commands,
--- and applies highlights via the provided set_highlight callback.
---@param config flemma.Config
---@param set_highlight fun(group_name: string, value: string|table)
function M.apply(config, set_highlight)
  local rewriters = preprocessor.get_all()

  for _, rewriter in ipairs(rewriters) do
    if type(rewriter.get_vim_syntax) == "function" then
      local rules = rewriter:get_vim_syntax(config)
      for _, rule in ipairs(rules) do
        local cmd = M.generate_command(rule)
        if cmd ~= "" then
          vim.cmd(cmd)
        end
        set_highlight(rule.group, rule.hl)
      end
    end
  end
end

return M
