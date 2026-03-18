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
---@param ctx flemma.secrets.Context
---@return boolean
function M.supports(_self, credential, ctx)
  if credential.kind ~= "access_token" then
    ctx:diagnostic("only resolves access_token credentials")
    return false
  end
  local cfg = ctx:get_config()
  local path = (cfg and cfg.path) or "gcloud"
  if vim.fn.executable(path) ~= 1 then
    ctx:diagnostic("executable not found: '" .. path .. "' (check secrets.gcloud.path)")
    return false
  end
  return true
end

--- Run gcloud auth print-access-token with the given binary path and optional env.
---@param path string Binary path or name (e.g. "gcloud" or "/nix/store/.../bin/gcloud")
---@param env? table<string, string>
---@return string|nil token, integer|nil exit_code
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
    return nil, result.code
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
---@param ctx flemma.secrets.Context
---@return flemma.secrets.Result|nil
function M.resolve(_self, credential, ctx)
  local cfg = ctx:get_config()
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
      ctx:diagnostic("failed to create temp file for service account")
      return nil
    end
    file:write(service_account.value)
    file:close()

    local token, exit_code = run_gcloud(path, { GOOGLE_APPLICATION_CREDENTIALS = tmp })

    -- Delete temp file immediately
    os.remove(tmp)

    if token then
      log.debug("gcloud: generated access token from service account")
      return { value = token, ttl = TOKEN_TTL_SECONDS }
    end

    if exit_code then
      ctx:diagnostic("auth failed (exit code " .. tostring(exit_code) .. ")")
    else
      ctx:diagnostic("returned empty token")
    end
    log.debug("gcloud: failed to generate token from service account")
    return nil
  end

  -- Fallback: try default gcloud credentials
  log.debug("gcloud: trying default credentials")
  local token, exit_code = run_gcloud(path)
  if token then
    return { value = token, ttl = TOKEN_TTL_SECONDS }
  end

  if exit_code then
    ctx:diagnostic("auth failed (exit code " .. tostring(exit_code) .. ")")
  else
    ctx:diagnostic("returned empty token")
  end

  return nil
end

return M
