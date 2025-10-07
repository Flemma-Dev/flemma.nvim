--- Language parsers for frontmatter
--- Each parser converts source code into a flat table of key-value pairs
local M = {}

-- Parser registry
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
  return parsers[language]
end

---Check if a parser exists for a language
---@param language string The language identifier
---@return boolean exists True if parser is registered
function M.has(language)
  return parsers[language] ~= nil
end

---Get list of supported languages
---@return string[] languages Array of supported language identifiers
function M.supported_languages()
  local languages = {}
  for language in pairs(parsers) do
    table.insert(languages, language)
  end
  table.sort(languages)
  return languages
end

return M
