--- Tool result store — durable materialization of tool output.
---
--- Owns path resolution (preset expansion + template rendering), ID escaping,
--- namespace collapse, file writes with pluggable backup strategies, and
--- store-directory derivation. Replaces $TMPDIR truncation-overflow paths
--- with co-located durable storage.
---@class flemma.tools.Store
local M = {}

local context_module = require("flemma.context")
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

return M
