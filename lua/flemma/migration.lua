---@class flemma.migration
local M = {}

local config_facade = require("flemma.config")
local bridge = require("flemma.bridge")
local notify = require("flemma.notify")

local ROLES = { System = true, You = true, Assistant = true }

--- Pattern matching Tool Use headers with colon-separated tool names.
local COLON_TOOL_USE = "^%*%*Tool Use:%*%* `([^`]*:[^`]*)` %(`[^`]+`%)"

--- Known literal strings from old message templates that embed colon-separated tool names.
---@type { old: string, new: string }[]
local KNOWN_REPLACEMENTS = {
  { old = "`flemma:jobs:status`", new = "`flemma.jobs.status`" },
}

--- Check if a line array contains old-format role markers (inline content)
--- or colon-separated tool names in Tool Use headers.
---@param lines string[]
---@return boolean
function M.needs_migration(lines)
  for _, line in ipairs(lines) do
    local role = line:match("^@([%w]+):")
    if role and ROLES[role] then
      local after = line:sub(#role + 3) -- everything after "@Role:"
      if after:match("%S") then
        return true
      end
    end
    if line:match(COLON_TOOL_USE) then
      return true
    end
    for _, pair in ipairs(KNOWN_REPLACEMENTS) do
      if line:find(pair.old, 1, true) then
        return true
      end
    end
  end
  return false
end

--- Transform a line array from old format to new format.
--- Role markers with inline content are split onto their own line.
--- Content is preserved exactly — no trimming.
---@class flemma.migration.Result
---@field tool_names_migrated boolean True if any Tool Use headers had colon separators rewritten

---@param lines string[]
---@return string[] migrated_lines
---@return flemma.migration.Result
function M.migrate_lines(lines)
  local result = {}
  local tool_names_migrated = false
  for _, line in ipairs(lines) do
    local role = line:match("^@([%w]+):")
    if role and ROLES[role] then
      local after = line:sub(#role + 3) -- everything after "@Role:"
      if after:match("%S") then
        -- Old format: split marker onto its own line
        table.insert(result, "@" .. role .. ":")
        -- Preserve content: strip at most one leading space (the conventional separator)
        local content = after:match("^ (.*)$") or after
        table.insert(result, content)
      else
        -- Already new format (marker alone or with trailing whitespace)
        table.insert(result, line)
      end
    else
      local tool_name = line:match(COLON_TOOL_USE)
      if tool_name then
        local new_name = tool_name:gsub(":", ".")
        local escaped = tool_name:gsub("([%-])", "%%%1")
        table.insert(result, (line:gsub("`" .. escaped .. "`", "`" .. new_name .. "`", 1)))
        tool_names_migrated = true
      else
        local rewritten = line
        for _, pair in ipairs(KNOWN_REPLACEMENTS) do
          if rewritten:find(pair.old, 1, true) then
            rewritten = rewritten:gsub(pair.old:gsub("([%.%-%+])", "%%%1"), pair.new)
            tool_names_migrated = true
          end
        end
        table.insert(result, rewritten)
      end
    end
  end
  return result, { tool_names_migrated = tool_names_migrated }
end

--- Pattern for quoted colon-separated tool names: "word:word" or "word:word:word" etc.
--- Captures the full quoted string including quotes.
local QUOTED_COLON_TOOL = '"([a-zA-Z][a-zA-Z0-9_-]*:[a-zA-Z0-9_*:.-]*)"'

--- Migrate colon-separated tool names to dots on frontmatter lines that
--- reference flemma.opt.tools. Only touches lines inside the first fence
--- block that contain the tools config accessor.
---@param lines string[]
---@return string[] migrated_lines
---@return boolean changed True if any frontmatter lines were rewritten
local function migrate_frontmatter_tool_names(lines)
  local result = {}
  local in_frontmatter = false
  local changed = false
  for _, line in ipairs(lines) do
    if not in_frontmatter then
      if line:match("^```lua") then
        in_frontmatter = true
      end
      table.insert(result, line)
    elseif line:match("^```") then
      in_frontmatter = false
      table.insert(result, line)
    elseif line:match("flemma%.opt%.tools") and line:match(QUOTED_COLON_TOOL) then
      local migrated = line:gsub(QUOTED_COLON_TOOL, function(name)
        return '"' .. name:gsub(":", ".") .. '"'
      end)
      if migrated ~= line then
        changed = true
      end
      table.insert(result, migrated)
    else
      table.insert(result, line)
    end
  end
  return result, changed
end

--- Migrate a buffer from old format to new format.
--- No-op if buffer is already in new format.
--- Wrapped in a single undo block. Triggers auto_write if enabled.
---@param bufnr integer
function M.migrate_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not M.needs_migration(lines) then
    return
  end
  local new_lines, info = M.migrate_lines(lines)

  if info.tool_names_migrated then
    local fm_lines, fm_changed = migrate_frontmatter_tool_names(new_lines)
    if fm_changed then
      new_lines = fm_lines
      vim.schedule(function()
        notify.warn(
          "Tool names were migrated from ':' to '.' in Tool Use headers and frontmatter. "
            .. "Review the frontmatter to confirm the changes are correct."
        )
      end)
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

  -- auto_write if enabled
  local config = config_facade.get(bufnr)
  if config.editing and config.editing.auto_write and vim.bo[bufnr].modified then
    local buf_ok, buf_mod = pcall(require, "flemma.utilities.buffer")
    if buf_ok then
      local ok, err = pcall(buf_mod.buffer_cmd, bufnr, "silent! write!")
      if not ok then
        local log_ok, log_mod = pcall(require, "flemma.logging")
        if log_ok then
          log_mod.warn("migrate_buffer: auto_write failed: " .. tostring(err))
        end
      end
    end
  end
end

---Run all load-time buffer migrations in sequence.
---@param bufnr integer
function M.migrate(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  M.migrate_buffer(bufnr)
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      local count = bridge.resolve_orphaned_jobs(bufnr)
      if count > 0 then
        notify.info(count .. " orphaned job(s) resolved.")
      end
    end
  end)
end

return M
