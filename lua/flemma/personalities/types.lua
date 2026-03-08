--- Type definitions for the personality system
---@class flemma.personalities.Types

---@class flemma.personalities.Personality
---@field render fun(opts: flemma.personalities.RenderOpts): string

---@class flemma.personalities.RenderOpts
---@field tools flemma.personalities.ToolEntry[]
---@field environment flemma.personalities.Environment
---@field project_context flemma.personalities.ProjectContextFile[]

---@class flemma.personalities.ToolEntry
---@field name string
---@field parts table<string, string[]>

---@class flemma.personalities.Environment
---@field cwd string
---@field current_file? string
---@field filetype? string
---@field git_branch? string
---@field date string
---@field time string

---@class flemma.personalities.ProjectContextFile
---@field path string
---@field content string
