--- Coding assistant personality for Flemma
--- Generates a system prompt for LLM-powered coding assistance in Neovim.
---@class flemma.personalities.CodingAssistant : flemma.personalities.Personality
local M = {}

---@param opts flemma.personalities.RenderOpts
---@return string
function M.render(opts)
  local lines = {}

  table.insert(lines, "You are an expert coding assistant operating in Neovim.")
  table.insert(lines, "")

  -- Available tools
  if #opts.tools > 0 then
    table.insert(lines, "## Available tools")
    table.insert(lines, "")
    for _, tool in ipairs(opts.tools) do
      local snippet = tool.parts.snippet and tool.parts.snippet[1]
      if snippet then
        table.insert(lines, "- " .. tool.name .. ": " .. snippet)
      else
        table.insert(lines, "- " .. tool.name)
      end
    end
    table.insert(lines, "")
  end

  -- Guidelines (collected from tool parts)
  local guideline_lines = {}
  for _, tool in ipairs(opts.tools) do
    if tool.parts.guidelines then
      for _, guideline in ipairs(tool.parts.guidelines) do
        table.insert(guideline_lines, guideline)
      end
    end
  end
  if #guideline_lines > 0 then
    table.insert(lines, "## Guidelines")
    table.insert(lines, "")
    for _, guideline in ipairs(guideline_lines) do
      table.insert(lines, "- " .. guideline)
    end
    table.insert(lines, "")
  end

  -- Environment
  local env = opts.environment
  table.insert(lines, "## Environment")
  table.insert(lines, "")
  table.insert(lines, "- Current date: " .. env.date .. " " .. env.time)
  table.insert(lines, "- Working directory: " .. env.cwd)
  if env.current_file then
    local suffix = env.filetype and (" (" .. env.filetype .. ")") or ""
    table.insert(lines, "- Current file: " .. env.current_file .. suffix)
  end
  if env.git_branch then
    table.insert(lines, "- Git branch: " .. env.git_branch)
  end
  table.insert(lines, "")

  -- Project context
  if #opts.project_context > 0 then
    table.insert(lines, "## Project Context")
    table.insert(lines, "")
    for _, file in ipairs(opts.project_context) do
      table.insert(lines, "### " .. file.path)
      table.insert(lines, "")
      table.insert(lines, file.content)
      table.insert(lines, "")
    end
  end

  return table.concat(lines, "\n")
end

return M
