--- Tool result store — durable materialization of tool output.
---
--- Owns path resolution (preset expansion + template rendering), ID escaping,
--- namespace collapse, file writes with pluggable backup strategies, and
--- store-directory derivation. Replaces $TMPDIR truncation-overflow paths
--- with co-located durable storage.
---@class flemma.tools.Store
local M = {}

local context_module = require("flemma.context")
local loader = require("flemma.loader")
local notify = require("flemma.notify")
local path_util = require("flemma.utilities.path")
local renderer = require("flemma.templating.renderer")
local templating = require("flemma.templating")
local variables = require("flemma.utilities.variables")

---Escape a tool/job ID for use in filenames.
---Any character outside [A-Za-z0-9._-] becomes `--` (double dash).
---Double underscore (`__`) from wire-encoded tool names is preserved.
---@param id string
---@return string
function M.escape_id(id)
  return (id:gsub("[^A-Za-z0-9._%-]", "--"))
end

---Collapse doubled `flemma` namespace segments in a rendered store path.
---Segment-anchored: only collapses when a segment exactly equal to `flemma`
---immediately follows a segment exactly equal to `flemma` or `.flemma`.
---Repeats to fixed point.
---@param path string
---@return string
function M.collapse_namespace(path)
  local segments = vim.split(path, "/", { plain = true })
  local prev
  repeat
    prev = vim.deepcopy(segments)
    local result = {}
    local i = 1
    while i <= #segments do
      local seg = segments[i]
      if seg == "flemma" and i > 1 and (result[#result] == "flemma" or result[#result] == ".flemma") then
        i = i + 1
      else
        result[#result + 1] = seg
        i = i + 1
      end
    end
    segments = result
  until #segments == #prev
  return table.concat(segments, "/")
end

---@type table<string, string>
local PRESETS = {
  ["$chat"] = "{{ __dirname }}/.flemma/{{ flemma.path.basename(__filename) }}/{{ source }}_{{ id }}.txt",
  ["$state"] = "${XDG_STATE_HOME:-$HOME/.flemma}/flemma/store/{{ flemma.path.flatten(__filename) }}/{{ source }}_{{ id }}.txt",
}

---Build the template environment for store path rendering.
---@param opts flemma.tools.store.ResolveOpts
---@return table env
local function build_env(opts)
  local ctx
  if opts.__filename and opts.__filename ~= "" then
    ctx = context_module.from_file(opts.__filename)
  else
    ctx = context_module.from_file("")
  end
  local env = templating.from_context(ctx, opts.bufnr)
  env.source = opts.source or ""
  env.id = M.escape_id(opts.id or "")
  if opts.bufnr then
    env.bufnr = opts.bufnr
  end
  env.flemma = { path = path_util }
  return env
end

---Expand a preset name to its format template.
---@param format string
---@return string
local function expand_preset(format)
  if not format:match("^%$%w+$") then
    return format
  end
  local template = PRESETS[format]
  if not template then
    local known = {}
    for k, _ in pairs(PRESETS) do
      known[#known + 1] = k
    end
    table.sort(known)
    error(("Unknown store preset '%s' (known: %s)"):format(format, table.concat(known, ", ")))
  end
  return template
end

---Render a format string: Lua template expansion → variable expansion → resolve → collapse.
---@param format_str string
---@param env table
---@return string
local function render_format(format_str, env)
  local expanded = renderer.parts_to_text(renderer.render(format_str, env))
  expanded = variables.expand_inline(expanded)
  expanded = path_util.resolve(expanded)
  return M.collapse_namespace(expanded)
end

---@class flemma.tools.store.ResolveOpts
---@field __filename string|nil Chat file path (nil for unsaved buffers)
---@field __dirname string|nil Chat file directory (nil for unsaved buffers)
---@field source string "tool" or "job"
---@field id string Tool/job ID (will be escaped)
---@field path_format? string Override config (default: "$chat")
---@field unsaved_path_format? string Override config for unsaved buffers
---@field bufnr? integer Buffer number (required for unsaved buffers)

---Resolve the store file path for a tool/job result.
---@param opts flemma.tools.store.ResolveOpts
---@return string path Absolute path to the store file
function M.resolve_path(opts)
  local format_str
  if not opts.__filename or opts.__filename == "" then
    format_str = opts.unsaved_path_format or "${TMPDIR:-/tmp}/flemma/unsaved-{{ bufnr }}/{{ source }}_{{ id }}.txt"
    if format_str:match("^%$%w+$") then
      error("Presets are not supported in unsaved_path_format (no chat file path to derive from)")
    end
  else
    format_str = expand_preset(opts.path_format or "$chat")
  end
  local env = build_env(opts)
  return render_format(format_str, env)
end

---Resolve the store directory for a chat buffer.
---@param opts flemma.tools.store.ResolveOpts
---@return string dir Absolute path to the store directory
function M.resolve_dir(opts)
  return path_util.dirname(M.resolve_path(opts))
end

---@type string[]
local BUILTIN_BACKUP_STRATEGIES = {
  "flemma.tools.store.backups.version",
}

---Resolve a backup strategy by name.
---@param name string|false Strategy name or false to disable
---@return { backup: fun(path: string): boolean, string|nil }|nil
local function resolve_backup(name)
  if name == false then
    return nil
  end
  for _, module_path in ipairs(BUILTIN_BACKUP_STRATEGIES) do
    local mod = loader.load(module_path)
    if mod and module_path:match("%.([^.]+)$") == name then
      return mod
    end
  end
  local ok, mod = pcall(loader.load, name)
  if ok and mod then
    return mod
  end
  error(("Unknown backup strategy '%s'"):format(tostring(name)))
end

---Write content to a file, applying backup strategy and creating directories.
---@param path string Absolute path to write
---@param content string Content to write
---@param opts? { backup?: string|false } Backup strategy (default: none for raw writes)
---@return string|nil written_path
---@return string|nil error
function M.write(path, content, opts)
  opts = opts or {}

  local dir = path_util.dirname(path)
  if dir and vim.fn.isdirectory(dir) == 0 then
    local mkdir_ok = pcall(vim.fn.mkdir, dir, "p")
    if not mkdir_ok then
      return nil, ("Failed to create directory '%s'"):format(dir)
    end
  end

  if opts.backup and opts.backup ~= false then
    local strategy = resolve_backup(opts.backup)
    if strategy then
      local backup_ok, backup_err = strategy.backup(path)
      if not backup_ok then
        notify.warn("Store backup failed: " .. (backup_err or "unknown"))
      end
    end
  end

  local f = io.open(path, "w")
  if not f then
    return nil, ("Failed to open '%s' for writing"):format(path)
  end
  f:write(content)
  f:close()
  return path, nil
end

---@class flemma.tools.store.MaterializeOpts : flemma.tools.store.ResolveOpts
---@field content string Full tool output to write
---@field materialize_enabled? boolean Kill-switch (default true)
---@field truncated? boolean Whether the result was truncated
---@field backup? string|false Backup strategy name

---Materialize a tool result to the store.
---Writes full content; returns path on success, nil when skipped or on error.
---@param opts flemma.tools.store.MaterializeOpts
---@return string|nil path
---@return string|nil error
function M.materialize(opts)
  local should_write = opts.materialize_enabled ~= false or opts.truncated == true
  if not should_write then
    return nil, nil
  end

  local path = M.resolve_path(opts)
  return M.write(path, opts.content, { backup = opts.backup })
end

return M
