---@class flemma.secrets.cache
--- TTL-aware credential cache for the secrets module.
--- Stores resolved credentials keyed by "kind:service" and evicts entries
--- whose effective TTL has elapsed.
local M = {}

---@class flemma.secrets.Result
---@field value string
---@field ttl? integer

---@class flemma.secrets.CachedResult
---@field result flemma.secrets.Result
---@field resolved_at integer
---@field effective_ttl? number

--- Partial definition; authoritative definition is in flemma.secrets (init.lua).
---@class flemma.secrets.Credential
---@field kind string
---@field service string
---@field ttl? integer
---@field ttl_scale? number

---@type table<string, flemma.secrets.CachedResult>
local entries = {}

--- Check whether a cached entry is stale.
---@param entry flemma.secrets.CachedResult
---@return boolean
local function is_stale(entry)
  if not entry.effective_ttl then
    return false
  end
  local age = os.time() - entry.resolved_at
  return age >= entry.effective_ttl
end

--- Compute the effective TTL from result and credential TTLs plus scale.
---@param result flemma.secrets.Result
---@param credential flemma.secrets.Credential
---@return number|nil
local function compute_effective_ttl(result, credential)
  local base_ttl = result.ttl or credential.ttl
  if not base_ttl then
    return nil
  end
  local scale = credential.ttl_scale or 1.0
  return base_ttl * scale
end

--- Get a cached result. Returns nil if not found or stale.
---@param key string
---@return flemma.secrets.Result|nil
function M.get(key)
  local entry = entries[key]
  if not entry then
    return nil
  end
  if is_stale(entry) then
    entries[key] = nil
    return nil
  end
  return entry.result
end

--- Get the raw CachedResult entry (for testing/inspection).
---@param key string
---@return flemma.secrets.CachedResult|nil
function M.get_entry(key)
  return entries[key]
end

--- Store a result in the cache.
---@param key string
---@param result flemma.secrets.Result
---@param credential flemma.secrets.Credential
function M.set(key, result, credential)
  entries[key] = {
    result = result,
    resolved_at = os.time(),
    effective_ttl = compute_effective_ttl(result, credential),
  }
end

--- Remove a specific cache entry.
---@param key string
function M.invalidate(key)
  entries[key] = nil
end

--- Remove all cache entries.
function M.invalidate_all()
  entries = {}
end

--- Return the number of cached entries.
---@return integer
function M.count()
  local n = 0
  for _ in pairs(entries) do
    n = n + 1
  end
  return n
end

return M
