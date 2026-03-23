---@class flemma.migration
local M = {}

local config_facade = require("flemma.config")

local ROLES = { System = true, You = true, Assistant = true }

--- Check if a line array contains old-format role markers (inline content).
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
  end
  return false
end

--- Transform a line array from old format to new format.
--- Role markers with inline content are split onto their own line.
--- Content is preserved exactly — no trimming.
---@param lines string[]
---@return string[]
function M.migrate_lines(lines)
  local result = {}
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
      table.insert(result, line)
    end
  end
  return result
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
  local new_lines = M.migrate_lines(lines)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

  -- auto_write if enabled
  local config = config_facade.get(bufnr)
  if config.editing and config.editing.auto_write and vim.bo[bufnr].modified then
    local ui_ok, ui_mod = pcall(require, "flemma.ui")
    if ui_ok then
      local ok, err = pcall(ui_mod.buffer_cmd, bufnr, "silent! write!")
      if not ok then
        local log_ok, log_mod = pcall(require, "flemma.logging")
        if log_ok then
          log_mod.warn("migrate_buffer: auto_write failed: " .. tostring(err))
        end
      end
    end
  end
end

return M
