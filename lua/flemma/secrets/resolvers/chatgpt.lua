---@class flemma.secrets.resolvers.ChatGPT : flemma.secrets.Resolver
--- Resolves ChatGPT subscription credentials from the Codex CLI's auth file.
--- Reads ~/.codex/auth.json (or $CODEX_HOME/auth.json) and extracts the
--- OAuth access token and account ID.
local M = {}

local json = require("flemma.utilities.json")
local log = require("flemma.logging")

M.name = "chatgpt"
M.priority = 50

local CODEX_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
local TOKEN_ENDPOINT = "https://auth.openai.com/oauth/token"

---@param ctx flemma.secrets.Context
---@return string
local function get_auth_file_path(ctx)
  local cfg = ctx:get_config()
  if cfg and cfg.auth_file then
    return cfg.auth_file
  end
  local codex_home = os.getenv("CODEX_HOME")
  if codex_home and codex_home ~= "" then
    return codex_home .. "/auth.json"
  end
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
  return home .. "/.codex/auth.json"
end

---@param path string
---@return table|nil data, string|nil error
local function read_auth_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil, "file not found"
  end
  local content = file:read("*a")
  file:close()
  if not content or #content == 0 then
    return nil, "file is empty"
  end
  local ok, data = pcall(json.decode, content)
  if not ok or type(data) ~= "table" then
    return nil, "invalid JSON"
  end
  return data, nil
end

---@param expires_at number|nil
---@return integer
local function compute_ttl(expires_at)
  if not expires_at or type(expires_at) ~= "number" then
    return 300
  end
  local remaining = expires_at - os.time()
  if remaining <= 0 then
    return 0
  end
  return math.max(60, math.floor(remaining * 0.9))
end

---@param _self flemma.secrets.resolvers.ChatGPT
---@param credential flemma.secrets.Credential
---@param ctx flemma.secrets.Context
---@return boolean
function M.supports(_self, credential, ctx)
  if credential.kind ~= "chatgpt_subscription" then
    ctx:diagnostic("only resolves chatgpt_subscription credentials")
    return false
  end
  local path = get_auth_file_path(ctx)
  local data, err = read_auth_file(path)
  if not data then
    ctx:diagnostic(
      "ChatGPT credentials not found at "
        .. path
        .. " — run `codex login` to authenticate with your ChatGPT subscription"
        .. (err and " (" .. err .. ")" or "")
    )
    return false
  end
  if data.auth_mode ~= "chatgpt" then
    ctx:diagnostic(
      "Codex is configured for "
        .. tostring(data.auth_mode)
        .. " mode, not ChatGPT subscription — run `codex login` and choose 'Sign in with ChatGPT'"
    )
    return false
  end
  if not data.tokens or type(data.tokens) ~= "table" then
    ctx:diagnostic("ChatGPT credentials incomplete — run `codex login` to re-authenticate")
    return false
  end
  return true
end

---@param path string
---@param original_data table
---@param new_tokens table
local function write_auth_file(path, original_data, new_tokens)
  local updated = vim.deepcopy(original_data)
  updated.tokens = vim.tbl_extend("force", updated.tokens, new_tokens)
  local file = io.open(path, "w")
  if file then
    file:write(json.encode(updated))
    file:close()
    log.debug("chatgpt: wrote refreshed tokens to " .. path)
  else
    log.warn("chatgpt: could not write refreshed tokens to " .. path)
  end
end

---@param refresh_token string
---@param auth_file_path string
---@param original_data table
---@param ctx flemma.secrets.Context
---@param callback fun(result: flemma.secrets.Result|nil)
local function refresh_token_async(refresh_token, auth_file_path, original_data, ctx, callback)
  local body = "grant_type=refresh_token" .. "&refresh_token=" .. refresh_token .. "&client_id=" .. CODEX_CLIENT_ID

  vim.system({
    "curl",
    "-s",
    "-X",
    "POST",
    TOKEN_ENDPOINT,
    "-H",
    "Content-Type: application/x-www-form-urlencoded",
    "-d",
    body,
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        ctx:diagnostic(
          "ChatGPT token refresh failed (curl exit code "
            .. tostring(result.code)
            .. ") — run `codex login` to re-authenticate"
        )
        callback(nil)
        return
      end
      local ok, data = pcall(json.decode, result.stdout or "")
      if not ok or type(data) ~= "table" then
        ctx:diagnostic("ChatGPT token refresh returned invalid response — run `codex login` to re-authenticate")
        callback(nil)
        return
      end
      if data.error then
        ctx:diagnostic(
          "ChatGPT token refresh failed: "
            .. tostring(data.error_description or data.error)
            .. " — run `codex login` to re-authenticate"
        )
        callback(nil)
        return
      end
      local new_access = data.access_token
      if not new_access or new_access == "" then
        ctx:diagnostic("ChatGPT token refresh returned empty access token — run `codex login` to re-authenticate")
        callback(nil)
        return
      end

      local new_tokens = {
        access_token = new_access,
      }
      if data.refresh_token then
        new_tokens.refresh_token = data.refresh_token
      end
      if data.expires_in then
        new_tokens.expires_at = os.time() + data.expires_in
      end

      write_auth_file(auth_file_path, original_data, new_tokens)

      local account_id = original_data.tokens and original_data.tokens.account_id
      callback({
        value = new_access,
        ttl = data.expires_in and math.max(60, math.floor(data.expires_in * 0.9)) or 3500,
        metadata = account_id and { account_id = account_id } or nil,
      })
      log.debug("chatgpt: refreshed access token successfully")
    end)
  end)
end

---@param _self flemma.secrets.resolvers.ChatGPT
---@param _credential flemma.secrets.Credential
---@param ctx flemma.secrets.Context
---@param callback fun(result: flemma.secrets.Result|nil)
function M.resolve_async(_self, _credential, ctx, callback)
  local path = get_auth_file_path(ctx)
  local data, err = read_auth_file(path)
  if not data then
    ctx:diagnostic("could not read " .. path .. ": " .. (err or "unknown error") .. " — check file permissions")
    callback(nil)
    return
  end

  if data.auth_mode ~= "chatgpt" then
    ctx:diagnostic(
      "Codex is configured for "
        .. tostring(data.auth_mode)
        .. " mode, not ChatGPT subscription — run `codex login` and choose 'Sign in with ChatGPT'"
    )
    callback(nil)
    return
  end

  local tokens = data.tokens
  if not tokens or not tokens.access_token then
    ctx:diagnostic("ChatGPT credentials incomplete — run `codex login` to re-authenticate")
    callback(nil)
    return
  end

  local ttl = compute_ttl(tokens.expires_at)

  if ttl > 0 then
    callback({
      value = tokens.access_token,
      ttl = ttl,
      metadata = tokens.account_id and { account_id = tokens.account_id } or nil,
    })
    log.debug("chatgpt: resolved access token (TTL " .. tostring(ttl) .. "s)")
    return
  end

  if tokens.refresh_token then
    log.debug("chatgpt: access token expired, attempting refresh")
    refresh_token_async(tokens.refresh_token, path, data, ctx, callback)
  else
    ctx:diagnostic("ChatGPT session expired (no refresh token) — run `codex login` to refresh")
    callback(nil)
  end
end

return M
