--- Tool result store — durable materialization of tool output.
---
--- Owns path resolution (preset expansion + template rendering), ID escaping,
--- namespace collapse, file writes with pluggable backup strategies, and
--- store-directory derivation. Replaces $TMPDIR truncation-overflow paths
--- with co-located durable storage.
---@class flemma.tools.Store
local M = {}

local base_truncate = require("flemma.utilities.truncate")
local config_facade = require("flemma.config")
local context_module = require("flemma.context")
local json = require("flemma.utilities.json")
local loader = require("flemma.loader")
local path_util = require("flemma.utilities.path")
local renderer = require("flemma.templating.renderer")
local sandbox_module = require("flemma.sandbox")
local templating = require("flemma.templating")
local tool_names = require("flemma.utilities.tools")
local variables = require("flemma.utilities.variables")

---Escape a tool/job ID for use in filenames.
---Any character outside [A-Za-z0-9._-] becomes `--` (double dash).
---Double underscore (`__`) from wire-encoded tool names is preserved.
---@param id string
---@return string
function M.escape_id(id)
  return (id:gsub("[^A-Za-z0-9._%-]", "--"))
end

---Collapse consecutive occurrences of a tool name within a single path segment.
---When a segment contains `{name}{sep}{name}` (same name repeated with a
---non-alphanumeric separator, at a word boundary), the separator + second
---occurrence are removed. Repeats to fixed point.
---@param segment string A single path component (no slashes)
---@param wire_name string Wire-encoded tool name to de-duplicate
---@return string
function M.deduplicate_name_in_segment(segment, wire_name)
  if wire_name == "" then
    return segment
  end
  local pattern = vim.pesc(wire_name) .. "([^%w])" .. vim.pesc(wire_name)
  local prev
  repeat
    prev = segment
    local start, finish = segment:find(pattern)
    if start then
      local before_ok = start == 1 or not segment:sub(start - 1, start - 1):match("%w")
      local after = finish + 1
      local after_ok = after > #segment or not segment:sub(after, after):match("%w")
      if before_ok and after_ok then
        segment = segment:sub(1, start + #wire_name - 1) .. segment:sub(finish + 1)
      else
        break
      end
    end
  until segment == prev
  return segment
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
  ["$chat"] = "{{ __dirname }}/.flemma/{{ flemma.path.basename(__filename) }}/{{ source }}_{{ name }}_{{ id }}.txt",
  ["$state"] = "${XDG_STATE_HOME:-$HOME/.flemma}/flemma/store/{{ flemma.path.flatten(__filename) }}/{{ source }}_{{ name }}_{{ id }}.txt",
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
  env.name = tool_names.encode_tool_name(opts.name or "")
  env.id = M.escape_id(opts.id or "")
  if opts.bufnr then
    env.bufnr = opts.bufnr
  end
  env.flemma = { path = path_util, pid = vim.fn.getpid() }
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

---Render a format string: Lua template expansion → variable expansion → resolve →
---namespace collapse → per-segment name de-duplication.
---@param format_str string
---@param env table
---@return string
local function render_format(format_str, env)
  local parts, diagnostics = renderer.render(format_str, env)
  if #diagnostics > 0 then
    local messages = {}
    for _, diagnostic in ipairs(diagnostics) do
      messages[#messages + 1] = diagnostic.error or "unknown error"
    end
    error(("Invalid store path format '%s': %s"):format(format_str, table.concat(messages, "; ")))
  end
  local expanded = renderer.parts_to_text(parts)
  expanded = variables.expand_inline(expanded)
  expanded = path_util.resolve(expanded)
  expanded = M.collapse_namespace(expanded)
  local wire_name = env.name
  if wire_name and wire_name ~= "" then
    local segments = vim.split(expanded, "/", { plain = true })
    for i, seg in ipairs(segments) do
      segments[i] = M.deduplicate_name_in_segment(seg, wire_name)
    end
    expanded = table.concat(segments, "/")
  end
  return expanded
end

---@class flemma.tools.store.ResolveOpts
---@field __filename string|nil Chat file path (nil for unnamed buffers)
---@field __dirname string|nil Chat file directory (nil for unnamed buffers)
---@field source string "tool" or "job"
---@field name? string Tool name (dots → __ wire encoding; de-duplicated from ID)
---@field id string Tool/job ID (will be escaped)
---@field path_format? string Override config (default: "$chat")
---@field unnamed_path_format? string Override config for unnamed buffers
---@field bufnr? integer Buffer number (required for unnamed buffers)

---Resolve the store file path for a tool/job result.
---@param opts flemma.tools.store.ResolveOpts
---@return string path Absolute path to the store file
local function resolve_path(opts)
  local format_str
  if not opts.__filename or opts.__filename == "" then
    -- {{ flemma.pid }} keeps the path process-unique: buffer numbers restart
    -- per Neovim instance, and concurrent instances share ${TMPDIR:-/tmp}.
    format_str = opts.unnamed_path_format
      or "${TMPDIR:-/tmp}/flemma/unnamed/{{ flemma.pid }}/{{ bufnr }}/{{ source }}_{{ name }}_{{ id }}.txt"
    if format_str:match("^%$%w+$") then
      error("Presets are not supported in unnamed_path_format (no chat file path to derive from)")
    end
  else
    format_str = expand_preset(opts.path_format or "$chat")
  end
  local env = build_env(opts)
  return render_format(format_str, env)
end

---Get the store directory path from explicit options.
---@param opts flemma.tools.store.ResolveOpts
---@return string path Absolute path to the store directory
function M.get_store_path(opts)
  return path_util.dirname(resolve_path(opts))
end

---Get the store directory path for a buffer, creating it if it does not exist.
---@param bufnr integer
---@return string path
function M.ensure_buffer_store_path(bufnr)
  local path = M.get_buffer_store_path(bufnr)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
  return path
end

---Get the store directory path for a buffer using its config.
---@param bufnr integer
---@return string path
function M.get_buffer_store_path(bufnr)
  local config = config_facade.materialize(bufnr)
  local store_config = config.tools and config.tools.store or {}
  local buffer_ctx = context_module.from_buffer(bufnr)
  return M.get_store_path({
    __filename = buffer_ctx:get_filename(),
    __dirname = buffer_ctx:get_dirname(),
    source = "tool",
    id = "_",
    path_format = store_config.path_format or "$chat",
    unnamed_path_format = store_config.unnamed_path_format,
    bufnr = bufnr,
  })
end

---Built-in backup strategy names, resolved from `tools/store/backups/`.
---@type string[]
local BUILTIN_BACKUP_STRATEGIES = { "version" }

local BUILTIN_BACKUP_NAMESPACE = "flemma.tools.store.backups."

---Resolve a backup strategy by name, mirroring sandbox backend resolution:
---naked names select built-in strategies from `tools/store/backups/`; module
---paths (dot-notation) load user strategies via the flemma loader.
---@param name string|false Strategy name, module path, or false to disable
---@return { backup: fun(path: string): boolean, string|nil }|nil
local function resolve_backup(name)
  if name == false then
    return nil
  end
  ---@cast name string
  if loader.is_module_path(name) then
    local mod = loader.load(name)
    if type(mod.backup) ~= "function" then
      error(string.format("flemma: module '%s' must export a 'backup' function (expected backup strategy)", name))
    end
    return mod
  end
  if vim.tbl_contains(BUILTIN_BACKUP_STRATEGIES, name) then
    return loader.load(BUILTIN_BACKUP_NAMESPACE .. name)
  end
  error(("Unknown backup strategy '%s' (known: %s)"):format(name, table.concat(BUILTIN_BACKUP_STRATEGIES, ", ")))
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
        -- A failed backup must not clobber the existing file; the new
        -- content survives in the buffer, the old version on disk.
        return nil, ("Backup failed for '%s': %s"):format(path, backup_err or "unknown")
      end
    end
  end

  local f = io.open(path, "w")
  if not f then
    return nil, ("Failed to open '%s' for writing"):format(path)
  end
  local write_ok, write_err = f:write(content)
  local close_ok, close_err = f:close()
  if not write_ok then
    return nil, ("Failed to write '%s': %s"):format(path, tostring(write_err))
  end
  if not close_ok then
    return nil, ("Failed to write '%s': %s"):format(path, tostring(close_err))
  end
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

  local path = resolve_path(opts)
  return M.write(path, opts.content, { backup = opts.backup })
end

---@class flemma.tools.store.CompletionOpts
---@field bufnr integer
---@field __filename string|nil
---@field __dirname string|nil
---@field tool_name? string Tool name (e.g., "bash", "flemma.jobs.status")
---@field tool_id string
---@field source string "tool" or "job"
---@field result flemma.tools.ExecutionResult
---@field store_config table Materialized tools.store config subtree

---Materialize a tool result at completion time.
---Called from the executor before buffer injection.
---@param opts flemma.tools.store.CompletionOpts
---@return string|nil path
---@return string|nil error
function M.materialize_for_completion(opts)
  local store_config = opts.store_config
  if store_config.materialize == false then
    return nil, nil
  end

  local result = opts.result
  local content ---@type string
  if result.error then
    content = result.error --[[@as string]]
    if result.output and result.output ~= "" then
      content = content .. "\n\nPartial output:\n" .. tostring(result.output)
    end
  elseif type(result.output) == "table" then
    content = json.encode(result.output)
  else
    content = tostring(result.output or "")
  end

  -- Config errors (unknown preset, unknown backup strategy) must degrade to
  -- a returned error: this runs after the tool, and a raise here would strand
  -- the buffer before injection.
  local ok, path, write_err = pcall(M.materialize, {
    __filename = opts.__filename,
    __dirname = opts.__dirname,
    source = opts.source,
    name = opts.tool_name,
    id = opts.tool_id,
    path_format = store_config.path_format,
    unnamed_path_format = store_config.unnamed_path_format,
    bufnr = opts.bufnr,
    content = content,
    materialize_enabled = true,
    truncated = false,
    backup = store_config.backup,
  })
  if not ok then
    return nil, tostring(path)
  end
  return path, --[[@as string|nil]]
    write_err --[[@as string|nil]]
end

-- ---------------------------------------------------------------------------
-- Redirect (flemma.save_to)
-- ---------------------------------------------------------------------------

---@type string|nil
local store_cwd = nil

---Capture a pcall result list without truncating interior nils.
---@param ok boolean
---@param ... any
---@return boolean ok, integer count, table results
local function capture_call(ok, ...)
  return ok, select("#", ...), { ... }
end

---Run a function with $FLEMMA_TOOLS_STORE_PATH set to the given directory.
---The variable is restored to its previous value after the function returns
---(even on error). All callback return values are propagated, including
---nils in `value, err` tuples.
---@param cwd string Store directory for inline variable expansion
---@param fn fun(): ...
---@return any ...
function M.with_cwd(cwd, fn)
  local prev = store_cwd
  store_cwd = cwd
  local ok, count, results = capture_call(pcall(fn))
  store_cwd = prev
  if not ok then
    error(results[1], 2)
  end
  return unpack(results, 1, count)
end

---Register $FLEMMA_TOOLS_STORE_PATH as a flemma-resolved inline variable.
function M.register_variable()
  variables.register_inline("FLEMMA_TOOLS_STORE_PATH", function()
    return store_cwd
  end)
end

---Build a redirect stub with preview for buffer injection.
---@param content string Full tool output
---@param dest_path string Resolved destination path
---@param preview_config { lines: number, bytes: number }
---@return string stub_content
function M.build_redirect_stub(content, dest_path, preview_config)
  local lines = {}

  if preview_config.lines > 0 then
    local preview = base_truncate.truncate_head(content, {
      max_lines = preview_config.lines,
      max_bytes = preview_config.bytes,
    })
    for _, line in ipairs(vim.split(preview.content, "\n", { plain = true })) do
      lines[#lines + 1] = line
    end
    lines[#lines + 1] = ""
  end

  local size = base_truncate.format_size(#content)
  local line_count = select(2, content:gsub("\n", "")) + 1
  lines[#lines + 1] = ("[Output saved: %s — %s, %d lines]"):format(dest_path, size, line_count)

  return table.concat(lines, "\n")
end

---@class flemma.tools.store.RedirectOpts
---@field save_to string Raw save_to value from tool input
---@field content string Full tool output
---@field chat_dirname string|nil Chat file directory for relative path resolution
---@field bufnr integer Buffer number
---@field preview { lines: number, bytes: number }
---@field backup string|false Backup strategy name

---Execute a redirect: resolve destination, write content, return stub.
---@param opts flemma.tools.store.RedirectOpts
---@return string|nil stub_content
---@return string|nil error
function M.execute_redirect(opts)
  local dest = opts.save_to
  dest = variables.expand_inline(dest)
  dest = path_util.resolve(dest, opts.chat_dirname)

  -- The store directory is created lazily, so isdirectory() cannot see it
  -- yet; a destination equal to it (or an ancestor of it) would occupy a
  -- path mkdir later needs as a directory. Compare resolved paths instead.
  local store_dir = store_cwd ~= nil and path_util.resolve(store_cwd) or nil
  local occludes_store = store_dir ~= nil
    and (dest == store_dir or (vim.startswith(store_dir, dest) and store_dir:sub(#dest + 1, #dest + 1) == "/"))

  if occludes_store or vim.fn.isdirectory(dest) == 1 or dest:sub(-1) == "/" then
    return nil, ("save_to target '%s' is a directory — append a filename"):format(dest)
  end

  if sandbox_module.is_enabled(opts.bufnr) then
    if not sandbox_module.is_path_writable(dest, opts.bufnr) then
      return nil, ("save_to destination '%s' is not writable under sandbox policy"):format(dest)
    end
  end

  local written, write_err = M.write(dest, opts.content, { backup = opts.backup })
  if not written then
    return nil, write_err
  end

  local stub = M.build_redirect_stub(opts.content, dest, opts.preview)
  return stub, nil
end

---@class flemma.tools.store.ApplyRedirectOpts
---@field save_to string Raw flemma.save_to value from the tool input
---@field result flemma.tools.ExecutionResult Captured tool result (success only)
---@field bufnr integer
---@field store_config table Materialized tools.store config subtree

---Apply a flemma.save_to redirect to a captured execution result.
---On success the output is replaced by the stub; on failure the full output
---is kept with a model-facing notice appended, so content is never lost.
---The notice speaks plain filesystem language — the model knows the
---save_to value it chose, not the machinery behind it.
---@param opts flemma.tools.store.ApplyRedirectOpts
---@return flemma.tools.ExecutionResult result Replacement execution result
---@return string|nil error Redirect error (already reflected in the result)
function M.apply_redirect(opts)
  local result = opts.result
  local content = type(result.output) == "table" and json.encode(result.output) or tostring(result.output or "")
  local buffer_ctx = context_module.from_buffer(opts.bufnr)
  local store_config = opts.store_config

  -- Config errors (unknown preset, unknown backup strategy) must degrade to
  -- the inline-fallback notice: this runs after the tool, and a raise here
  -- would strand the buffer before injection.
  local call_ok, stub, redirect_err = pcall(function()
    return M.with_cwd(M.get_buffer_store_path(opts.bufnr), function()
      return M.execute_redirect({
        save_to = opts.save_to,
        content = content,
        chat_dirname = buffer_ctx:get_dirname(),
        bufnr = opts.bufnr,
        preview = store_config.preview or { lines = 10, bytes = 2048 },
        backup = store_config.backup,
      })
    end)
  end)
  if not call_ok then
    redirect_err = tostring(stub)
    stub = nil
  end

  if stub then
    return { success = true, output = stub }, nil
  end

  local notice = ("[Output not saved: %s. Showing the full output instead.]"):format(redirect_err or "unknown error")
  return { success = true, output = content .. "\n\n" .. notice }, redirect_err
end

-- Register $FLEMMA_TOOLS_STORE_PATH for inline expansion at load time
M.register_variable()

-- Register urn:flemma:store for sandbox rw_paths auto-grant
variables.register("urn:flemma:store", function(context)
  local bufnr = context and context.bufnr
  if not bufnr then
    return nil
  end
  local ok, dir = pcall(M.get_buffer_store_path, bufnr)
  if ok and dir then
    return dir
  end
  return nil
end)

return M
