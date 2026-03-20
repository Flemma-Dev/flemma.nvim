--- Opts builder for the personality system
--- Assembles RenderOpts from tool definitions, Neovim state, and project context.
--- Personalities receive pre-built data and do no data gathering themselves.
---@class flemma.personalities.Builder
local M = {}

local state = require("flemma.state")
local tools = require("flemma.tools")

---@type string[]
local DEFAULT_TARGETS = {
  "AGENTS.md",
  "CLAUDE.md",
  ".claude/CLAUDE.md",
  ".cursorrules",
  ".github/copilot-instructions.md",
}

--- Build tool entries for a personality from a sorted tool definition array.
--- Each entry has { name, parts } where parts is keyed by part name.
--- Single string values are normalized to { value }.
---@param personality_name string
---@param tool_definitions flemma.tools.ToolDefinition[]
---@return flemma.personalities.ToolEntry[]
function M.build_tools(personality_name, tool_definitions)
  ---@type flemma.personalities.ToolEntry[]
  local result = {}
  for _, definition in ipairs(tool_definitions) do
    ---@type table<string, string[]>
    local parts = {}
    if definition.personalities and definition.personalities[personality_name] then
      for part_name, value in pairs(definition.personalities[personality_name]) do
        if type(value) == "string" then
          parts[part_name] = { value }
        elseif type(value) == "table" then
          parts[part_name] = value
        end
      end
    end
    table.insert(result, { name = definition.name, parts = parts })
  end
  return result
end

--- Build environment context from current Neovim state.
--- Date and time are cached per-buffer (in buffer_state.personality_environment) so the
--- system prompt stays identical across requests, enabling LLM provider prompt caching.
--- All other fields (cwd, current_file, filetype, git_branch) are captured fresh each
--- time since they may change between requests.
---@param bufnr? integer Buffer number (defaults to current buffer)
---@return flemma.personalities.Environment
function M.build_environment(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Cache date/time per buffer for prompt caching stability
  local buffer_state = state.get_buffer_state(bufnr)
  if not buffer_state.personality_environment then
    buffer_state.personality_environment = {
      date = os.date("%A, %B %d, %Y") --[[@as string]],
      time = os.date("%I:%M %p") --[[@as string]],
    }
  end
  ---@cast buffer_state {personality_environment: flemma.personalities.CachedEnvironment}
  local cached = buffer_state.personality_environment

  local cwd = vim.fn.getcwd()

  -- Current file (relative to cwd if possible)
  ---@type string|nil
  local current_file = nil
  local buffer_name = vim.api.nvim_buf_get_name(bufnr)
  if buffer_name ~= "" then
    local relative = vim.fn.fnamemodify(buffer_name, ":.")
    if relative ~= buffer_name then
      current_file = relative
    else
      current_file = buffer_name
    end
  end

  -- Filetype
  ---@type string|nil
  local filetype = vim.bo[bufnr].filetype
  if filetype == "" then
    filetype = nil
  end

  -- Git branch
  ---@type string|nil
  local git_branch = nil
  local git_result = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD 2>/dev/null")
  if vim.v.shell_error == 0 and git_result[1] and git_result[1] ~= "" then
    git_branch = git_result[1]
  end

  ---@type flemma.personalities.Environment
  return {
    cwd = cwd,
    current_file = current_file,
    filetype = filetype,
    git_branch = git_branch,
    date = cached.date,
    time = cached.time,
  }
end

--- Build project context by scanning for known files in the base directory.
--- Deduplicates by file content (byte-identical files are included only once).
---@param base_dir string Base directory to scan
---@param targets? string[] Override target list (defaults to DEFAULT_TARGETS)
---@return flemma.personalities.ProjectContextFile[]
function M.build_project_context(base_dir, targets)
  targets = targets or DEFAULT_TARGETS
  ---@type flemma.personalities.ProjectContextFile[]
  local result = {}
  ---@type table<string, boolean>
  local seen_content = {}

  for _, target in ipairs(targets) do
    local path = vim.fs.normalize(base_dir .. "/" .. target)
    if vim.fn.filereadable(path) == 1 then
      local file_handle = io.open(path, "r")
      if file_handle then
        local content = file_handle:read("*a")
        file_handle:close()
        if content and #content > 0 and not seen_content[content] then
          seen_content[content] = true
          table.insert(result, { path = target, content = content })
        end
      end
    end
  end

  return result
end

--- Build complete RenderOpts for a personality.
--- This is the main entry point — assembles all data the personality needs.
---@param personality_name string
---@param bufnr? integer Buffer number for per-buffer config resolution and environment context
---@param base_dir? string Base directory for project context (defaults to cwd)
---@return flemma.personalities.RenderOpts
function M.build(personality_name, bufnr, base_dir)
  local sorted_tools = tools.get_sorted_for_prompt(bufnr)
  return {
    tools = M.build_tools(personality_name, sorted_tools),
    environment = M.build_environment(bufnr),
    project_context = M.build_project_context(base_dir or vim.fn.getcwd()),
  }
end

return M
