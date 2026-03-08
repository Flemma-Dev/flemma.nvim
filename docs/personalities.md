# Personalities

Personalities are dynamic system prompt generators for `.chat` buffers. Each personality is a Lua module that assembles a markdown prompt from pre-built data — available tools, environment context, and project-specific files.

## Usage

Include a personality in your system prompt using the `include()` expression with a URN:

    @System:
    {{ include('urn:flemma:personality:coding-assistant') }}

The personality generates a complete system prompt section with tool listings, behavioral guidelines, environment context, and any project-level instructions it discovers.

## Built-in Personalities

### `coding-assistant`

Generates a prompt for LLM-powered coding assistance. Includes:

- **Core persona** — identifies the assistant as a coding-focused agent in Neovim
- **Available tools** — lists all enabled tools with short descriptions
- **Guidelines** — behavioral rules contributed by tool definitions
- **Environment** — working directory, current file, git branch, date/time
- **Project context** — auto-discovered files like `AGENTS.md`, `CLAUDE.md`, `.cursorrules`

#### Project Context Discovery

The personality scans the current directory for these files (in order):

1. `AGENTS.md`
2. `CLAUDE.md`
3. `.claude/CLAUDE.md`
4. `.cursorrules`
5. `.github/copilot-instructions.md`

Files with identical content (e.g., symlinks) are deduplicated — only the first match is included.

> [!NOTE]
> **Prompt caching:** The date and time in the environment section are captured once per buffer session and reused for all subsequent requests. This keeps the system prompt identical across requests, enabling LLM provider prompt caching. Other environment fields (working directory, current file, git branch) are always fresh. The cached date/time is cleared automatically when the buffer is wiped.

## Creating a Personality

Each personality is a Lua module at `lua/flemma/personalities/<name>.lua` that implements a `render()` function:

```lua
---@class flemma.personalities.MyPersonality : flemma.personalities.Personality
local M = {}

---@param opts flemma.personalities.RenderOpts
---@return string
function M.render(opts)
  local lines = {}
  table.insert(lines, "You are a specialized assistant.")
  table.insert(lines, "")
  -- Use opts.tools, opts.environment, opts.project_context
  -- to build your prompt however you like
  return table.concat(lines, "\n")
end

return M
```

Personalities are autonomous — Flemma does not prescribe a template or section structure. The personality owns its format entirely.

### RenderOpts

The `opts` table is pre-built before `render()` is called. The personality does no data gathering.

```lua
---@class flemma.personalities.RenderOpts
---@field tools flemma.personalities.ToolEntry[]
---@field environment flemma.personalities.Environment
---@field project_context flemma.personalities.ProjectContextFile[]
```

#### Tools

All enabled tools (respecting frontmatter opts), sorted alphabetically. Each entry has:

```lua
---@class flemma.personalities.ToolEntry
---@field name string
---@field parts table<string, string[]>
```

`parts` contains personality-specific data contributed by the tool definition, keyed by arbitrary part names. Tools without parts for this personality have an empty `parts` table.

#### Environment

```lua
---@class flemma.personalities.Environment
---@field cwd string
---@field current_file? string  -- relative to cwd
---@field filetype? string
---@field git_branch? string
---@field date string
---@field time string
```

#### Project Context

```lua
---@class flemma.personalities.ProjectContextFile
---@field path string   -- relative path
---@field content string
```

### Adding Parts to Tool Definitions

Tool definitions can contribute personality-specific parts via the `personalities` field:

```lua
{
  name = "my-tool",
  description = "Tool description for the API",
  input_schema = { ... },
  personalities = {
    ["coding-assistant"] = {
      snippet = "Short description for the tools list",
      guidelines = {
        "Use my-tool when you need to do X",
        "Always verify results before proceeding",
      },
    },
  },
}
```

Part names (`snippet`, `guidelines`, etc.) are not prescribed by Flemma. They are whatever the personality module expects to find. Single string values are normalized to `{ value }` when building opts.

### Registering a Built-in Personality

Add the module path to `BUILTIN_PERSONALITIES` in `lua/flemma/personalities/init.lua`:

```lua
local BUILTIN_PERSONALITIES = {
  ["coding-assistant"] = "flemma.personalities.coding-assistant",
  ["my-personality"] = "flemma.personalities.my-personality",
}
```

The personality is loaded via `flemma.loader` and registered during `setup()`.
