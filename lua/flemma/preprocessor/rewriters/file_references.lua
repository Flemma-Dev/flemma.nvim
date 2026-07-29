--- File-references rewriter
--- Converts @./path, @../path, @~/path, and @//absolute/path references into include() expressions
--- that the processor evaluates into file parts.
---@class flemma.preprocessor.rewriters.FileReferences
local M = {}

local modeline = require("flemma.utilities.modeline")
local preprocessor = require("flemma.preprocessor")
local utilities = require("flemma.utilities.encoding")

local url_decode = utilities.url_decode
local lua_string_escape = utilities.lua_string_escape

---Strip trailing prose punctuation from a raw reference. Quote-aware: nothing
---at or before the last quote character is touched, so punctuation inside a
---quoted option value (`;note='a;b.'`) is content, not sentence prose.
---@param raw string
---@return string body The reference without trailing punctuation
---@return string trailing The stripped trailing punctuation
local function strip_trailing_punctuation(raw)
  local prefix, tail = raw:match("^(.*['\"])(.-)$")
  if not prefix then
    prefix, tail = "", raw
  end
  local cleaned = tail:gsub("[%p]+$", "")
  local body = prefix .. cleaned
  return body, raw:sub(#body + 1)
end

local file_refs = preprocessor.create_rewriter("file-references", { priority = 100 })

--- Shared handler for file reference patterns (@./, @../, @~/, @//).
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

  -- Trailing prose punctuation belongs to the sentence, not the reference:
  -- strip it from the raw capture first, so the pathless and options-bearing
  -- forms share one rule, then parse the remainder through the shared matrix
  -- grammar. `type=` is the only option consumed today; other keys parse
  -- uniformly and are ignored. A MIME with parameters must be quoted
  -- (`;type='text/plain;charset=utf-8'`) — an unquoted `;` starts the next
  -- option per the grammar.
  local raw, trailing = strip_trailing_punctuation(match.captures[1])
  local raw_path, options = modeline.parse_matrix(raw)
  local opts_parts = { "[symbols.BINARY] = true" }
  local mime = options.type
  if mime ~= nil and type(mime) ~= "table" then
    table.insert(opts_parts, "[symbols.MIME] = '" .. lua_string_escape(tostring(mime)) .. "'")
  end

  local path = url_decode(raw_path) --[[@as string]]

  -- @// convention: strip the leading / so //tmp/foo becomes /tmp/foo
  if path:sub(1, 2) == "//" then
    path = path:sub(2)
  end

  local escaped_path = lua_string_escape(path)
  local code = "include('" .. escaped_path .. "', { " .. table.concat(opts_parts, ", ") .. " })"

  if trailing and #trailing > 0 then
    return { ctx:expression(code), ctx:text(trailing) }
  end

  return ctx:expression(code)
end

file_refs:on_text("@(%.%.?%/[%.%/]*%S+)", handle_file_reference)
file_refs:on_text("@(%/%/%S+)", handle_file_reference)
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
      pattern = [=[@\v(\/\/)\S*[^[:punct:]\s]]=],
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
