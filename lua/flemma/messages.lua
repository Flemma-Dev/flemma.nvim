--- String catalogue backed by po/flemma.po.
--- The module IS the catalogue: indexing any key returns a lazily rendered
--- string proxy. `messages["job.executing.tracked"]{ job_id = id }` renders
--- with variables; `messages["tool.denied"]{}` forces a no-variable render
--- where a real string must materialize immediately (a stored/returned
--- field); a bare `messages["tool.denied"]` (no call at all) is enough
--- wherever the consumer already stringifies it, e.g. `:describe()` or `..`
--- concatenation, via `__tostring`/`__concat`.
--- The module exports no functions — every index is a catalogue lookup.
--- Call sites use Lua's brace-call sugar (`messages[...]{ ... }`); `make format`
--- strips the parentheses stylua re-adds, via
--- contrib/scripts/format-messages-brace-call.sh.
---@class flemma.messages
---@field [string] flemma.messages.String
local M = {}

local log = require("flemma.logging")
local po = require("flemma.utilities.po")
local renderer = require("flemma.templating.renderer")

---A lazily rendered catalogue entry.
--- `variables` is mandatory on `__call` — always pass a table (`{}` when the
--- entry has none) — so a bare `messages["key"]()` is a type-check error
--- instead of silently rendering, keeping the old no-args call style from
--- creeping back in.
---@class flemma.messages.String
---@field key string Catalogue key, kept for error attribution
---@field template string Raw msgstr template
---@operator call(table<string, any>): string
---@operator concat(any): string

---A description/text value accepted where either a plain string or an
---unrendered catalogue proxy is valid — consumers normalize with `tostring()`.
---@alias flemma.Message string|flemma.messages.String

---Render a template through the templating engine. Output is exact — PO
---content is explicit, so no trimming is applied.
---@param key string
---@param template string
---@param variables? table<string, any>
---@return string
local function render(key, template, variables)
  local parts, diagnostics = renderer.render(template, variables or {})
  for _, diagnostic in ipairs(diagnostics) do
    log.warn("messages: '" .. key .. "': " .. (diagnostic.error or "unknown error"))
  end
  return renderer.parts_to_text(parts)
end

local PROXY_METATABLE = {}

---Resolve either operand of `__concat` to text.
---@param value any
---@return string
local function concat_operand_to_text(value)
  if getmetatable(value) == PROXY_METATABLE then
    ---@cast value flemma.messages.String
    return render(value.key, value.template, nil)
  end
  return tostring(value)
end

---@param self flemma.messages.String
---@param variables table<string, any>
---@return string
PROXY_METATABLE.__call = function(self, variables)
  return render(self.key, self.template, variables)
end

---@param self flemma.messages.String
---@return string
PROXY_METATABLE.__tostring = function(self)
  return render(self.key, self.template, nil)
end

---@param left any
---@param right any
---@return string
PROXY_METATABLE.__concat = function(left, right)
  return concat_operand_to_text(left) .. concat_operand_to_text(right)
end

---Load and parse the shipped catalogue. Runs at require time so parse
---errors surface at startup, and the module-level result is the cache.
---@return table<string, string>
local function load_catalogue()
  local matches = vim.api.nvim_get_runtime_file("po/flemma.po", false)
  local path = matches[1]
  if not path then
    error("messages: po/flemma.po not found on the runtimepath")
  end
  local file = assert(io.open(path, "r"), "messages: cannot open " .. path)
  local content = file:read("*a")
  file:close()
  return po.parse(content)
end

local catalogue = load_catalogue()

return setmetatable(M, {
  ---@param key string
  ---@return flemma.messages.String
  __index = function(_, key)
    local template = catalogue[key]
    if template == nil then
      error("messages: unknown catalogue key: " .. tostring(key))
    end
    local proxy = setmetatable({ key = key, template = template }, PROXY_METATABLE)
    rawset(M, key, proxy)
    return proxy
  end,
})
