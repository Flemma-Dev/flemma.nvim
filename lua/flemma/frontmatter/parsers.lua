--- Language parsers for frontmatter
--- Each parser converts source code into a flat table of key-value pairs
local M = {}

local parser_modules = {
  lua = "flemma.frontmatter.parsers.lua",
  json = "flemma.frontmatter.parsers.json",
}

local parsers = {}

---Register a parser for a specific language
---@param language string The language identifier (e.g., "lua", "json")
---@param parser_fn function Function that takes code string and returns table
function M.register(language, parser_fn)
  parsers[language] = parser_fn
end

---Get a parser for a specific language
---@param language string The language identifier
---@return function|nil parser_fn The parser function, or nil if not found
function M.get(language)
  if not parsers[language] then
    local module_path = parser_modules[language]
    if module_path then
      local parser_module = require(module_path)
      parsers[language] = parser_module.parse
    end
  end
  return parsers[language]
end

---Check if a parser exists for a language
---@param language string The language identifier
---@return boolean exists True if parser is registered
function M.has(language)
  return parser_modules[language] ~= nil or parsers[language] ~= nil
end

return M
