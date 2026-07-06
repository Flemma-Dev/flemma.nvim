--- String catalogue backed by po/flemma-harness.po (model-facing strings:
--- conversation text, tool schemas) and po/flemma.po (user-facing UI
--- strings), merged into one flat key namespace — keys must stay unique
--- across the files, enforced at load time.
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
--- Plural entries carry a `plural` selector — `__call` picks the form via
--- the compiled Plural-Forms expression when `count` is present.
---@class flemma.messages.String
---@field key string Catalogue key, kept for error attribution
---@field template string Default msgstr template (singular form for plural entries)
---@field forms string[] All forms (singular: {template}, plural: {msgstr[0], msgstr[1], …})
---@field plural? flemma.utilities.plural.Fn Compiled Plural-Forms selector
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
  if self.plural and variables.count ~= nil then
    local form_index = self.plural(variables.count)
    local template = self.forms[form_index + 1] or self.forms[1]
    return render(self.key, template, variables)
  end
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

---Runtime paths of the shipped catalogues. Keys must stay unique across
---all files — load_catalogue() reports every collision at load time.
local CATALOGUE_PATHS = {
  "po/flemma-harness.po", -- model-facing: conversation text, tool schemas
  "po/flemma.po", -- user-facing UI: notifications, prompts
}

---Read and parse one catalogue file off the runtimepath.
---@param runtime_path string
---@return table<string, flemma.utilities.po.Entry>
local function load_file(runtime_path)
  local matches = vim.api.nvim_get_runtime_file(runtime_path, false)
  local path = matches[1]
  if not path then
    error("messages: " .. runtime_path .. " not found on the runtimepath")
  end
  local file = assert(io.open(path, "r"), "messages: cannot open " .. path)
  local content = file:read("*a")
  file:close()
  return po.parse(content)
end

---Load and merge the shipped catalogues. Runs at require time so parse
---errors and cross-file key collisions surface at startup, and the
---module-level result is the cache.
---@return table<string, flemma.utilities.po.Entry>
local function load_catalogue()
  local merged = {} ---@type table<string, flemma.utilities.po.Entry>
  local collisions = {} ---@type string[]
  for _, runtime_path in ipairs(CATALOGUE_PATHS) do
    for key, entry in pairs(load_file(runtime_path)) do
      if merged[key] ~= nil then
        table.insert(collisions, key)
      else
        merged[key] = entry
      end
    end
  end
  if #collisions > 0 then
    table.sort(collisions)
    error("messages: keys defined in more than one catalogue: " .. table.concat(collisions, ", "))
  end
  return merged
end

local catalogue = load_catalogue()

return setmetatable(M, {
  ---@param key string
  ---@return flemma.messages.String
  __index = function(_, key)
    local entry = catalogue[key]
    if entry == nil then
      error("messages: unknown catalogue key: " .. tostring(key))
    end
    local proxy = setmetatable(
      { key = key, template = entry.forms[1], forms = entry.forms, plural = entry.plural },
      PROXY_METATABLE
    )
    rawset(M, key, proxy)
    return proxy
  end,
})
