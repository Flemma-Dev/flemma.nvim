--- File-references rewriter
--- Converts @./path, @../path, and @~/path references into include() expressions
--- that the processor evaluates into file parts.
---@class flemma.preprocessor.rewriters.FileReferences
local M = {}

local preprocessor = require("flemma.preprocessor")
local utilities = require("flemma.preprocessor.utilities")

local url_decode = utilities.url_decode
local lua_string_escape = utilities.lua_string_escape

---Strip trailing punctuation from a file path.
---@param path string
---@return string path The path without trailing punctuation
---@return string trailing The stripped trailing punctuation
local function strip_trailing_punctuation(path)
  local cleaned = path:gsub("[%p]+$", "")
  local trailing = path:sub(#cleaned + 1)
  return cleaned, trailing
end

local file_refs = preprocessor.create_rewriter("file-references", { priority = 100 })

--- Shared handler for file reference patterns (@./, @../, @~/).
--- Parses options (;type=mime), strips trailing punctuation, and emits
--- an include() expression with BINARY and optional MIME flags.
---@param match flemma.preprocessor.Match
---@param ctx flemma.preprocessor.Context
---@return flemma.preprocessor.Emission|flemma.preprocessor.EmissionList|nil
local function handle_file_reference(match, ctx)
  -- File references only apply to non-Assistant messages
  if ctx.message and ctx.message.role == "Assistant" then
    return nil
  end

  local raw_path, options_str = match.captures[1]:match("^([^;]+)(;.+)$")
  local trailing

  local opts_parts = {}
  if options_str then
    local mime_with_punct = options_str:match("^;type=(.+)$")
    if mime_with_punct then
      local mime = mime_with_punct:gsub("[%p]+$", "")
      trailing = mime_with_punct:sub(#mime + 1)
      table.insert(opts_parts, "[symbols.BINARY] = true")
      table.insert(opts_parts, "[symbols.MIME] = '" .. lua_string_escape(mime) .. "'")
    end
  else
    raw_path = match.captures[1]
    local stripped
    stripped, trailing = strip_trailing_punctuation(raw_path)
    raw_path = stripped
    table.insert(opts_parts, "[symbols.BINARY] = true")
  end

  local path = url_decode(raw_path)
  ---@cast path string

  local escaped_path = lua_string_escape(path)
  local code = "include('" .. escaped_path .. "', { " .. table.concat(opts_parts, ", ") .. " })"

  if trailing and #trailing > 0 then
    return { ctx:expression(code), ctx:text(trailing) }
  end

  return ctx:expression(code)
end

file_refs:on_text("@(%.%.?%/[%.%/]*%S+)", handle_file_reference)
file_refs:on_text("@(~%/%S+)", handle_file_reference)

---@param config flemma.Config
---@return flemma.preprocessor.SyntaxRule[]
function file_refs:get_vim_syntax(config)
  return {
    {
      kind = "match",
      group = "FlemmaUserFileReference",
      pattern = [=[@\v(\.\.?\/)\S*[^[:punct:]\s]]=],
      containedin = { "user", "system" },
      hl = config.highlights.user_file_reference,
    },
    {
      kind = "match",
      group = "FlemmaUserFileReference",
      pattern = [=[@\v(\~\/)\S*[^[:punct:]\s]]=],
      containedin = { "user", "system" },
      hl = config.highlights.user_file_reference,
    },
  }
end

M.rewriter = file_refs

return M
