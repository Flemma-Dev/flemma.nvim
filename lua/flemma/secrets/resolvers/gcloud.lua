---@class flemma.secrets.resolvers.Gcloud : flemma.secrets.Resolver
--- Derives access tokens using the gcloud CLI.
--- Tries to resolve a service_account credential first; if found, mints a token
--- from the key via `gcloud auth application-default print-access-token` (which
--- honours GOOGLE_APPLICATION_CREDENTIALS). Otherwise falls back to the active
--- CLI account via `gcloud auth print-access-token`.
local M = {}

local log = require("flemma.logging")
local s = require("flemma.schema")
local secrets = require("flemma.secrets")

M.name = "gcloud"
M.priority = 25

---@type flemma.secrets.ResolverMetadata
M.metadata = {
  config_schema = s.object({
    path = s.string("gcloud"),
  }),
}

--- Token TTL reported by Google (1 hour).
local TOKEN_TTL_SECONDS = 3600

--- Vertex AI (and Google Cloud APIs generally) require the cloud-platform scope.
--- ADC mints service-account tokens with no default scope, so we request it explicitly.
local CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"

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
---@param args string[] gcloud subcommand arguments (after `path`)
---@param env table<string, string>|nil
---@param ctx flemma.secrets.Context
---@param callback fun(result: flemma.secrets.Result|nil)
local function run_gcloud_async(path, args, env, ctx, callback)
  local opts = { text = true }
  if env then
    opts.env = env
  end
  local cmd = { path }
  vim.list_extend(cmd, args)
  vim.system(cmd, opts, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local stderr = (result.stderr or ""):gsub("%s+$", "")
        if stderr:find("Reauthentication") or stderr:find("refresh") then
          ctx:diagnostic("credentials expired (run `gcloud auth login` to re-authenticate)")
        else
          ctx:diagnostic("auth failed (exit code " .. tostring(result.code) .. "): " .. (stderr:match("[^\n]+") or ""))
        end
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

      -- A service-account key is an Application Default Credential. `gcloud auth
      -- print-access-token` reads only the CLI account store (`gcloud auth login`)
      -- and ignores GOOGLE_APPLICATION_CREDENTIALS, so we must use the
      -- `application-default` subcommand to mint a token from the key file.
      run_gcloud_async(
        path,
        { "auth", "application-default", "print-access-token", "--scopes=" .. CLOUD_PLATFORM_SCOPE },
        { GOOGLE_APPLICATION_CREDENTIALS = tmp },
        ctx,
        function(result)
          os.remove(tmp)
          if result then
            log.debug("gcloud: generated access token from service account (async)")
          end
          callback(result)
        end
      )
      return
    end

    log.debug("gcloud: trying default credentials (async)")
    run_gcloud_async(path, { "auth", "print-access-token" }, nil, ctx, callback)
  end)
end

return M
