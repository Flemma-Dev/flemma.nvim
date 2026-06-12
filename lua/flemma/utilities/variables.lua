--- Variable expansion utility
--- Expands URN-mapped Flemma variables, environment variables with ${VAR:-default}
--- fallback syntax, and ~ home directory references. Provides prefix deduplication
--- for path lists.
---@class flemma.utilities.Variables
local M = {}

--- Registered URN resolvers.
--- Each resolver receives an optional context table and returns a string or nil.
---@type table<string, fun(context?: table): string|nil>
local resolvers = {}

--- Registered inline variable resolvers.
--- Checked by expand_inline before falling back to os.getenv.
---@type table<string, fun(context?: table): string|nil>
local inline_resolvers = {}

local URN_PREFIX = "urn:"

--- Register a URN variable resolver.
---@param urn string URN identifier (e.g., "urn:flemma:cwd")
---@param resolver fun(context?: table): string|nil
function M.register(urn, resolver)
  resolvers[urn] = resolver
end

---Register a variable that expand_inline resolves before os.getenv.
---@param name string Variable name (without $)
---@param resolver fun(context?: table): string|nil
function M.register_inline(name, resolver)
  inline_resolvers[name] = resolver
end

--- Clear all registered resolvers (for testing).
function M.clear()
  resolvers = {}
  inline_resolvers = {}
end

--- Expand ~ at the start of a string to the home directory.
---@param value string
---@return string
local function expand_tilde(value)
  if vim.startswith(value, "~/") or value == "~" then
    return vim.fn.expand(value)
  end
  return value
end

--- Expand a single variable string.
---
--- Supported forms:
---   - `urn:flemma:*`     — looked up in the resolver registry
---   - `$VAR`             — os.getenv("VAR"), nil if unset
---   - `${VAR:-default}`  — os.getenv("VAR"), falls back to default (~ expanded)
---   - `~/...`            — expands ~ to $HOME
---   - anything else      — returned as-is (literal path)
---
---@param value string The variable or path to expand
---@param context? table Optional context passed to URN resolvers
---@return string|nil result nil when the variable resolves to nothing
function M.expand(value, context)
  -- URN variables: look up in registry
  if value:sub(1, #URN_PREFIX) == URN_PREFIX then
    local resolver = resolvers[value]
    if not resolver then
      error("flemma: unknown URN variable '" .. value .. "'", 2)
    end
    return resolver(context)
  end

  -- ${VAR:-default} syntax
  local var_name, default = value:match("^%${([%w_]+):%-(.+)}$")
  if var_name then
    local env_value = os.getenv(var_name)
    if env_value and env_value ~= "" then
      return env_value
    end
    return expand_tilde(default)
  end

  -- $VAR syntax
  local simple_var = value:match("^%$([%w_]+)$")
  if simple_var then
    return os.getenv(simple_var)
  end

  -- Tilde expansion
  if value:sub(1, 1) == "~" then
    return expand_tilde(value)
  end

  -- Literal path
  return value
end

--- Expand a list of variable strings, dropping nil results and
--- silently skipping entries that error (e.g. unregistered URNs).
---@param values string[]
---@param context? table Optional context passed to URN resolvers
---@return string[]
function M.expand_list(values, context)
  local result = {}
  for _, value in ipairs(values) do
    local ok, expanded = pcall(M.expand, value, context)
    if ok and expanded then
      table.insert(result, expanded)
    end
  end
  return result
end

--- Deduplicate a list of absolute paths by prefix.
--- If path A is a parent of path B (B starts with A/), B is dropped.
--- The result is sorted alphabetically.
---@param paths string[]
---@return string[]
function M.deduplicate_by_prefix(paths)
  if #paths <= 1 then
    return vim.deepcopy(paths)
  end

  -- Sort alphabetically (shallowest parents naturally come first)
  local sorted = vim.deepcopy(paths)
  table.sort(sorted)

  local result = {}
  for _, path in ipairs(sorted) do
    local subsumed = false
    for _, kept in ipairs(result) do
      -- Check if `kept` is a parent of `path` (must match at / boundary)
      if path == kept or (vim.startswith(path, kept) and path:sub(#kept + 1, #kept + 1) == "/") then
        subsumed = true
        break
      end
    end
    if not subsumed then
      table.insert(result, path)
    end
  end

  return result
end

--- Expand environment variable references inline within a larger string.
---
--- Unlike `expand()` which requires the entire string to be one variable
--- reference, this finds and replaces all `${VAR:-default}`, `$VAR`, and
--- leading `~/` occurrences within the string.
---
--- URN references (`urn:flemma:*`) are not supported inline — they are
--- whole-string patterns handled by `expand()`.
---@param text string
---@return string
function M.expand_inline(text)
  -- Expansion is iterative so references inside substituted values resolve;
  -- the pass cap stops mutually-referential resolvers from looping forever.
  local MAX_PASSES = 8
  local passes = 0
  local prev
  repeat
    prev = text
    passes = passes + 1

    -- ${VAR:-default} — greedy match on var name, non-greedy on default
    text = text:gsub("%${([%w_]+):%-(.-)}", function(var, default)
      local val
      if inline_resolvers[var] then
        val = inline_resolvers[var]()
      else
        val = os.getenv(var)
      end
      if val and val ~= "" then
        return val
      end
      return expand_tilde(default)
    end)

    -- Bare $VAR — only match word-character var names to avoid false positives
    text = text:gsub("%$([%w_]+)", function(var)
      if inline_resolvers[var] then
        return inline_resolvers[var]() or ""
      end
      return os.getenv(var) or ""
    end)
  until text == prev or passes >= MAX_PASSES

  -- Leading ~/
  if text:sub(1, 2) == "~/" or text == "~" then
    text = expand_tilde(text)
  end

  return text
end

return M
