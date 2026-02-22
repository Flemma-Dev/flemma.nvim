--- Bubblewrap sandbox backend
--- Translates a resolved sandbox policy into bwrap command-line arguments
---@class flemma.sandbox.backends.Bwrap
local M = {}

--- Validate that bwrap is available on this platform
---@param backend_config flemma.config.BwrapBackendConfig
---@return boolean ok, string|nil error
function M.available(backend_config)
  if vim.fn.has("linux") ~= 1 then
    return false,
      "Bubblewrap sandbox requires Linux (user namespaces). " .. "No sandbox backend is available for this platform."
  end

  local bwrap = backend_config.path or "bwrap"
  if vim.fn.executable(bwrap) ~= 1 then
    return false,
      "bubblewrap (bwrap) not found at '"
        .. bwrap
        .. "'. Install it (e.g. apt install bubblewrap) or set sandbox.backends.bwrap.path."
  end

  return true, nil
end

--- Translate a resolved sandbox policy into a bwrap-wrapped command
---@param policy flemma.config.SandboxPolicy rw_paths are pre-resolved absolutes
---@param backend_config flemma.config.BwrapBackendConfig
---@param inner_cmd string[]
---@return string[]|nil args, string|nil error
function M.wrap(policy, backend_config, inner_cmd)
  local ok, err = M.available(backend_config)
  if not ok then
    return nil, err
  end

  local bwrap = backend_config.path or "bwrap"
  local args = { bwrap }

  -- Entire rootfs read-only
  vim.list_extend(args, { "--ro-bind", "/", "/" })

  -- RW: paths from resolved policy (already absolute and deduplicated)
  for _, path in ipairs(policy.rw_paths or {}) do
    vim.list_extend(args, { "--bind", path, path })
  end

  -- Essentials for tools (Python, Node, etc.)
  vim.list_extend(args, { "--dev", "/dev" })
  vim.list_extend(args, { "--proc", "/proc" })
  vim.list_extend(args, { "--tmpfs", "/run" })

  -- NixOS: /run/current-system holds symlinks to all system packages.
  -- The tmpfs above hides it, so re-bind it read-only on top.
  if vim.uv.fs_stat("/run/current-system") then
    vim.list_extend(args, { "--ro-bind", "/run/current-system", "/run/current-system" })
  end

  -- Capabilities / privilege isolation
  if policy.allow_privileged ~= true then
    table.insert(args, "--unshare-user")
  end

  -- Namespace isolation (always)
  vim.list_extend(args, { "--unshare-pid", "--unshare-uts", "--unshare-ipc" })

  -- Network
  if policy.network == false then
    table.insert(args, "--unshare-net")
  else
    table.insert(args, "--share-net")
  end

  -- Lifecycle safety
  vim.list_extend(args, { "--die-with-parent", "--new-session" })

  -- Power-user escape hatch
  if backend_config.extra_args then
    vim.list_extend(args, backend_config.extra_args)
  end

  -- Append the inner command
  vim.list_extend(args, inner_cmd)

  return args, nil
end

return M
