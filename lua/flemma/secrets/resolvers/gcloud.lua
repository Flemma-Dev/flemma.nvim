---@class flemma.secrets.resolvers.Gcloud : flemma.secrets.Resolver
--- Derives access tokens using the gcloud CLI.
--- Tries to resolve a service_account credential first, then uses it with
--- gcloud auth print-access-token. Falls back to default gcloud credentials.
local M = {}

local log = require("flemma.logging")
local secrets = require("flemma.secrets")

M.name = "gcloud"
M.priority = 25

--- Token TTL reported by Google (1 hour).
local TOKEN_TTL_SECONDS = 3600

---@param _self flemma.secrets.resolvers.Gcloud
---@param credential flemma.secrets.Credential
---@param ctx flemma.config.ConfigAware
---@return boolean
function M.supports(_self, credential, ctx)
  local cfg = ctx:get_config()
  ---@cast cfg flemma.config.SecretsGcloudConfig|nil
  local path = (cfg and cfg.path) or "gcloud"
  return credential.kind == "access_token" and vim.fn.executable(path) == 1
end

--- Run gcloud auth print-access-token with the given binary path and optional env.
---@param path string Binary path or name (e.g. "gcloud" or "/nix/store/.../bin/gcloud")
---@param env? table<string, string>
---@return string|nil token
local function run_gcloud(path, env)
  local cmd = { path, "auth", "print-access-token" }
  local opts = { text = true }
  if env then
    opts.env = env
  end

  local proc = vim.system(cmd, opts)
  local result = proc:wait()

  if result.code ~= 0 then
    log.debug("gcloud: command failed with code " .. tostring(result.code))
    return nil
  end

  local token = result.stdout
  if not token then
    return nil
  end

  token = token:gsub("%s+$", "")
  if #token == 0 then
    return nil
  end

  return token
end

---@param _self flemma.secrets.resolvers.Gcloud
---@param credential flemma.secrets.Credential
---@param ctx flemma.config.ConfigAware
---@return flemma.secrets.Result|nil
function M.resolve(_self, credential, ctx)
  local cfg = ctx:get_config()
  ---@cast cfg flemma.config.SecretsGcloudConfig|nil
  local path = (cfg and cfg.path) or "gcloud"

  -- Try to get a service account for this service
  local service_account = secrets.resolve({
    kind = "service_account",
    service = credential.service,
  })

  if service_account and service_account.value:match("service_account") then
    -- Write service account JSON to temp file
    local tmp = vim.fn.tempname()
    local file = io.open(tmp, "w")
    if not file then
      log.error("gcloud: failed to create temp file for service account")
      return nil
    end
    file:write(service_account.value)
    file:close()

    local token = run_gcloud(path, { GOOGLE_APPLICATION_CREDENTIALS = tmp })

    -- Delete temp file immediately
    os.remove(tmp)

    if token then
      log.debug("gcloud: generated access token from service account")
      return { value = token, ttl = TOKEN_TTL_SECONDS }
    end

    log.debug("gcloud: failed to generate token from service account")
    return nil
  end

  -- Fallback: try default gcloud credentials
  log.debug("gcloud: trying default credentials")
  local token = run_gcloud(path)
  if token then
    return { value = token, ttl = TOKEN_TTL_SECONDS }
  end

  return nil
end

return M
