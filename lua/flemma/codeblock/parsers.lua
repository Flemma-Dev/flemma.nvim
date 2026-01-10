--- Generic language parsers for fenced code blocks
--- Shared by frontmatter, tool use input, and tool results
local M = {}

local parser_modules = {
  lua = "flemma.codeblock.parsers.lua",
  json = "flemma.codeblock.parsers.json",
}

local parsers = {}

---Register a parser for a specific language
---@param language string The language identifier (e.g., "lua", "json")
---@param parser_fn function Function that takes code string and optional context, returns parsed value
function M.register(language, parser_fn)
  parsers[language:lower()] = parser_fn
end

---Get a parser for a specific language (case-insensitive)
---@param language string The language identifier
---@return function|nil parser_fn The parser function, or nil if not found
function M.get(language)
  if not language then
    return nil
  end
  local lang_lower = language:lower()
  if not parsers[lang_lower] then
    local module_path = parser_modules[lang_lower]
    if module_path then
      local parser_module = require(module_path)
      parsers[lang_lower] = parser_module.parse
    end
  end
  return parsers[lang_lower]
end

---Check if a parser exists for a language
---@param language string The language identifier
---@return boolean exists True if parser is registered or available
function M.has(language)
  if not language then
    return false
  end
  local lang_lower = language:lower()
  return parser_modules[lang_lower] ~= nil or parsers[lang_lower] ~= nil
end

---Parse content with the appropriate parser
---@param language string|nil The language identifier (defaults to json)
---@param content string The content to parse
---@param context table|nil Optional context for evaluation
---@return any value The parsed value
---@return string|nil error Error message if parsing failed
function M.parse(language, content, context)
  local lang = language or "json"
  local parser = M.get(lang)

  if not parser then
    return nil, "No parser registered for language: " .. tostring(lang)
  end

  local ok, result = pcall(parser, content, context)
  if not ok then
    return nil, tostring(result)
  end

  return result, nil
end

return M
