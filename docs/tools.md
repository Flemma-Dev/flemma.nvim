# Tools

Flemma's tool system lets models request actions — run a calculation, execute a shell command, read or modify files — and receive structured results, all within the `.chat` buffer. This document covers approval, per-buffer configuration, custom tool registration, and the resolver API.

For a quick overview of built-in tools and the basic workflow, see the [Tool Calling](../README.md#tool-calling) section in the README.

---

## Tool approval

By default, Flemma requires you to review tool calls before execution (<kbd>Ctrl-]</kbd> enters a three-phase cycle):

1. **Inject placeholders** – empty `**Tool Result:**` blocks are added, fenced with `` `flemma:pending ``. The cursor moves to the first placeholder.
2. **Execute** – press <kbd>Ctrl-]</kbd> again. Pending placeholders are executed; any you edited are treated as manual overrides.
3. **Send** – once every tool has a result, the next <kbd>Ctrl-]</kbd> sends the conversation.

Disable approval entirely with `tools.require_approval = false`. Use `tools.auto_approve` to whitelist specific tools or write a custom policy function:

```lua
tools = {
  auto_approve = { "calculator", "read" },       -- list form
  auto_approve = function(tool_name, input, ctx)  -- function form
    if tool_name == "calculator" then return true end
    if tool_name == "bash" and input.command:match("rm %-rf") then return "deny" end
    return false  -- require approval
  end,
}
```

### Per-buffer approval

Override approval on a per-buffer basis using `flemma.opt.tools.auto_approve` in Lua frontmatter. This works alongside the global `tools.auto_approve` config — global config is checked first (priority 100), then per-buffer frontmatter (priority 90):

````lua
```lua
-- List form: auto-approve these tools in this buffer
flemma.opt.tools.auto_approve = { "calculator", "read" }

-- Function form: full control per-buffer
flemma.opt.tools.auto_approve = function(tool_name, input, ctx)
  if tool_name == "calculator" then return true end
  return nil  -- pass to next resolver
end
```
````

The function form returns `true` (approve), `false` (require approval), `"deny"` (block), or `nil` (pass to the next resolver in the chain).

---

## Tool execution

- **Async tools** (like `bash`) show an animated spinner while running and can be cancelled.
- **Buffer locking** – the buffer is made non-modifiable during tool execution to prevent race conditions.
- **Output truncation** – large outputs (> 4000 lines or 8 MB) are automatically truncated. The full output is saved to a temporary file.
- **Cursor positioning** – after injection, the cursor can move to the result (`"result"`), stay put (`"stay"`), or jump to the next `@You:` prompt (`"next"`). Controlled by `tools.cursor_after_result`.

### Parallel tool use

All three providers support parallel tool calls. Press <kbd>Ctrl-]</kbd> to execute all pending calls at once, or use <kbd>Alt-Enter</kbd> on individual blocks. Flemma validates that every `**Tool Use:**` block has a matching `**Tool Result:**` before sending.

---

## Per-buffer tool selection

Control which tools are available per-buffer using `flemma.opt` in Lua frontmatter:

````lua
```lua
flemma.opt.tools = {"bash", "read"}             -- only these tools
flemma.opt.tools:remove("calculator")           -- remove from defaults
flemma.opt.tools:append("calculator_async")     -- add a tool
flemma.opt.tools = flemma.opt.tools + "read"    -- operator overloads work too
```
````

Each evaluation starts from defaults (all enabled tools). Misspelled tool names produce an error with a "did you mean" suggestion.

### Per-buffer parameter overrides

General and provider-specific parameters can be overridden per-buffer using `flemma.opt` in Lua frontmatter:

````lua
```lua
-- General parameters (work across all providers)
flemma.opt.thinking = "medium"          -- override the unified thinking level
flemma.opt.cache_retention = "long"     -- override prompt caching strategy
flemma.opt.max_tokens = 8000            -- override max output tokens
flemma.opt.temperature = 0.3            -- override sampling temperature

-- Provider-specific overrides (take priority over general)
flemma.opt.anthropic.thinking_budget = 20000
flemma.opt.openai.reasoning = "high"
flemma.opt.vertex.thinking_budget = 4096
```
````

When both general and provider-specific parameters are set, provider-specific values win. For example, setting both `flemma.opt.thinking = "low"` and `flemma.opt.anthropic.thinking_budget = 20000` will use 20,000 tokens on Anthropic.

---

## Registering custom tools

`require("flemma.tools").register()` is a single entry point that accepts several forms:

**Single definition** – pass a name and definition table:

```lua
local tools = require("flemma.tools")
tools.register("my_tool", {
  name = "my_tool",
  description = "Does something useful",
  input_schema = {
    type = "object",
    properties = {
      query = { type = "string", description = "The input query" },
    },
    required = { "query" },
  },
  execute = function(input)
    return { success = true, output = "done: " .. input.query }
  end,
})
```

**Module name** – pass a module path. If the module exports `.definitions` (an array of definition tables), they are registered synchronously. If it exports `.resolve(register, done)`, it is registered as an async source (see [Async tool definitions](#async-tool-definitions)):

```lua
tools.register("my_plugin.tools.search")
```

**Batch** – pass an array of definition tables:

```lua
tools.register({
  { name = "tool_a", description = "...", input_schema = { type = "object", properties = {} } },
  { name = "tool_b", description = "...", input_schema = { type = "object", properties = {} } },
})
```

---

## Strict mode for tool schemas

OpenAI's Responses API supports [strict mode](https://platform.openai.com/docs/guides/structured-outputs) for function calling, which guarantees that the model's arguments will conform exactly to your JSON Schema. All of Flemma's built-in tools use strict mode.

To opt in for your custom tools, set `strict = true` on the definition and ensure the `input_schema` meets OpenAI's strict-mode requirements:

- All properties must be listed in `required`
- The schema must include `additionalProperties = false`
- Optional parameters use a nullable type array instead of being omitted from `required`:

```lua
tools.register("my_tool", {
  name = "my_tool",
  description = "Does something",
  strict = true,
  input_schema = {
    type = "object",
    properties = {
      query   = { type = "string", description = "Required input" },
      max_results = { type = { "number", "null" }, description = "Optional limit (default: 10)" },
    },
    required = { "query", "max_results" },
    additionalProperties = false,
  },
  execute = function(input)
    local limit = input.max_results or 10
    return { success = true, output = "found results" }
  end,
})
```

When `strict` is not set (or set to `false`), the field is omitted from the API request entirely. Schema validation is your responsibility when opting in – Flemma passes the schema through as-is.

---

## Async tool definitions

Tool definitions that need to call external processes or remote APIs can resolve asynchronously. Flemma gates API requests on all sources being ready – if you send while definitions are still loading, the buffer shows "Waiting for tool definitions to load..." and auto-sends once everything resolves.

**Function form** – pass a resolve function directly:

```lua
tools.register(function(register, done)
  vim.fn.jobstart({ "my-cli", "list-tools" }, {
    on_exit = function()
      register("discovered_tool", { --[[ definition ]] })
      done()       -- signals this source is complete
    end,
  })
end)
```

**Table form** – pass a table with `.resolve` and an optional `.timeout` (seconds):

```lua
tools.register({
  timeout = 60,
  resolve = function(register, done)
    -- fetch definitions from a remote API...
    register("remote_tool", { --[[ definition ]] })
    done()
  end,
})
```

**Module form** – export a `resolve` function from your module:

```lua
-- In lua/my_plugin/tools.lua
local M = {}

function M.resolve(register, done)
  -- async work...
  register("my_tool", { --[[ definition ]] })
  done()
end

M.timeout = 45  -- optional, defaults to tools.default_timeout (30s)

return M
```

```lua
-- In your setup:
tools.register("my_plugin.tools")
```

Key details:

- **`register(name, def)`** can be called multiple times within a single source to register several tools.
- **`done(err?)`** must be called exactly once. Pass an error string to signal failure (the source completes but a warning is shown). Double-calling `done()` is safe (idempotent).
- **Timeout** – if `done()` is never called, the source times out after `tools.default_timeout` seconds (default 30). This prevents a broken source from blocking requests forever.
- **Error handling** – if the resolve function throws, `done(err)` is called automatically.

---

## Approval resolvers

Flemma uses a priority-based resolver chain to decide whether a tool call should be auto-approved, require user approval, or be denied. The chain evaluates resolvers in priority order (highest first); the first non-nil result wins. If no resolver returns a decision, the default is `"require_approval"`.

Built-in resolvers are registered during `setup()`:

| Priority | Name                       | Source                                                      |
| -------- | -------------------------- | ----------------------------------------------------------- |
| 100      | `config:auto_approve`      | Global `tools.auto_approve` from config                     |
| 90       | `frontmatter:auto_approve` | Per-buffer `flemma.opt.tools.auto_approve` from frontmatter |
| 0        | `config:catch_all_approve` | Only when `tools.require_approval = false`                  |

Third-party plugins register at the default priority of 50. Set `priority` higher to run before built-in resolvers (e.g., 200 to override config), or lower to act as a fallback.

### Registering a resolver

```lua
local approval = require("flemma.tools.approval")

approval.register("my_plugin:security_policy", {
  description = "Block dangerous bash commands",
  resolve = function(tool_name, input, context)
    if tool_name == "bash" and input.command:match("rm %-rf") then
      return "deny"
    end
    return nil  -- pass to next resolver
  end,
})
```

The `resolve` function receives:

- **`tool_name`** (`string`) – the name of the tool being called (e.g., `"bash"`, `"calculator"`).
- **`input`** (`table`) – the tool call's input arguments.
- **`context`** (`table`) – contains `bufnr` (buffer number) and `tool_id` (unique ID for this tool call).

Return values:

| Return value         | Effect                                              |
| -------------------- | --------------------------------------------------- |
| `"approve"`          | Auto-approve; skip the approval placeholder step    |
| `"require_approval"` | Show the placeholder and wait for user confirmation |
| `"deny"`             | Block execution; inject an error result             |
| `nil`                | Pass; let the next resolver in the chain decide     |

If a resolver throws an error, it is logged and skipped (treated as `nil`).

### Unregistering a resolver

```lua
approval.unregister("my_plugin:security_policy")  -- returns true if found
```

Re-registering with the same name replaces the existing resolver.

### Introspection

```lua
approval.get("config:auto_approve")   -- returns the resolver entry or nil
approval.get_all()                    -- all resolvers sorted by priority (deep copy)
approval.count()                      -- number of registered resolvers
```
