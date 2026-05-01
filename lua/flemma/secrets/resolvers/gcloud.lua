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

---@param path string
---@param env table<string, string>|nil
---@param ctx flemma.secrets.Context
---@param callback fun(result: flemma.secrets.Result|nil)
local function run_gcloud_async(path, env, ctx, callback)
  local opts = { text = true }
  if env then
    opts.env = env
  end
  vim.system({ path, "auth", "print-access-token" }, opts, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        ctx:diagnostic("auth failed (exit code " .. tostring(result.code) .. ")")
        callback(nil)
        return
      end
      local token = (result.stdout or ""):gsub("%s+$", "")
      if #token == 0 then
        ctx:diagnostic("returned empty token")
        callback(nil)
        return
      end
      callback({ value = token, ttl = TOKEN_TTL_SECONDS })
    end)
  end)
end

---@param _self flemma.secrets.resolvers.Gcloud
---@param credential flemma.secrets.Credential
---@param ctx flemma.secrets.Context
---@param callback fun(result: flemma.secrets.Result|nil)
function M.resolve_async(_self, credential, ctx, callback)
  local cfg = ctx:get_config()
  local path = (cfg and cfg.path) or "gcloud"

  secrets.resolve_async({ kind = "service_account", service = credential.service }, function(service_account)
    if service_account and service_account.value:match("service_account") then
      local tmp = vim.fn.tempname()
      local file = io.open(tmp, "w")
      if not file then
        log.error("gcloud: failed to create temp file for service account")
        ctx:diagnostic("failed to create temp file for service account")
        callback(nil)
        return
      end
      file:write(service_account.value)
      file:close()

      run_gcloud_async(path, { GOOGLE_APPLICATION_CREDENTIALS = tmp }, ctx, function(result)
        os.remove(tmp)
        if result then
          log.debug("gcloud: generated access token from service account (async)")
        end
        callback(result)
      end)
      return
    end

    log.debug("gcloud: trying default credentials (async)")
    run_gcloud_async(path, nil, ctx, callback)
  end)
end

return M
