--- Strict-subset GNU gettext PO parser.
--- Parses monolingual key-based catalogues: `msgid`/`msgstr` pairs with
--- continuation strings and C-style escapes. Everything outside the subset
--- (msgctxt, plural forms) is rejected with a descriptive error so the
--- shipped catalogue stays compatible with external gettext tooling.
---@class flemma.utilities.Po
local M = {}

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

---Extract and decode the quoted payload of a `msgid`/`msgstr` line.
---@param line string
---@param keyword string
---@param line_number integer
---@return string
local function extract(line, keyword, line_number)
  local fragment = line:match("^" .. keyword .. '%s+"(.*)"%s*$')
  if fragment == nil then
    error(("po: malformed %s on line %d"):format(keyword, line_number), 0)
  end
  return decode(fragment, line_number)
end

---Parse PO file content into a key→content map.
---The header entry (first entry, empty msgid) is skipped. Entries whose
---msgstr is empty are omitted (gettext "untranslated" semantics). Duplicate
---msgids, empty msgids outside the header, unsupported features (msgctxt,
---plural forms), and malformed lines raise errors.
---@param content string
---@return table<string, string> entries
function M.parse(content)
  ---@type table<string, string>
  local entries = {}
  ---@type table<string, boolean>
  local seen = {}
  local entry_count = 0
  ---@type string|nil
  local msgid = nil
  ---@type string|nil
  local msgstr = nil
  ---@type "msgid"|"msgstr"|nil
  local collecting = nil
  local line_number = 0
  local entry_line = 0

  local function finalize()
    if msgid == nil then
      return
    end
    -- collecting == "msgid" (no msgstr seen) is rejected by the callers below.
    if msgid == "" then
      if entry_count > 0 then
        error(("po: empty msgid outside the header entry (line %d)"):format(entry_line), 0)
      end
    else
      if seen[msgid] then
        error(("po: duplicate msgid %q (line %d)"):format(msgid, entry_line), 0)
      end
      seen[msgid] = true
      if msgstr ~= "" then
        entries[msgid] = msgstr --[[@as string]]
      end
    end
    entry_count = entry_count + 1
    msgid, msgstr, collecting = nil, nil, nil
  end

  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    line_number = line_number + 1
    if line:match("^%s*$") or line:sub(1, 1) == "#" then
      -- Blank line or comment (any flavor, including #~ obsolete entries).
      if collecting == "msgid" then
        error(("po: msgid %q has no msgstr (line %d)"):format(tostring(msgid), line_number), 0)
      elseif collecting == "msgstr" then
        finalize()
      end
    elseif line:match('^msgctxt[%s"]') then
      error(("po: msgctxt is not supported (line %d)"):format(line_number), 0)
    elseif line:match('^msgid_plural[%s"]') then
      error(("po: plural forms (msgid_plural) are not supported (line %d)"):format(line_number), 0)
    elseif line:match("^msgstr%[") then
      error(("po: plural forms (msgstr[N]) are not supported (line %d)"):format(line_number), 0)
    elseif line:match("^msgid%s") then
      if collecting == "msgid" then
        error(("po: msgid %q has no msgstr (line %d)"):format(tostring(msgid), line_number), 0)
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
      elseif collecting == "msgstr" then
        msgstr = (msgstr or "") .. decoded
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
  finalize()
  return entries
end

return M
