-- LuaLS configuration for CLI type checking (used by `make check`).
--
-- Reads .luarc.jsonc as the single source of truth for diagnostic settings,
-- then resolves LuaLS variables ($VIMRUNTIME, ${3rd}) in all string values.
-- The editor uses .luarc.jsonc directly, where the language server resolves
-- those variables automatically. In CLI --check mode it doesn't, so this
-- wrapper handles it.

--- Strip a // line comment only if it's outside of string literals.
local function strip_line_comment(line)
  local in_string = false
  for i = 1, #line do
    local ch = line:sub(i, i)
    if ch == '"' and (i == 1 or line:sub(i - 1, i - 1) ~= "\\") then
      in_string = not in_string
    elseif not in_string and ch == "/" and line:sub(i + 1, i + 1) == "/" then
      return line:sub(1, i - 1)
    end
  end
  return line
end

--- Parse a JSONC file into a Lua table.
--- Strips // and /* */ comments, then converts JSON syntax to a Lua table
--- literal and evaluates it with load(). Only suitable for simple config
--- files — string values must not contain unescaped [ ] characters.
local function read_jsonc(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()

  -- Strip JSONC comments (line comments must be string-aware to not eat URLs)
  local lines = {}
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = strip_line_comment(line)
  end
  content = table.concat(lines, "\n")
  content = content:gsub("/%*.-%*/", "") -- block comments

  -- JSON → Lua table literal
  content = content:gsub("%[", "{") -- arrays
  content = content:gsub("%]", "}") -- arrays
  content = content:gsub('"([^"]+)"%s*:', '["%1"] =') -- keys
  content = content:gsub(":%s*null", "= nil") -- null → nil

  local fn = load("return " .. content)
  if not fn then
    return nil
  end
  return fn()
end

-- Load the editor config as the base (run from project root via Makefile)
local config = read_jsonc(".luarc.jsonc")
if not config then
  error(".luarc-check.lua: could not read or parse .luarc.jsonc")
end

-- Resolve VIMRUNTIME: the Makefile sets this for CLI mode.
local vimruntime = os.getenv("VIMRUNTIME")

-- Resolve the LuaLS 3rd-party stub directory (for luv types, etc.).
-- Auto-detect from the lua-language-server binary path on NixOS and
-- conventional installs; override with LUA_LS_3RD env var if needed.
local thirdparty = os.getenv("LUA_LS_3RD")
if not thirdparty or thirdparty == "" then
  thirdparty = nil
  local ok, handle = pcall(io.popen, 'readlink -f "$(which lua-language-server 2>/dev/null)" 2>/dev/null')
  if ok and handle then
    local bin_path = handle:read("*l") or ""
    handle:close()
    local root = bin_path:match("(.+)/bin/lua%-language%-server$")
    if root then
      thirdparty = root .. "/share/lua-language-server/meta/3rd"
    end
  end
end

-- Resolve LuaLS variables in all string values throughout the config tree.
-- This mirrors what the language server does internally for JSON configs.
local function resolve_variables(tbl)
  for k, v in pairs(tbl) do
    if type(v) == "string" then
      if vimruntime then
        v = v:gsub("%$VIMRUNTIME", vimruntime)
      end
      if thirdparty then
        v = v:gsub("%${3rd}", thirdparty)
      end
      tbl[k] = v
    elseif type(v) == "table" then
      resolve_variables(v)
    end
  end
end

resolve_variables(config)

return config
