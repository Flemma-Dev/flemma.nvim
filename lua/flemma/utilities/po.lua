--- Strict-subset GNU gettext PO parser.
--- Parses monolingual key-based catalogues: `msgid`/`msgstr` pairs with
--- continuation strings, C-style escapes, and plural forms. Everything
--- outside the subset (msgctxt) is rejected with a descriptive error so
--- the shipped catalogue stays compatible with external gettext tooling.
---@class flemma.utilities.Po
local M = {}

local plural = require("flemma.utilities.plural")

---@type table<string, string>
local ESCAPES = { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }

---Decode the inside of a PO quoted fragment, applying escape sequences.
---@param fragment string Content between the outer double quotes
---@param line_number integer 1-based line number for error attribution
---@return string
local function decode(fragment, line_number)
  local out = {}
  local i = 1
  while i <= #fragment do
    local char = fragment:sub(i, i)
    if char == "\\" then
      local escape = fragment:sub(i + 1, i + 1)
      local mapped = ESCAPES[escape]
      if not mapped then
        error(("po: unsupported escape sequence '\\%s' on line %d"):format(escape, line_number), 0)
      end
      out[#out + 1] = mapped
      i = i + 2
    elseif char == '"' then
      error(("po: unescaped quote on line %d"):format(line_number), 0)
    else
      out[#out + 1] = char
      i = i + 1
    end
  end
  return table.concat(out)
end

---Extract and decode the quoted payload of a directive line.
---@param line string
---@param keyword string Lua pattern matching the keyword prefix
---@param line_number integer
---@return string
local function extract(line, keyword, line_number)
  local fragment = line:match("^" .. keyword .. '%s+"(.*)"%s*$')
  if fragment == nil then
    error(("po: malformed %s on line %d"):format(keyword, line_number), 0)
  end
  return decode(fragment, line_number)
end

---A parsed catalogue entry. Singular entries have a single-element `forms`
---array and no `plural` selector; plural entries carry multiple forms and a
---compiled `Plural-Forms` expression.
---@class flemma.utilities.po.Entry
---@field forms string[] 1-indexed; singular: {msgstr}, plural: {msgstr[0], msgstr[1], …}
---@field plural? flemma.utilities.plural.Fn Compiled Plural-Forms expression; returns 0-based index

---Default English plural selector used when no Plural-Forms header exists.
---@type flemma.utilities.plural.Fn
local DEFAULT_PLURAL_FN = function(n)
  return n ~= 1 and 1 or 0
end

---Parse PO file content into a key→content map.
---The header entry (first entry, empty msgid) is skipped. Entries whose
---msgstr is empty are omitted (gettext "untranslated" semantics). Duplicate
---msgids, empty msgids outside the header, unsupported features (msgctxt),
---and malformed lines raise errors.
---Plural entries (`msgid_plural` + `msgstr[N]`) carry multiple forms and a
---compiled `plural` selector; singular entries have a single-element `forms`
---array and no selector.
---@param content string
---@return table<string, flemma.utilities.po.Entry> entries
function M.parse(content)
  ---@type table<string, flemma.utilities.po.Entry>
  local entries = {}
  ---@type table<string, boolean>
  local seen = {}
  local entry_count = 0

  ---@type string|nil
  local msgid = nil
  ---@type string|nil
  local msgstr = nil
  ---@type string|nil
  local msgid_plural_str = nil
  ---@type string[]|nil
  local msgstr_forms = nil
  ---@type integer|nil
  local current_form_index = nil

  ---@type "msgid"|"msgid_plural"|"msgstr"|"msgstr_plural"|nil
  local collecting = nil
  local line_number = 0
  local entry_line = 0

  ---@type flemma.utilities.plural.Fn|nil
  local header_plural_fn = nil

  local function finalize()
    if msgid == nil then
      return
    end
    if msgid == "" then
      if entry_count > 0 then
        error(("po: empty msgid outside the header entry (line %d)"):format(entry_line), 0)
      end
      if msgstr and msgstr ~= "" then
        for header_line in msgstr:gmatch("[^\n]+") do
          local value = header_line:match("^Plural%-Forms:%s*(.+)")
          if value then
            local _
            _, header_plural_fn = plural.parse_header(value)
            break
          end
        end
      end
    else
      if seen[msgid] then
        error(("po: duplicate msgid %q (line %d)"):format(msgid, entry_line), 0)
      end
      seen[msgid] = true
      if msgid_plural_str ~= nil then
        if msgstr_forms and #msgstr_forms > 0 then
          entries[msgid] = {
            forms = msgstr_forms,
            plural = header_plural_fn or DEFAULT_PLURAL_FN,
          }
        end
      else
        if msgstr ~= "" then
          entries[msgid] = {
            forms = {
              msgstr --[[@as string]],
            },
          }
        end
      end
    end
    entry_count = entry_count + 1
    msgid = nil
    msgstr = nil
    msgid_plural_str = nil
    msgstr_forms = nil
    current_form_index = nil
    collecting = nil
  end

  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    line_number = line_number + 1
    if line:match("^%s*$") or line:sub(1, 1) == "#" then
      -- Blank line or comment (any flavor, including #~ obsolete entries).
      if collecting == "msgid" then
        error(("po: msgid %q has no msgstr (line %d)"):format(tostring(msgid), line_number), 0)
      elseif collecting == "msgid_plural" then
        error(("po: msgid_plural has no msgstr[0] (line %d)"):format(line_number), 0)
      elseif collecting == "msgstr" or collecting == "msgstr_plural" then
        finalize()
      end
    elseif line:match('^msgctxt[%s"]') then
      error(("po: msgctxt is not supported (line %d)"):format(line_number), 0)
    elseif line:match("^msgid_plural%s") then
      if collecting ~= "msgid" then
        error(("po: msgid_plural without a preceding msgid (line %d)"):format(line_number), 0)
      end
      msgid_plural_str = extract(line, "msgid_plural", line_number)
      collecting = "msgid_plural"
    elseif line:match("^msgstr%[") then
      local index_str = line:match("^msgstr%[(%d+)%]")
      if not index_str then
        error(("po: malformed msgstr[N] on line %d"):format(line_number), 0)
      end
      local index = tonumber(index_str) --[[@as integer]]
      if collecting == "msgid_plural" then
        if index ~= 0 then
          error(("po: expected msgstr[0] after msgid_plural, got msgstr[%d] (line %d)"):format(index, line_number), 0)
        end
        msgstr_forms = {}
      elseif collecting == "msgstr_plural" then
        if index ~= current_form_index + 1 then
          error(
            ("po: expected msgstr[%d], got msgstr[%d] (line %d)"):format(current_form_index + 1, index, line_number),
            0
          )
        end
      else
        error(("po: msgstr[N] without a preceding msgid_plural (line %d)"):format(line_number), 0)
      end
      current_form_index = index
      msgstr_forms[index + 1] = extract(line, "msgstr%[" .. index_str .. "%]", line_number)
      collecting = "msgstr_plural"
    elseif line:match("^msgid%s") then
      if collecting == "msgid" then
        error(("po: msgid %q has no msgstr (line %d)"):format(tostring(msgid), line_number), 0)
      end
      if collecting == "msgid_plural" then
        error(("po: msgid_plural has no msgstr[0] (line %d)"):format(line_number), 0)
      end
      finalize()
      entry_line = line_number
      msgid = extract(line, "msgid", line_number)
      collecting = "msgid"
    elseif line:match("^msgstr%s") then
      if collecting ~= "msgid" then
        error(("po: msgstr without a preceding msgid (line %d)"):format(line_number), 0)
      end
      msgstr = extract(line, "msgstr", line_number)
      collecting = "msgstr"
    elseif line:sub(1, 1) == '"' then
      local fragment = line:match('^"(.*)"%s*$')
      if fragment == nil then
        error(("po: malformed continuation string on line %d"):format(line_number), 0)
      end
      local decoded = decode(fragment, line_number)
      if collecting == "msgid" then
        msgid = (msgid or "") .. decoded
      elseif collecting == "msgid_plural" then
        msgid_plural_str = (msgid_plural_str or "") .. decoded
      elseif collecting == "msgstr" then
        msgstr = (msgstr or "") .. decoded
      elseif collecting == "msgstr_plural" then
        ---@cast current_form_index integer
        ---@cast msgstr_forms string[]
        msgstr_forms[current_form_index + 1] = (msgstr_forms[current_form_index + 1] or "") .. decoded
      else
        error(("po: continuation string outside an entry (line %d)"):format(line_number), 0)
      end
    else
      error(("po: unexpected content on line %d: %s"):format(line_number, line), 0)
    end
  end

  if collecting == "msgid" then
    error(("po: msgid %q has no msgstr (line %d)"):format(msgid, line_number), 0)
  end
  if collecting == "msgid_plural" then
    error(("po: msgid_plural has no msgstr[0] (line %d)"):format(line_number), 0)
  end
  finalize()
  return entries
end

return M
