--- Collects runtime status data from all Flemma subsystems
--- Used by :Flemma status to display current configuration and state
---@class flemma.Status
local M = {}

local config_facade = require("flemma.config")
local normalize = require("flemma.provider.normalize")
local autopilot = require("flemma.autopilot")
local processor = require("flemma.processor")
local sandbox = require("flemma.sandbox")
local state = require("flemma.state")
local str = require("flemma.utilities.string")
local tools_module = require("flemma.tools")
local tools_approval = require("flemma.tools.approval")
local diagnostic_format = require("flemma.utilities.diagnostic")
local registry = require("flemma.provider.registry")

local MARKER_SANDBOX = "⊡"

--- Base code point for the decorative letter block used as source layer icons.
--- Change this single value to switch icon style (e.g. 0x24B6 for circled,
--- 0x1F170 for negative squared, 0x1F150 for negative circled).
local ICON_LETTER_BASE = 0x1F170

---Build a decorative letter from its ASCII uppercase character.
---@param ch string Single uppercase ASCII letter
---@return string
local function icon_letter(ch)
  return vim.fn.nr2char(ICON_LETTER_BASE + string.byte(ch) - string.byte("A"))
end

---Source layer icons for config layer indicators.
---@type table<string, string>
local SOURCE_ICON = {
  D = icon_letter("D"),
  S = icon_letter("S"),
  R = icon_letter("R"),
  F = icon_letter("F"),
}

---Highlight group for each source layer icon.
---@type table<string, string>
local SOURCE_HL = {
  D = "FlemmaStatusSourceDefault",
  S = "FlemmaStatusSourceSetup",
  R = "FlemmaStatusSourceRuntime",
  F = "FlemmaStatusSourceFrontmatter",
}

---Extmark namespace for status buffer highlighting.
local NS = vim.api.nvim_create_namespace("flemma_status")

---Highlight group for each layer op verb.
---@type table<string, string>
local OP_HL = {
  set = "FlemmaStatusOpSet",
  append = "FlemmaStatusOpAppend",
  remove = "FlemmaStatusOpRemove",
  prepend = "FlemmaStatusOpAppend",
}

---@class flemma.status.ShowOptions
---@field verbose? boolean Include layer ops and resolved config tree
---@field jump_to? string Section header to jump cursor to
---@field bufnr? integer Buffer to collect status from (defaults to current)

---@class flemma.status.Data
---@field provider { name: string, model: string|nil, initialized: boolean, model_info: flemma.models.ModelInfo|nil, source: string|nil, model_source: string|nil }
---@field parameters { merged: table<string, any>, sources: table<string, string>, resolved_max_tokens: integer|nil, resolved_thinking: string|nil }
---@field autopilot { enabled: boolean, config_enabled: boolean, buffer_state: string, max_turns: integer, sources: table<string, string> }
---@field sandbox { enabled: boolean, config_enabled: boolean, runtime_override: boolean|nil, backend: string|nil, backend_mode: string|nil, backend_available: boolean, backend_error: string|nil, policy: flemma.config.SandboxPolicy, sources: table<string, string> }
---@field tools { enabled: string[], disabled: string[], booting: boolean, frontmatter_items: table<string, true>|nil, max_concurrent: integer }
---@field approval { approved: string[], denied: string[], pending: string[], require_approval_disabled: boolean, frontmatter_items: table<string, true>|nil, sandbox_items: table<string, true>|nil }
---@field buffer { is_chat: boolean, bufnr: integer }
---@field diagnostics? flemma.ast.Diagnostic[] Frontmatter validation diagnostics
---@field introspection? { layer_ops: { label: string, name: string, ops: table[] }[], resolved: { path: string, value: any, source: string?, depth: integer, is_object: boolean }[] }

---@class flemma.status.FormatResult
---@field lines string[]
---@field extmarks integer[][] Each entry: {line, col_start, col_end, hl_group_idx}
---@field virt_texts { [1]: integer, [2]: [string, string][] }[]

-- ---------------------------------------------------------------------------
-- Collectors
-- ---------------------------------------------------------------------------

---Collect provider section data
---@param config flemma.Config
---@param bufnr integer
---@return { name: string, model: string|nil, initialized: boolean, model_info: flemma.models.ModelInfo|nil, source: string|nil, model_source: string|nil }
local function collect_provider(config, bufnr)
  local model_info = config.model and registry.get_model_info(config.provider, config.model) or nil
  local provider_info = config_facade.inspect(bufnr, "provider")
  local model_info_src = config_facade.inspect(bufnr, "model")
  return {
    name = config.provider,
    model = config.model,
    initialized = config.provider ~= nil and config.provider ~= "",
    model_info = model_info,
    source = provider_info and provider_info.layer or nil,
    model_source = model_info_src and model_info_src.layer or nil,
  }
end

---Collect parameters section data with per-key source tracking.
---@param config flemma.Config
---@param bufnr integer
---@return { merged: table<string, any>, sources: table<string, string>, resolved_max_tokens: integer|nil, resolved_thinking: string|nil }
local function collect_parameters(config, bufnr)
  local base_merged = normalize.flatten_parameters(config.provider, config)

  -- Build source map for each flattened parameter key.
  -- Provider-specific path takes precedence over general path (same as flatten).
  local sources = {}
  local provider_name = config.provider
  for key, _ in pairs(base_merged) do
    if key == "model" then
      local info = config_facade.inspect(bufnr, "model")
      if info and info.layer then
        sources[key] = info.layer
      end
    else
      -- Check provider-specific path first
      local specific = config_facade.inspect(bufnr, "parameters." .. provider_name .. "." .. key)
      if specific and specific.value ~= nil then
        sources[key] = specific.layer
      else
        local general = config_facade.inspect(bufnr, "parameters." .. key)
        if general and general.layer then
          sources[key] = general.layer
        end
      end
    end
  end

  -- Resolve max_tokens on a copy to show the resolved integer alongside the original
  local resolved_max_tokens = nil
  if type(base_merged.max_tokens) == "string" then
    local resolve_copy = { max_tokens = base_merged.max_tokens }
    normalize.resolve_max_tokens(config.provider, config.model or "", resolve_copy)
    resolved_max_tokens = resolve_copy.max_tokens
  end

  -- Resolve thinking to show the provider-facing value alongside the config value
  ---@type string|nil
  local resolved_thinking = nil
  if base_merged.thinking ~= nil then
    local caps = registry.get_capabilities(config.provider)
    local model_info = config.model and registry.get_model_info(config.provider, config.model) or nil
    if caps then
      local resolution = normalize.resolve_thinking(base_merged, caps, model_info)
      if resolution.enabled then
        if resolution.budget then
          resolved_thinking = tostring(resolution.budget) .. " tokens"
        elseif resolution.effort then
          resolved_thinking = resolution.effort
        end
      else
        resolved_thinking = "disabled"
      end
    end
  end

  return {
    merged = base_merged,
    sources = sources,
    resolved_max_tokens = resolved_max_tokens,
    resolved_thinking = resolved_thinking,
  }
end

---Collect autopilot section data
---@param bufnr integer
---@param config flemma.Config
---@return { enabled: boolean, config_enabled: boolean, buffer_state: string, max_turns: integer, sources: table<string, string> }
local function collect_autopilot(bufnr, config)
  local autopilot_config = config.tools and config.tools.autopilot
  local max_turns = (autopilot_config and autopilot_config.max_turns) or 100

  -- Base config value (ignoring frontmatter): mirrors autopilot.is_enabled() without the opts check
  local config_enabled = autopilot_config ~= nil
    and (autopilot_config.enabled == nil or autopilot_config.enabled == true)

  local sources = {}
  local enabled_info = config_facade.inspect(bufnr, "tools.autopilot.enabled")
  if enabled_info and enabled_info.layer then
    sources.status = enabled_info.layer
  end
  local turns_info = config_facade.inspect(bufnr, "tools.autopilot.max_turns")
  if turns_info and turns_info.layer then
    sources.max_turns = turns_info.layer
  end

  return {
    enabled = autopilot.is_enabled(bufnr),
    config_enabled = config_enabled,
    buffer_state = autopilot.get_state(bufnr),
    max_turns = max_turns,
    sources = sources,
  }
end

---Collect sandbox section data
---@param bufnr integer
---@return { enabled: boolean, config_enabled: boolean, runtime_override: boolean|nil, backend: string|nil, backend_mode: string|nil, backend_available: boolean, backend_error: string|nil, policy: flemma.config.SandboxPolicy, sources: table<string, string> }
local function collect_sandbox(bufnr)
  local sandbox_config = sandbox.resolve_config(bufnr)
  local runtime_override = sandbox.get_override()

  local backend_name, backend_error = sandbox.detect_available_backend(bufnr)
  local backend_available, validate_error = sandbox.validate_backend(bufnr)

  local policy = sandbox.get_policy(bufnr)

  local sources = {}
  local enabled_info = config_facade.inspect(bufnr, "sandbox.enabled")
  if enabled_info and enabled_info.layer then
    sources.config_setting = enabled_info.layer
  end
  local backend_info = config_facade.inspect(bufnr, "sandbox.backend")
  if backend_info and backend_info.layer then
    sources.backend = backend_info.layer
  end
  local network_info = config_facade.inspect(bufnr, "sandbox.policy.network")
  if network_info and network_info.layer then
    sources.network = network_info.layer
  end
  local priv_info = config_facade.inspect(bufnr, "sandbox.policy.allow_privileged")
  if priv_info and priv_info.layer then
    sources.privileged = priv_info.layer
  end

  return {
    enabled = sandbox.is_enabled(bufnr),
    config_enabled = sandbox_config.enabled == true,
    runtime_override = runtime_override,
    backend = backend_name,
    backend_mode = sandbox_config.backend,
    backend_available = backend_available,
    backend_error = backend_error or validate_error,
    policy = policy,
    sources = sources,
  }
end

---Collect tools section data, using the config store for source tracking.
---When frontmatter changes the tool list, items that differ from the base
---config are tracked in frontmatter_items for annotation.
---@param bufnr integer
---@return { enabled: string[], disabled: string[], booting: boolean, frontmatter_items: table<string, true>|nil, max_concurrent: integer }
local function collect_tools(bufnr)
  local all_tools = tools_module.get_all({ include_disabled = true })

  -- Get the tools list source from the config store
  local tools_info = config_facade.inspect(bufnr, "tools")
  local tools_list = tools_info and tools_info.value
  local tools_source = tools_info and tools_info.layer
  local frontmatter_modified = tools_source and tools_source:find("F") ~= nil

  local enabled = {}
  local disabled = {}
  local frontmatter_items = {}

  if frontmatter_modified and type(tools_list) == "table" and #tools_list > 0 then
    -- Frontmatter modified the tools list — filter by it and detect diffs
    local allowed_set = {}
    for _, name in ipairs(tools_list) do
      allowed_set[name] = true
    end

    -- Get the base tool list (without frontmatter) for diff detection
    local base_info = config_facade.inspect(nil, "tools")
    local base_set = {}
    if base_info and type(base_info.value) == "table" then
      for _, name in ipairs(base_info.value) do
        base_set[name] = true
      end
    else
      for name, definition in pairs(all_tools) do
        if definition.enabled ~= false then
          base_set[name] = true
        end
      end
    end

    for name, _ in pairs(all_tools) do
      if allowed_set[name] then
        table.insert(enabled, name)
        if not base_set[name] then
          frontmatter_items[name] = true
        end
      else
        table.insert(disabled, name)
        if base_set[name] then
          frontmatter_items[name] = true
        end
      end
    end
  else
    -- No frontmatter modification — use registry enabled status
    for name, definition in pairs(all_tools) do
      if definition.enabled ~= false then
        table.insert(enabled, name)
      else
        table.insert(disabled, name)
      end
    end
  end

  table.sort(enabled)
  table.sort(disabled)

  local mc_info = config_facade.inspect(bufnr, "tools.max_concurrent")
  local max_concurrent = (mc_info and mc_info.value) or 2

  return {
    enabled = enabled,
    disabled = disabled,
    booting = not tools_module.is_ready(),
    frontmatter_items = next(frontmatter_items) and frontmatter_items or nil,
    max_concurrent = max_concurrent,
  }
end

---Map an ApprovalResult to the bucket key used by collect_approval.
local RESULT_TO_BUCKET = {
  approve = "approved",
  deny = "denied",
  require_approval = "pending",
}

---Resolve approval for a tool via the resolver chain, returning the bucket and source.
---@param tool_name string
---@param bufnr integer
---@return "approved"|"denied"|"pending" bucket
---@return string source Resolver name that made the decision
local function resolve_tool_approval(tool_name, bufnr)
  local result, source = tools_approval.resolve_with_source(tool_name, {}, { bufnr = bufnr, tool_id = "" })
  return RESULT_TO_BUCKET[result] or "pending", source
end

---Collect tool approval section data by running each tool through the approval
---resolver chain — the same code path used at tool-execution time.
---@param config flemma.Config Materialized config (from collect)
---@param bufnr integer Buffer number for resolver context
---@param enabled_tools string[] Sorted list of enabled tool names
---@return { approved: string[], denied: string[], pending: string[], require_approval_disabled: boolean, frontmatter_items: table<string, true>|nil, sandbox_items: table<string, true>|nil }
local function collect_approval(config, bufnr, enabled_tools)
  local tools_config = config.tools
  local require_approval_disabled = tools_config ~= nil and tools_config.require_approval == false

  -- Classify each tool through the resolver chain
  local approved = {}
  local denied = {}
  local pending = {}
  local sandbox_items = {}

  for _, name in ipairs(enabled_tools) do
    local bucket, resolver_source = resolve_tool_approval(name, bufnr)
    if bucket == "denied" then
      table.insert(denied, name)
    elseif bucket == "approved" then
      table.insert(approved, name)
    else
      table.insert(pending, name)
    end

    -- Track sandbox-sourced approvals
    if resolver_source == "urn:flemma:approval:sandbox" then
      sandbox_items[name] = true
    end
  end

  -- Per-tool frontmatter attribution: only mark tools that frontmatter
  -- actually contributed. A "set" op means frontmatter owns the entire list;
  -- otherwise check individual "append"/"prepend" ops per tool.
  local fm_layer = config_facade.LAYERS.FRONTMATTER
  local frontmatter_items = {}
  if config_facade.layer_has_set(fm_layer, bufnr, "tools.auto_approve") then
    -- Frontmatter replaced the entire list — all approved tools are frontmatter-determined
    for _, name in ipairs(approved) do
      if not sandbox_items[name] then
        frontmatter_items[name] = true
      end
    end
  else
    for _, name in ipairs(approved) do
      if
        config_facade.layer_has_op(fm_layer, bufnr, "append", "tools.auto_approve", name)
        or config_facade.layer_has_op(fm_layer, bufnr, "prepend", "tools.auto_approve", name)
      then
        frontmatter_items[name] = true
      end
    end
  end

  ---@type table<string, true>|nil
  local frontmatter_result = nil
  if next(frontmatter_items) then
    frontmatter_result = frontmatter_items
  end
  ---@type table<string, true>|nil
  local sandbox_result = nil
  if next(sandbox_items) then
    sandbox_result = sandbox_items
  end

  return {
    approved = approved,
    denied = denied,
    pending = pending,
    require_approval_disabled = require_approval_disabled,
    frontmatter_items = frontmatter_result,
    sandbox_items = sandbox_result,
  }
end

---Collect introspection data for the verbose view.
---Returns raw layer ops and the resolved config tree with source annotations.
---@param bufnr integer
---@return { layer_ops: { label: string, name: string, ops: table[] }[], resolved: { path: string, value: any, source: string?, depth: integer, is_object: boolean }[] }
local function collect_introspection(bufnr)
  local LAYERS = config_facade.LAYERS
  local layer_ops = {}

  ---@type { label: string, num: integer, name: string }[]
  local layer_info = {
    { label = "D", num = LAYERS.DEFAULTS, name = "defaults" },
    { label = "S", num = LAYERS.SETUP, name = "setup" },
    { label = "R", num = LAYERS.RUNTIME, name = "runtime" },
    { label = "F", num = LAYERS.FRONTMATTER, name = "frontmatter" },
  }

  for _, info in ipairs(layer_info) do
    local ops
    if info.num == LAYERS.FRONTMATTER then
      ops = config_facade.dump_layer(info.num, bufnr)
    else
      ops = config_facade.dump_layer(info.num)
    end
    table.insert(layer_ops, {
      label = info.label,
      name = info.name,
      ops = ops,
    })
  end

  local resolved = config_facade.dump_resolved(bufnr)

  return {
    layer_ops = layer_ops,
    resolved = resolved,
  }
end

-- ---------------------------------------------------------------------------
-- Builder — produces lines + extmark data for the status display
-- ---------------------------------------------------------------------------

---@class flemma.status.Builder
---@field lines string[]
---@field extmarks { [1]: integer, [2]: integer, [3]: integer, [4]: string }[]
---@field virt_texts { [1]: integer, [2]: [string, string][] }[]
---@field _cur string
---@field _marks { col_start: integer, col_end: integer, hl_group: string }[]
---@field _virt [string, string][]|nil
---@field _depth boolean[]
---@field _line integer
local Builder = {}
Builder.__index = Builder

---@return flemma.status.Builder
local function new_builder()
  return setmetatable({
    lines = {},
    extmarks = {},
    virt_texts = {},
    _cur = "",
    _marks = {},
    _virt = nil,
    _depth = {},
    _line = 0,
  }, Builder)
end

---Append text to the current line, optionally highlighted.
---@param text string
---@param hl_group? string
function Builder:put(text, hl_group)
  local start = #self._cur
  self._cur = self._cur .. text
  if hl_group then
    table.insert(self._marks, { col_start = start, col_end = start + #text, hl_group = hl_group })
  end
end

---Set right-aligned virtual text for the current line.
---@param chunks [string, string][]
function Builder:virt(chunks)
  self._virt = chunks
end

---Flush the current line to output.
function Builder:nl()
  table.insert(self.lines, self._cur)
  for _, m in ipairs(self._marks) do
    table.insert(self.extmarks, { self._line, m.col_start, m.col_end, m.hl_group })
  end
  if self._virt then
    table.insert(self.virt_texts, { self._line, self._virt })
    self._virt = nil
  end
  self._line = self._line + 1
  self._cur = ""
  self._marks = {}
end

---Emit an empty line.
function Builder:blank()
  self:nl()
end

---Compute the tree prefix string for the current depth.
---@param is_last boolean
---@return string
function Builder:_prefix(is_last)
  local parts = {}
  for i = 1, #self._depth do
    if self._depth[i] then
      table.insert(parts, "   ")
    else
      table.insert(parts, "│  ")
    end
  end
  table.insert(parts, is_last and "└─ " or "├─ ")
  return table.concat(parts)
end

---Compute a continuation prefix (vertical lines only, no branch marker).
---@return string
function Builder:_cont()
  local parts = {}
  for i = 1, #self._depth do
    if self._depth[i] then
      table.insert(parts, "   ")
    else
      table.insert(parts, "│  ")
    end
  end
  return table.concat(parts)
end

---Emit a tree branch prefix and push depth (node has children).
---@param is_last boolean
function Builder:branch(is_last)
  self:put(self:_prefix(is_last), "FlemmaStatusTree")
  table.insert(self._depth, is_last)
end

---Pop one level of tree depth.
function Builder:unbranch()
  table.remove(self._depth)
end

---Emit a tree leaf prefix (no depth push — node has no children).
---@param is_last boolean
function Builder:leaf(is_last)
  self:put(self:_prefix(is_last), "FlemmaStatusTree")
end

---Emit a continuation line (just vertical bars for current depth).
function Builder:gap()
  local prefix = self:_cont():gsub("%s+$", "")
  if prefix == "" then
    prefix = "│"
  end
  self:put(prefix, "FlemmaStatusTree")
  self:nl()
end

---Finalize and return the result.
---@return flemma.status.FormatResult
function Builder:build()
  if self._cur ~= "" then
    self:nl()
  end
  return { lines = self.lines, extmarks = self.extmarks, virt_texts = self.virt_texts }
end

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

---Format a scalar or table value as a compact display string
---@param value any
---@return string
local function format_value(value)
  if type(value) == "table" then
    return vim.inspect(value, { newline = " ", indent = "" })
  end
  return tostring(value)
end

---Right-pad a string to the given display width.
---Uses strdisplaywidth to handle multi-byte characters correctly.
---@param text string
---@param width integer
---@return string
local function pad(text, width)
  local display_width = vim.fn.strdisplaywidth(text)
  if display_width >= width then
    return text
  end
  return text .. string.rep(" ", width - display_width)
end

---Compute a key padding width from a list of key strings (max display width + 2 gap).
---@param keys string[]
---@return integer
local function key_width_of(keys)
  local max_w = 0
  for _, k in ipairs(keys) do
    max_w = math.max(max_w, vim.fn.strdisplaywidth(k))
  end
  return max_w + 2
end

---Collapse well-known path prefixes for display: $HOME → ~, $CWD → ./
---@param path string
---@return string
local function collapse_path(path)
  local cwd = vim.fn.getcwd()
  if cwd and #cwd > 0 and path:sub(1, #cwd) == cwd then
    return "." .. path:sub(#cwd + 1)
  end
  local home = vim.env.HOME
  if home and #home > 0 and path:sub(1, #home) == home then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

---Build virtual text chunks for a source layer indicator string (e.g., "D", "S+F").
---@param source string|nil
---@return [string, string][]|nil
local function source_virt_text(source)
  if not source or source == "D" then
    return nil
  end
  local chunks = {}
  for part in source:gmatch("[DSRF]") do
    if #chunks > 0 then
      table.insert(chunks, { " ", "Normal" })
    end
    local icon = SOURCE_ICON[part] or part
    local hl = SOURCE_HL[part] or "Comment"
    table.insert(chunks, { icon, hl })
  end
  if #chunks > 0 then
    table.insert(chunks, { " ", "Normal" })
  end
  return #chunks > 0 and chunks or nil
end

---Build virtual text chunks for tool markers (frontmatter/sandbox).
---@param name string
---@param frontmatter_items table<string, true>|nil
---@param sandbox_items table<string, true>|nil
---@return [string, string][]|nil
local function tool_markers_virt(name, frontmatter_items, sandbox_items)
  local chunks = {}
  if frontmatter_items and frontmatter_items[name] then
    table.insert(chunks, { SOURCE_ICON.F, SOURCE_HL.F })
  end
  if sandbox_items and sandbox_items[name] then
    if #chunks > 0 then
      table.insert(chunks, { " ", "Normal" })
    end
    table.insert(chunks, { MARKER_SANDBOX, "FlemmaStatusSandboxIcon" })
  end
  if #chunks > 0 then
    table.insert(chunks, { " ", "Normal" })
  end
  return #chunks > 0 and chunks or nil
end

--- Inline highlight patterns: {lua_pattern, highlight_group}, ordered by specificity.
---@type {[1]: string, [2]: string}[]
local VALUE_PATTERNS = {
  { "%$%d+%.?%d*", "FlemmaStatusNumber" },
  { "%d+%.?%d*%%", "FlemmaStatusNumber" },
  { "%d+%.?%d*[KM]", "FlemmaStatusNumber" },
  { "%d+%.?%d*", "FlemmaStatusNumber" },
  { "true", "FlemmaStatusEnabled" },
  { "enabled", "FlemmaStatusEnabled" },
  { "false", "FlemmaStatusDisabled" },
  { "disabled", "FlemmaStatusDisabled" },
}

---Emit value text with inline highlighting for numbers, booleans, and status keywords.
---@param b flemma.status.Builder
---@param text string
---@param base_hl? string Highlight for unhighlighted text segments
local function put_value(b, text, base_hl)
  local pos = 1
  local len = #text
  while pos <= len do
    ---@type integer?, integer?, string?
    local best_s, best_e, best_hl
    for _, entry in ipairs(VALUE_PATTERNS) do
      local s, e = text:find(entry[1], pos)
      if s and (not best_s or s < best_s or (s == best_s and e > best_e)) then
        best_s, best_e, best_hl = s, e, entry[2]
      end
    end

    if not best_s then
      b:put(text:sub(pos), base_hl)
      break
    end

    if best_s > pos then
      b:put(text:sub(pos, best_s - 1), base_hl)
    end
    b:put(text:sub(best_s, best_e), best_hl)
    pos = best_e + 1
  end
end

---Emit a model name with version suffix highlighted separately.
---The version starts at the first digit and extends to the end.
---@param b flemma.status.Builder
---@param model string
local function put_model_value(b, model)
  local ver_start = model:find("%d")
  if ver_start and ver_start > 1 then
    b:put(model:sub(1, ver_start - 1))
    b:put(model:sub(ver_start), "FlemmaStatusVersion")
  else
    b:put(model)
  end
end

---@class flemma.status.KVItem
---@field key string
---@field value string
---@field source? string
---@field value_hl? string
---@field put_fn? fun(b: flemma.status.Builder)

---Render a flat key-value section as a tree branch.
---Key width is computed from the items — no hardcoded widths.
---@param b flemma.status.Builder
---@param section_name string
---@param items flemma.status.KVItem[]
---@param is_last boolean
---@param summary? string
local function format_kv_section(b, section_name, items, is_last, summary)
  b:branch(is_last)
  b:put(section_name, "FlemmaStatusSection")
  if summary then
    b:put("  ")
    b:put(summary, "FlemmaStatusSummary")
  end
  b:nl()

  if #items == 0 then
    b:leaf(true)
    b:put("(none)", "FlemmaStatusParen")
    b:nl()
  else
    local item_keys = {}
    for _, item in ipairs(items) do
      table.insert(item_keys, item.key)
    end
    local kw = key_width_of(item_keys)

    for i, item in ipairs(items) do
      b:leaf(i == #items)
      b:put(pad(item.key, kw), "FlemmaStatusKey")
      b:put(" ")
      if item.put_fn then
        item.put_fn(b)
      elseif item.value_hl then
        b:put(item.value, item.value_hl)
      else
        put_value(b, item.value)
      end
      if item.source then
        local vt = source_virt_text(item.source)
        if vt then
          b:virt(vt)
        end
      end
      b:nl()
    end
  end

  b:unbranch()
end

-- ---------------------------------------------------------------------------
-- Section formatters
-- ---------------------------------------------------------------------------

---@param b flemma.status.Builder
---@param data flemma.status.Data
---@param is_last boolean
local function format_provider_section(b, data, is_last)
  local p = data.provider

  ---@type flemma.status.KVItem[]
  local items = {
    { key = "name", value = p.name, source = p.source },
    {
      key = "model",
      value = p.model or "(none)",
      source = p.model_source,
      put_fn = p.model and function(b_inner)
          put_model_value(b_inner, p.model --[[@as string]])
        end or nil,
    },
  }

  local mi = p.model_info
  if mi then
    if mi.max_input_tokens or mi.max_output_tokens then
      local ctx_parts = {}
      if mi.max_input_tokens then
        table.insert(ctx_parts, str.format_tokens(mi.max_input_tokens) .. " input")
      end
      if mi.max_output_tokens then
        table.insert(ctx_parts, str.format_tokens(mi.max_output_tokens) .. " output")
      end
      table.insert(items, { key = "context", value = table.concat(ctx_parts, ", ") })
    end

    if mi.pricing then
      local pricing = mi.pricing
      local price_str = string.format("$%.2f/$%.2f", pricing.input, pricing.output)
      if pricing.cache_read or pricing.cache_write then
        local cache_parts = {}
        if pricing.cache_read then
          table.insert(cache_parts, string.format("$%.2f read", pricing.cache_read))
        end
        if pricing.cache_write then
          table.insert(cache_parts, string.format("$%.2f write", pricing.cache_write))
        end
        price_str = price_str .. " (cache: " .. table.concat(cache_parts, ", ") .. ")"
      end
      table.insert(items, { key = "pricing", value = price_str })
    end
  end

  format_kv_section(b, "Provider", items, is_last)
end

---@param b flemma.status.Builder
---@param data flemma.status.Data
---@param is_last boolean
local function format_parameters_section(b, data, is_last)
  local sorted_keys = {}
  for key, _ in pairs(data.parameters.merged) do
    table.insert(sorted_keys, key)
  end
  table.sort(sorted_keys)

  ---@type flemma.status.KVItem[]
  local items = {}
  for _, key in ipairs(sorted_keys) do
    local value = data.parameters.merged[key]
    local value_str = format_value(value)
    if key == "max_tokens" and data.parameters.resolved_max_tokens then
      value_str = value_str .. " → " .. tostring(data.parameters.resolved_max_tokens)
    elseif key == "thinking" and data.parameters.resolved_thinking then
      if data.parameters.resolved_thinking ~= value_str then
        value_str = value_str .. " → " .. data.parameters.resolved_thinking
      end
    end
    local source = data.parameters.sources and data.parameters.sources[key] or nil
    ---@type fun(b: flemma.status.Builder)|nil
    local put_fn = nil
    if key == "model" and type(value) == "string" then
      put_fn = function(b_inner)
        put_model_value(b_inner, value_str)
      end
    end
    table.insert(items, { key = key, value = value_str, source = source, put_fn = put_fn })
  end

  format_kv_section(b, "Parameters", items, is_last)
end

---@param b flemma.status.Builder
---@param data flemma.status.Data
---@param is_last boolean
local function format_autopilot_section(b, data, is_last)
  local ap = data.autopilot
  local status_str = (ap.enabled and "enabled" or "disabled") .. " (" .. ap.buffer_state .. ")"
  local status_hl = ap.enabled and "FlemmaStatusEnabled" or "FlemmaStatusDisabled"

  ---@type flemma.status.KVItem[]
  local items = {
    { key = "status", value = status_str, value_hl = status_hl, source = ap.sources.status },
    { key = "max_turns", value = tostring(ap.max_turns), source = ap.sources.max_turns },
  }

  format_kv_section(b, "Autopilot", items, is_last)
end

---@param b flemma.status.Builder
---@param data flemma.status.Data
---@param is_last boolean
local function format_sandbox_section(b, data, is_last)
  local sb = data.sandbox

  -- Compute key width from the actual keys in this section
  local sandbox_keys = { "status", "config setting", "backend", "network", "privileged" }
  if sb.runtime_override ~= nil then
    table.insert(sandbox_keys, "runtime override")
  end
  local KEY_W = key_width_of(sandbox_keys)

  b:branch(is_last)
  b:put("Sandbox", "FlemmaStatusSection")
  b:nl()

  -- status
  b:leaf(false)
  b:put(pad("status", KEY_W), "FlemmaStatusKey")
  b:put(" ")
  b:put(sb.enabled and "enabled" or "disabled", sb.enabled and "FlemmaStatusEnabled" or "FlemmaStatusDisabled")
  b:nl()

  -- config setting
  b:leaf(false)
  b:put(pad("config setting", KEY_W), "FlemmaStatusKey")
  b:put(" ")
  b:put(
    sb.config_enabled and "enabled" or "disabled",
    sb.config_enabled and "FlemmaStatusEnabled" or "FlemmaStatusDisabled"
  )
  if sb.sources.config_setting then
    local vt = source_virt_text(sb.sources.config_setting)
    if vt then
      b:virt(vt)
    end
  end
  b:nl()

  -- runtime override (optional)
  if sb.runtime_override ~= nil then
    b:leaf(false)
    b:put(pad("runtime override", KEY_W), "FlemmaStatusKey")
    b:put(" ")
    b:put(tostring(sb.runtime_override), sb.runtime_override and "FlemmaStatusEnabled" or "FlemmaStatusDisabled")
    b:nl()
  end

  -- backend (branch — has children)
  local backend_text = (sb.backend or "(none)") .. (sb.backend_mode and (" (" .. sb.backend_mode .. ")") or "")
  local has_error = sb.backend_error ~= nil
  local backend_children = { "available" }
  if has_error then
    table.insert(backend_children, "error")
  end
  -- Each tree level adds 3 display cells of prefix ("│  " / "├─ ").
  -- Shrink the child key width by 3 so values align with the parent's.
  local BACKEND_KW = math.max(key_width_of(backend_children), KEY_W - 3)

  b:branch(false)
  b:put(pad("backend", KEY_W), "FlemmaStatusKey")
  b:put(" ")
  b:put(backend_text)
  if sb.sources.backend then
    local vt = source_virt_text(sb.sources.backend)
    if vt then
      b:virt(vt)
    end
  end
  b:nl()

  b:leaf(not has_error)
  b:put(pad("available", BACKEND_KW), "FlemmaStatusKey")
  b:put(" ")
  b:put(tostring(sb.backend_available), sb.backend_available and "FlemmaStatusEnabled" or "FlemmaStatusDisabled")
  b:nl()

  if has_error then
    b:leaf(true)
    b:put(pad("error", BACKEND_KW), "FlemmaStatusKey")
    b:put(" ")
    b:put(sb.backend_error --[[@as string]], "FlemmaStatusDisabled")
    b:nl()
  end

  b:unbranch()

  -- network
  b:leaf(false)
  b:put(pad("network", KEY_W), "FlemmaStatusKey")
  b:put(" ")
  local net_str = sb.policy.network == false and "blocked" or "allowed"
  b:put(net_str, sb.policy.network == false and "FlemmaStatusDisabled" or "FlemmaStatusEnabled")
  if sb.sources.network then
    local vt = source_virt_text(sb.sources.network)
    if vt then
      b:virt(vt)
    end
  end
  b:nl()

  -- privileged
  local rw_paths = sb.policy.rw_paths or {}
  b:leaf(#rw_paths == 0)
  b:put(pad("privileged", KEY_W), "FlemmaStatusKey")
  b:put(" ")
  local priv_str = sb.policy.allow_privileged == true and "allowed" or "dropped"
  b:put(priv_str, sb.policy.allow_privileged == true and "FlemmaStatusDisabled" or "FlemmaStatusEnabled")
  if sb.sources.privileged then
    local vt = source_virt_text(sb.sources.privileged)
    if vt then
      b:virt(vt)
    end
  end
  b:nl()

  -- rw_paths
  if #rw_paths > 0 then
    b:branch(true)
    b:put("rw_paths", "FlemmaStatusKey")
    b:nl()

    for i, path in ipairs(rw_paths) do
      b:leaf(i == #rw_paths)
      b:put(collapse_path(path))
      b:nl()
    end

    b:unbranch()
  end

  b:unbranch()
end

---@param b flemma.status.Builder
---@param data flemma.status.Data
---@param is_last boolean
local function format_tools_section(b, data, is_last)
  local t = data.tools
  local enabled_count = #t.enabled
  local disabled_count = #t.disabled
  local summary = enabled_count .. " enabled, " .. disabled_count .. " disabled"

  b:branch(is_last)
  b:put("Tools", "FlemmaStatusSection")
  b:put("  ")
  b:put(summary, "FlemmaStatusSummary")
  b:nl()

  -- booting indicator
  if t.booting then
    b:leaf(false)
    b:put("⏳ loading async tool sources…", "FlemmaStatusBooting")
    b:nl()
  end

  -- max_concurrent
  local mc_label = t.max_concurrent == 0 and "unlimited" or tostring(t.max_concurrent)
  local mc_is_last = enabled_count == 0 and disabled_count == 0
  b:leaf(mc_is_last)
  b:put(pad("max_concurrent", key_width_of({ "max_concurrent" })), "FlemmaStatusKey")
  b:put(" ")
  b:put(mc_label)
  b:nl()

  -- enabled tools
  if enabled_count > 0 then
    b:branch(disabled_count == 0)
    b:put("enabled", "FlemmaStatusKey")
    b:nl()

    for i, name in ipairs(t.enabled) do
      b:leaf(i == enabled_count)
      b:put(name, "FlemmaStatusToolEnabled")
      local vt = tool_markers_virt(name, t.frontmatter_items, nil)
      if vt then
        b:virt(vt)
      end
      b:nl()
    end

    b:unbranch()
  end

  -- disabled tools
  if disabled_count > 0 then
    b:branch(true)
    b:put("disabled", "FlemmaStatusKey")
    b:nl()

    for i, name in ipairs(t.disabled) do
      b:leaf(i == disabled_count)
      b:put(name, "FlemmaStatusToolDisabled")
      local vt = tool_markers_virt(name, t.frontmatter_items, nil)
      if vt then
        b:virt(vt)
      end
      b:nl()
    end

    b:unbranch()
  end

  b:unbranch()
end

---@param b flemma.status.Builder
---@param data flemma.status.Data
---@param is_last boolean
local function format_approval_section(b, data, is_last)
  local ap = data.approval

  b:branch(is_last)
  b:put("Approval", "FlemmaStatusSection")
  b:nl()

  if ap.require_approval_disabled then
    b:leaf(true)
    b:put("all tools auto-approved ", "FlemmaStatusEnabled")
    b:put("(require_approval = false)", "FlemmaStatusParen")
    b:nl()
  else
    local has_approved = #ap.approved > 0
    local has_denied = #ap.denied > 0
    local has_pending = #ap.pending > 0
    local total_groups = (has_approved and 1 or 0) + (has_denied and 1 or 0) + (has_pending and 1 or 0)
    local groups_shown = 0

    if has_approved then
      groups_shown = groups_shown + 1
      b:branch(groups_shown == total_groups)
      b:put("✓ ", "FlemmaStatusToolEnabled")
      b:put("auto-approve", "FlemmaStatusToolEnabled")
      b:nl()

      for i, name in ipairs(ap.approved) do
        b:leaf(i == #ap.approved)
        b:put(name)
        local vt = tool_markers_virt(name, ap.frontmatter_items, ap.sandbox_items)
        if vt then
          b:virt(vt)
        end
        b:nl()
      end

      b:unbranch()
    end

    if has_denied then
      groups_shown = groups_shown + 1
      b:branch(groups_shown == total_groups)
      b:put("✗ ", "FlemmaStatusToolDisabled")
      b:put("deny", "FlemmaStatusToolDisabled")
      b:nl()

      for i, name in ipairs(ap.denied) do
        b:leaf(i == #ap.denied)
        b:put(name)
        b:nl()
      end

      b:unbranch()
    end

    if has_pending then
      groups_shown = groups_shown + 1
      b:branch(groups_shown == total_groups)
      b:put("⋯ ", "FlemmaStatusToolPending")
      b:put("require approval", "FlemmaStatusToolPending")
      b:nl()

      for i, name in ipairs(ap.pending) do
        b:leaf(i == #ap.pending)
        b:put(name)
        b:nl()
      end

      b:unbranch()
    end

    if total_groups == 0 then
      b:leaf(true)
      b:put("(no tools registered)", "FlemmaStatusParen")
      b:nl()
    end
  end

  b:unbranch()
end

---Recursively render a table as tree nodes (for model_info, config dump).
---@param b flemma.status.Builder
---@param tbl table
local function render_table_tree(b, tbl)
  local keys = {}
  for k in pairs(tbl) do
    table.insert(keys, k)
  end
  table.sort(keys, function(a, b_key)
    return tostring(a) < tostring(b_key)
  end)

  -- Compute per-run key widths: consecutive leaf keys share a width,
  -- broken by object (table) entries so alignment resets after subtrees.
  local key_widths = {}
  local run_keys = {}
  local run_indices = {}
  for i, k in ipairs(keys) do
    if type(tbl[k]) == "table" then
      -- Object breaks the run — flush
      if #run_indices > 0 then
        local kw = key_width_of(run_keys)
        for _, idx in ipairs(run_indices) do
          key_widths[idx] = kw
        end
        run_keys = {}
        run_indices = {}
      end
    else
      table.insert(run_keys, tostring(k))
      table.insert(run_indices, i)
    end
  end
  if #run_indices > 0 then
    local kw = key_width_of(run_keys)
    for _, idx in ipairs(run_indices) do
      key_widths[idx] = kw
    end
  end

  for i, k in ipairs(keys) do
    local v = tbl[k]
    local last = i == #keys

    if type(v) == "table" then
      b:branch(last)
      b:put(tostring(k), "FlemmaStatusKey")
      b:nl()
      render_table_tree(b, v)
      b:unbranch()
    else
      b:leaf(last)
      b:put(pad(tostring(k), key_widths[i] or 8), "FlemmaStatusKey")
      b:put(" ")
      put_value(b, format_value(v))
      b:nl()
    end
  end
end

---@param b flemma.status.Builder
---@param data flemma.status.Data
---@param is_last boolean
local function format_model_info_section(b, data, is_last)
  local mi = data.provider.model_info
  if not mi then
    return
  end

  b:branch(is_last)
  b:put("Model Info", "FlemmaStatusSection")
  b:nl()

  render_table_tree(b, mi)

  b:unbranch()
end

---@param b flemma.status.Builder
---@param data flemma.status.Data
---@param is_last boolean
local function format_layer_ops_section(b, data, is_last)
  local intro = data.introspection
  if not intro then
    return
  end

  b:branch(is_last)
  b:put("Layer Ops", "FlemmaStatusSection")
  b:nl()

  local layers = intro.layer_ops

  -- Compute layer name width from actual names
  local layer_names = {}
  for _, layer in ipairs(layers) do
    table.insert(layer_names, layer.name)
  end
  local layer_kw = key_width_of(layer_names)

  for li, layer in ipairs(layers) do
    local layer_is_last = li == #layers
    local op_count = #layer.ops
    local suffix = ""
    if layer.label == "D" then
      suffix = " (schema materialized)"
    end

    if layer.label == "D" or op_count == 0 then
      b:leaf(layer_is_last)
      b:put(pad(layer.name, layer_kw), "FlemmaStatusKey")
      b:put(" ")
      b:put(op_count .. " ops" .. suffix, "FlemmaStatusSummary")
      b:nl()
    else
      b:branch(layer_is_last)
      b:put(pad(layer.name, layer_kw), "FlemmaStatusKey")
      b:put(" ")
      b:put(op_count .. " ops", "FlemmaStatusSummary")
      b:nl()

      -- Compute op verb and path widths from this layer's ops
      local op_names = {}
      local op_paths = {}
      for _, op_entry in ipairs(layer.ops) do
        table.insert(op_names, op_entry.op)
        table.insert(op_paths, op_entry.path)
      end
      local op_kw = key_width_of(op_names)
      local path_kw = key_width_of(op_paths)

      for oi, op_entry in ipairs(layer.ops) do
        b:leaf(oi == op_count)
        local op_hl = OP_HL[op_entry.op] or "FlemmaStatusOpSet"
        b:put(pad(op_entry.op, op_kw), op_hl)
        b:put(" ")
        b:put(pad(op_entry.path, path_kw), "FlemmaStatusOpPath")
        b:put(" → ", "FlemmaStatusOpArrow")
        b:put(format_value(op_entry.value))
        b:nl()
      end

      b:unbranch()
    end
  end

  b:unbranch()
end

---@param b flemma.status.Builder
---@param data flemma.status.Data
---@param is_last boolean
local function format_resolved_section(b, data, is_last)
  local intro = data.introspection
  if not intro then
    return
  end

  b:branch(is_last)
  b:put("Resolved Config", "FlemmaStatusSection")
  b:nl()

  local resolved = intro.resolved
  if #resolved == 0 then
    b:leaf(true)
    b:put("(empty)", "FlemmaStatusParen")
    b:nl()
    b:unbranch()
    return
  end

  -- Pre-compute whether each entry is the last sibling at its depth
  local is_last_sibling = {}
  for i = 1, #resolved do
    local depth = resolved[i].depth
    local found_sibling = false
    for j = i + 1, #resolved do
      if resolved[j].depth == depth then
        found_sibling = true
        break
      elseif resolved[j].depth < depth then
        break
      end
    end
    is_last_sibling[i] = not found_sibling
  end

  -- Pre-compute key width per sibling group so siblings align with each
  -- other but different subtrees get their own tighter alignment.
  local key_widths = {}

  ---Flush a run of leaf indices: assign the shared key width.
  ---@param indices integer[]
  ---@param max_w integer
  local function flush_run(indices, max_w)
    if #indices == 0 then
      return
    end
    local width = max_w > 0 and max_w + 2 or 8
    for _, idx in ipairs(indices) do
      key_widths[idx] = width
    end
  end

  ---Scan direct children of a parent, grouping consecutive leaves into
  ---runs broken by object nodes.  Each run gets its own key width so
  ---alignment resets after every subtree.
  ---@param start integer First child index in the resolved list
  ---@param parent_depth integer Depth of the parent (-1 for root)
  ---@param child_depth integer Depth of direct children
  local function compute_sibling_widths(start, parent_depth, child_depth)
    local max_w = 0
    local indices = {}
    for j = start, #resolved do
      if resolved[j].depth <= parent_depth then
        break
      end
      if resolved[j].depth == child_depth then
        if resolved[j].is_object then
          -- Object breaks the current leaf run
          flush_run(indices, max_w)
          max_w = 0
          indices = {}
        else
          local leaf_name = resolved[j].path:match("[^.]+$") or resolved[j].path
          max_w = math.max(max_w, vim.fn.strdisplaywidth(leaf_name))
          table.insert(indices, j)
        end
      end
    end
    flush_run(indices, max_w)
  end

  compute_sibling_widths(1, -1, 0)
  for idx = 1, #resolved do
    if resolved[idx].is_object then
      compute_sibling_widths(idx + 1, resolved[idx].depth, resolved[idx].depth + 1)
    end
  end

  local current_depth = 0

  for i, entry in ipairs(resolved) do
    local depth = entry.depth

    -- Adjust depth: unbranch if going up
    while current_depth > depth do
      b:unbranch()
      current_depth = current_depth - 1
    end

    local last = is_last_sibling[i]

    if entry.is_object then
      b:branch(last)
      local leaf_name = entry.path:match("[^.]+$") or entry.path
      b:put(leaf_name, "FlemmaStatusKey")
      b:nl()
      current_depth = current_depth + 1
    else
      b:leaf(last)
      local leaf_name = entry.path:match("[^.]+$") or entry.path
      b:put(pad(leaf_name, key_widths[i] or 12), "FlemmaStatusKey")
      b:put(" ")
      put_value(b, format_value(entry.value))
      if entry.source then
        local vt = source_virt_text(entry.source)
        if vt then
          b:virt(vt)
        end
      end
      b:nl()
    end
  end

  -- Unbranch back to resolved section level
  while current_depth > 0 do
    b:unbranch()
    current_depth = current_depth - 1
  end

  b:unbranch()
end

---@param b flemma.status.Builder
---@param data flemma.status.Data
---@param is_last boolean
local function format_config_fallback(b, data, is_last)
  b:branch(is_last)
  b:put("Config (full)", "FlemmaStatusSection")
  b:nl()

  local config_text = vim.inspect(config_facade.materialize(data.buffer.bufnr))
  local config_lines = vim.split(config_text, "\n", { trimempty = true })

  for i, line in ipairs(config_lines) do
    b:leaf(i == #config_lines)
    b:put(line)
    b:nl()
  end

  b:unbranch()
end

---@param b flemma.status.Builder
---@param data flemma.status.Data
local function format_legend(b, data)
  local has_source = data.provider.source
    or data.provider.model_source
    or (data.parameters.sources and next(data.parameters.sources))
    or (data.autopilot.sources and next(data.autopilot.sources))
    or (data.sandbox.sources and next(data.sandbox.sources))
    or data.tools.frontmatter_items
    or data.approval.frontmatter_items
  local has_sandbox = data.approval.sandbox_items ~= nil

  if not has_source and not has_sandbox then
    return
  end

  b:put(SOURCE_ICON.S, SOURCE_HL.S)
  b:put(" setup  ", "FlemmaStatusLegend")
  b:put(SOURCE_ICON.F, SOURCE_HL.F)
  b:put(" frontmatter  ", "FlemmaStatusLegend")
  b:put(SOURCE_ICON.R, SOURCE_HL.R)
  b:put(" runtime", "FlemmaStatusLegend")
  if has_sandbox then
    b:put("  ")
    b:put(MARKER_SANDBOX, "FlemmaStatusSandboxIcon")
    b:put(" sandbox", "FlemmaStatusLegend")
  end
  b:nl()
end

---Format status data into tree-structured lines with extmark highlight data.
---@param data flemma.status.Data
---@param verbose boolean Whether to include layer ops and resolved config tree
---@return flemma.status.FormatResult
function M.format(data, verbose)
  local b = new_builder()

  -- Title
  b:put("Flemma Status", "FlemmaStatusTitle")
  b:nl()

  -- Frontmatter validation diagnostics
  if data.diagnostics and #data.diagnostics > 0 then
    for i, d in ipairs(diagnostic_format.sort(data.diagnostics)) do
      local hl = diagnostic_format.highlight(d.severity)
      b:put("┆", "FlemmaStatusTree")
      b:put(" " .. diagnostic_format.format_message(d), hl)
      b:nl()
      local loc = diagnostic_format.format_location(d)
      if loc then
        b:put("┆", "FlemmaStatusTree")
        b:put("   " .. loc, "Comment")
        b:nl()
      end
      for _, stack_line in ipairs(diagnostic_format.format_include_stack(d)) do
        b:put("┆", "FlemmaStatusTree")
        b:put("   " .. stack_line, "Comment")
        b:nl()
      end
      if i < #data.diagnostics then
        b:put("┆", "FlemmaStatusTree")
        b:nl()
      end
    end
  end

  b:gap()

  local has_introspection = verbose and data.introspection ~= nil

  -- ── Provider ──
  format_provider_section(b, data, false)
  b:gap()

  -- ── Parameters ──
  format_parameters_section(b, data, false)
  b:gap()

  -- ── Autopilot ──
  format_autopilot_section(b, data, false)
  b:gap()

  -- ── Sandbox ──
  format_sandbox_section(b, data, false)
  b:gap()

  -- ── Tools ──
  format_tools_section(b, data, false)
  b:gap()

  -- ── Approval ──
  local approval_is_last = not has_introspection
  format_approval_section(b, data, approval_is_last)

  -- ── Verbose sections ──
  if has_introspection then
    if data.provider.model_info then
      b:gap()
      format_model_info_section(b, data, false)
    end

    b:gap()
    format_layer_ops_section(b, data, false)

    b:gap()
    format_resolved_section(b, data, true)
  elseif verbose then
    b:gap()
    format_config_fallback(b, data, true)
  end

  -- Legend
  b:blank()
  format_legend(b, data)

  return b:build()
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---Collect all runtime status data for a buffer
---@param bufnr integer Buffer number (0 for current)
---@return flemma.status.Data
function M.collect(bufnr)
  -- Evaluate frontmatter for chat buffers FIRST — writes to config store's
  -- FRONTMATTER layer. This must happen before materialize() so the
  -- materialized config includes frontmatter overrides.
  local is_chat = vim.api.nvim_buf_is_valid(bufnr) and bufnr > 0 and vim.bo[bufnr].filetype == "chat"
  local collected_diagnostics = nil
  if is_chat then
    local fm_result = processor.evaluate_buffer_frontmatter(bufnr)
    state.get_buffer_state(bufnr).frontmatter_eval_code = fm_result.frontmatter_code
    -- Collect diagnostics (validation failures are already converted inside
    -- evaluate_frontmatter_internal, no separate normalization needed)
    for _, diagnostic in ipairs(fm_result.diagnostics) do
      if diagnostic.severity == "error" or diagnostic.severity == "warning" then
        collected_diagnostics = collected_diagnostics or {}
        table.insert(collected_diagnostics, diagnostic)
      end
    end
  end

  -- Materialize after frontmatter evaluation so all layers are included.
  -- materialize() is needed because flatten_parameters uses pairs().
  -- resolve_preset() expands $-prefixed model references to concrete values.
  local config = normalize.resolve_preset(config_facade.materialize(bufnr))

  local tools_data = collect_tools(bufnr)

  return {
    provider = collect_provider(config, bufnr),
    parameters = collect_parameters(config, bufnr),
    autopilot = collect_autopilot(bufnr, config),
    sandbox = collect_sandbox(bufnr),
    tools = tools_data,
    approval = collect_approval(config, bufnr, tools_data.enabled),
    buffer = {
      is_chat = is_chat,
      bufnr = bufnr,
    },
    diagnostics = collected_diagnostics,
  }
end

---Collect all runtime status data for a buffer including introspection for verbose view.
---@param bufnr integer Buffer number (0 for current)
---@return flemma.status.Data
function M.collect_verbose(bufnr)
  local data = M.collect(bufnr)
  data.introspection = collect_introspection(bufnr)
  return data
end

---Ensure all status highlight groups are defined.
local function setup_highlights()
  local groups = {
    FlemmaStatusTitle = "Title",
    FlemmaStatusTree = "Comment",
    FlemmaStatusSection = "Type",
    FlemmaStatusKey = "Keyword",
    FlemmaStatusEnabled = "DiagnosticOk",
    FlemmaStatusDisabled = "DiagnosticWarn",
    FlemmaStatusParen = "Comment",
    FlemmaStatusSummary = "Comment",
    FlemmaStatusToolEnabled = "DiagnosticOk",
    FlemmaStatusToolDisabled = "DiagnosticWarn",
    FlemmaStatusToolPending = "DiagnosticInfo",
    FlemmaStatusBooting = "WarningMsg",
    FlemmaStatusNumber = "Number",
    FlemmaStatusVersion = "Special",
    FlemmaStatusOpSet = "Keyword",
    FlemmaStatusOpAppend = "DiagnosticOk",
    FlemmaStatusOpRemove = "DiagnosticWarn",
    FlemmaStatusOpPath = "Identifier",
    FlemmaStatusOpArrow = "Operator",
    FlemmaStatusLegend = "Comment",
  }
  for name, link in pairs(groups) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end

  -- Source/sandbox icon highlights: fg-only (no bg) so CursorLine bleeds through
  -- when combined via hl_mode="combine" on the virtual text extmarks.
  local fg_only_groups = {
    FlemmaStatusSourceDefault = "Comment",
    FlemmaStatusSourceSetup = "DiagnosticInfo",
    FlemmaStatusSourceRuntime = "DiagnosticOk",
    FlemmaStatusSourceFrontmatter = "DiagnosticHint",
    FlemmaStatusSandboxIcon = "DiagnosticInfo",
  }
  for name, base in pairs(fg_only_groups) do
    local resolved = vim.api.nvim_get_hl(0, { name = base, link = false })
    vim.api.nvim_set_hl(0, name, { fg = resolved.fg, default = true })
  end
end

---Open a vertical-split scratch buffer with formatted status output
---@param opts flemma.status.ShowOptions
function M.show(opts)
  local target_bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  -- When the current buffer is the status window itself (e.g. re-running
  -- :Flemma status while the cursor is already in the status split), retrieve
  -- the original chat buffer that was recorded when the window was opened.
  if vim.api.nvim_buf_is_valid(target_bufnr) and vim.bo[target_bufnr].filetype == "flemma-status" then
    local source = vim.b[target_bufnr].flemma_source_bufnr
    if source and vim.api.nvim_buf_is_valid(source) then
      target_bufnr = source
    end
  end

  local is_verbose = opts.verbose or false
  local data
  if is_verbose then
    data = M.collect_verbose(target_bufnr)
  else
    data = M.collect(target_bufnr)
  end
  local result = M.format(data, is_verbose)

  -- Check if a status buffer already exists in the current tabpage
  local existing_win = nil
  local existing_bufnr = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "flemma-status" then
      existing_win = win
      existing_bufnr = buf
      break
    end
  end

  local buf
  local win
  if existing_win then
    vim.api.nvim_set_current_win(existing_win)
    buf = existing_bufnr --[[@as integer]]
    win = existing_win
  else
    vim.cmd("vnew")
    buf = vim.api.nvim_get_current_buf()
    win = vim.api.nvim_get_current_win()
  end

  -- Set buffer and window options
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.wo[win].wrap = false
  vim.api.nvim_buf_set_name(buf, "flemma://status")
  vim.b[buf].flemma_source_bufnr = target_bufnr

  -- Write content
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, result.lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "flemma-status"

  -- Apply extmark-based highlighting
  setup_highlights()
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  for _, em in ipairs(result.extmarks) do
    vim.api.nvim_buf_set_extmark(buf, NS, em[1], em[2], {
      end_col = em[3],
      hl_group = em[4],
    })
  end

  for _, vt in ipairs(result.virt_texts) do
    vim.api.nvim_buf_set_extmark(buf, NS, vt[1], 0, {
      virt_text = vt[2],
      virt_text_pos = "right_align",
      hl_mode = "combine",
    })
  end

  -- Map q to close
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })

  -- Jump to section if requested
  if opts.jump_to then
    local current_win = vim.api.nvim_get_current_win()
    for index, line in ipairs(result.lines) do
      if line:find(opts.jump_to, 1, true) then
        vim.api.nvim_win_set_cursor(current_win, { index, 0 })
        break
      end
    end
  end
end

return M
