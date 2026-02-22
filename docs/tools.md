# Tools

Flemma's tool system lets models request actions – run a calculation, execute a shell command, read or modify files – and receive structured results, all within the `.chat` buffer. This document covers approval, per-buffer configuration, custom tool registration, and the resolver API.

For a quick overview of built-in tools and the basic workflow, see the [Tool Calling](../README.md#tool-calling) section in the README.

---

## Tool approval

By default, Flemma requires you to review tool calls before execution. A single keypress (<kbd>Ctrl-]</kbd>) drives the entire flow through three phases:

### The three-phase cycle

**Phase 1 – Categorize.** When the model responds with `**Tool Use:**` blocks, pressing <kbd>Ctrl-]</kbd> checks each tool call against your approval settings and injects a `**Tool Result:**` placeholder with a status:

| Status     | Meaning                                              |
| ---------- | ---------------------------------------------------- |
| `approved` | Auto-approved by policy; will execute immediately    |
| `pending`  | Requires your review; blocks the cycle until you act |
| `denied`   | Blocked by policy; an error result is injected       |

The cursor moves to the first `pending` placeholder so you can review it.

**Phase 2 – Execute.** On the next <kbd>Ctrl-]</kbd> (or automatically via `vim.schedule` when Phase 1 produced only `approved`/`denied` tools), Flemma processes each placeholder by status:

- **`approved`** → the tool executes and its output replaces the placeholder.
- **`denied`** → an error result is injected (the model sees the tool was blocked).
- **`rejected`** → an error result is injected, using any content you wrote inside the block as the error message.
- **`pending`** → blocks the cycle. The cursor moves here and Flemma waits for you to act.

**Phase 3 – Send.** When no `flemma:tool` placeholders remain (every tool has a real result), the next <kbd>Ctrl-]</kbd> sends the conversation to the provider.

With [autopilot](configuration.md#autopilot) enabled (the default), Phases 1–3 chain automatically for approved tools. You only interact when a tool lands on `pending`.

### Tool status blocks

Each placeholder is a fenced code block with a `flemma:tool` language tag and a status in its info string:

````
**Tool Result:** `toolu_01`

```flemma:tool status=pending
```
````

You can **edit the status directly** in the buffer. This is the primary way to interact with pending tools:

- **Approve:** change `status=pending` to `status=approved`, then press <kbd>Ctrl-]</kbd>.
- **Reject:** change `status=pending` to `status=rejected`, then press <kbd>Ctrl-]</kbd>. Flemma injects an error result telling the model the tool was rejected.
- **Reject with a message:** change the status to `rejected` and type your reason inside the block – the model sees your text as the error:

  ````
  ```flemma:tool status=rejected
  I don't want to run rm -rf on my home directory.
  ```
  ````

- **Execute one tool:** press <kbd>Alt-Enter</kbd> on any tool block to execute or resolve it immediately (works for `approved`, `pending`, `rejected`, and `denied`).

### Content-overwrite protection

If you type content inside an `approved` or `pending` block, Flemma treats it as a manual override: execution is skipped, the cycle pauses, and your content is sent to the model as-is. A warning is shown so you know what happened.

### Configuring approval

Out of the box, `auto_approve` is set to `{ "$default" }`, which auto-approves `read`, `write`, and `edit` while keeping `bash` gated behind manual approval. This gives you a working agent loop without opting out of safety for shell commands.

Disable approval entirely with `tools.require_approval = false` – this registers a catch-all resolver at priority 0 that auto-approves every tool call. Alternatively, use `tools.auto_approve` to build a custom policy with presets, tool names, or a function:

```lua
tools = {
  -- Preset references and tool names can be mixed freely
  auto_approve = { "$readonly", "calculator" },

  -- Function form for full control
  auto_approve = function(tool_name, input, ctx)
    if tool_name == "calculator" then return true end
    if tool_name == "bash" and input.command:match("rm %-rf") then return "deny" end
    return false  -- require approval
  end,
}
```

### Approval presets

Presets are named collections of tool approval rules referenced with a `$` prefix in `auto_approve`. They keep common policies concise and composable.

**Built-in presets:**

| Preset      | Approves                | Description                                        |
| ----------- | ----------------------- | -------------------------------------------------- |
| `$readonly` | `read`                  | Read-only access – safe for exploration buffers    |
| `$default`  | `read`, `write`, `edit` | File operations without shell access (the default) |

**User-defined presets** override built-ins by name. Define them in `tools.presets`:

```lua
tools = {
  presets = {
    ["$yolo"]    = { approve = { "bash", "read", "write", "edit" } },
    ["$no-bash"] = { deny = { "bash" } },
  },
  auto_approve = { "$yolo", "$no-bash" },
}
```

Each preset is a table with optional `approve` and `deny` arrays:

- **`approve`** – tool names to auto-approve.
- **`deny`** – tool names to deny outright (an error result is injected).

**Composition rules:**

- **Union.** When multiple presets appear in `auto_approve`, their `approve` and `deny` sets are merged.
- **Deny wins.** If a tool appears in both `approve` (from one preset) and `deny` (from another), the tool is denied. This lets you layer a restrictive preset on top of a permissive one.
- **Plain tool names** mix freely with presets: `{ "$default", "calculator" }` approves everything in `$default` plus `calculator`.

### Per-buffer approval

Override approval on a per-buffer basis using `flemma.opt.tools.auto_approve` in Lua frontmatter. This works alongside the global `tools.auto_approve` config – global config is checked first (priority 100), then per-buffer frontmatter (priority 90):

````lua
```lua
-- Preset form: read-only access for this buffer
flemma.opt.tools.auto_approve = { "$readonly" }

-- List form: auto-approve these tools in this buffer
flemma.opt.tools.auto_approve = { "calculator", "read" }

-- Mix presets and tool names
flemma.opt.tools.auto_approve = { "$default", "bash" }

-- Function form: full control per-buffer
flemma.opt.tools.auto_approve = function(tool_name, input, ctx)
  if tool_name == "calculator" then return true end
  return nil  -- pass to next resolver
end
```
````

The function form returns `true` (approve), `false` (require approval), `"deny"` (block), or `nil` (pass to the next resolver in the chain).

**ListOption operations** let you modify the default policy incrementally instead of replacing it:

````lua
```lua
-- Start from default, but remove write access
flemma.opt.tools.auto_approve = { "$default" }
flemma.opt.tools.auto_approve:remove("write")

-- Add bash to the default set
flemma.opt.tools.auto_approve = { "$default" }
flemma.opt.tools.auto_approve:append("bash")

-- Operator shorthand: + (append), - (remove)
flemma.opt.tools.auto_approve = flemma.opt.tools.auto_approve + "bash" - "write"
```
````

When you `:remove()` a tool that lives inside a preset (e.g., removing `"write"` from `{ "$default" }`), the tool is excluded at expansion time – the preset itself stays in the list, but the named tool is filtered out when the resolver evaluates it.

---

## Tool execution

- **Async tools** (like `bash`) show an animated spinner while running and can be cancelled.
- **Buffer locking** – the buffer is made non-modifiable during tool execution to prevent race conditions.
- **Output truncation** – large outputs (> 2000 lines or 50 KB) are automatically truncated. The full output is saved to a temporary file.
- **Cursor positioning** – after injection, the cursor can move to the result (`"result"`), stay put (`"stay"`), or jump to the next `@You:` prompt (`"next"`). Controlled by `tools.cursor_after_result`.

### Parallel tool use

All three providers support parallel tool calls. Press <kbd>Ctrl-]</kbd> to execute all pending calls at once, or use <kbd>Alt-Enter</kbd> on individual blocks. Flemma validates that every `**Tool Use:**` block has a matching `**Tool Result:**` before sending.

---

## Tool previews

When a tool call is pending approval, its `flemma:tool` placeholder block is empty – you'd normally need to scroll up to the `**Tool Use:**` block to see what the tool will do. Tool previews eliminate that: Flemma renders a virtual line inside each empty placeholder showing a compact summary of the tool call.

For example, a pending `read` tool might show:

```
read: src/config.lua  +0,50  # reading config
```

And a pending `bash` tool:

```
bash: $ make test  # running tests
```

Previews are non-editable virtual text (extmarks) that disappear once the tool executes and its result replaces the placeholder. They adapt to the editor's text area width, truncating with `…` when necessary.

### Built-in preview formatters

Every built-in tool ships with a tailored `format_preview` function:

| Tool               | Preview format                                     | Example                                     |
| ------------------ | -------------------------------------------------- | ------------------------------------------- |
| `calculator`       | The expression directly                            | `calculator: 2 + 2`                         |
| `calculator_async` | Expression with optional delay                     | `calculator_async: sqrt(16)  # 500ms`       |
| `bash`             | `$ command` with optional label                    | `bash: $ git status  # checking repo`       |
| `read`             | Path with optional `+offset,limit` range and label | `read: config.lua  +100,50  # reading tail` |
| `edit`             | Path with optional label                           | `edit: config.lua  # fixing typo`           |
| `write`            | Path with content size and optional label          | `write: output.txt  (2.3 KB)  # saving log` |

### Generic fallback

Tools without a `format_preview` function get a generic key-value summary: `tool_name: key1="val1", key2="val2"`. Scalar values appear first (sorted alphabetically), followed by table values shown as `{key1, key2}` or `[N items]`.

### Custom preview formatters

Register a `format_preview` function on your tool definition to control how it appears in pending placeholders:

```lua
tools.register("my_search", {
  name = "my_search",
  description = "Search a knowledge base",
  input_schema = {
    type = "object",
    properties = {
      query = { type = "string", description = "Search query" },
      limit = { type = { "number", "null" }, description = "Max results" },
    },
    required = { "query", "limit" },
    additionalProperties = false,
  },
  format_preview = function(input, max_length)
    -- input: the tool's input arguments table
    -- max_length: available width after the "my_search: " prefix
    local preview = '"' .. input.query .. '"'
    if input.limit then
      preview = preview .. " (limit " .. input.limit .. ")"
    end
    return preview
  end,
  execute = function(input, context, callback) --[[ ... ]] end,
})
```

The function receives the input table and the available character width (the total preview width minus the `"name: "` prefix). Return a single-line string; newlines are collapsed to `⤶` and the result is truncated to fit the editor width.

### Styling

Tool previews use the `FlemmaToolPreview` highlight group (default: linked to `Comment`). Customise via `highlights.tool_preview` in your config – see [docs/ui.md](ui.md#highlights-and-styles) for details.

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
  format_preview = function(input, max_length)
    return '"' .. input.query:sub(1, max_length - 2) .. '"'
  end,
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

## ExecutionContext

Every tool's `execute` function receives up to three arguments: `input`, `context`, and an optional `callback`. The context is an `ExecutionContext` object that provides the stable contract tools code against – tools should never `require()` internal Flemma modules directly.

```lua
-- Sync tools: return an ExecutionResult directly
execute = function(input, ctx)
  return { success = true, output = "done" }
end

-- Async tools: call callback(result) when done, return a cancel function
execute = function(input, ctx, callback)
  -- ...
end
```

### Core fields

| Field            | Type      | Description                                                      |
| ---------------- | --------- | ---------------------------------------------------------------- |
| `ctx.bufnr`      | `integer` | Buffer number for the current execution                          |
| `ctx.cwd`        | `string`  | Absolute working directory (resolved from config or Neovim)      |
| `ctx.timeout`    | `integer` | Default timeout in seconds (from `config.tools.default_timeout`) |
| `ctx.__dirname`  | `string?` | Directory containing the `.chat` buffer (`nil` for unsaved)      |
| `ctx.__filename` | `string?` | Full path of the `.chat` buffer (`nil` for unsaved)              |

### Namespaces

The following namespaces are lazy-loaded on first access (zero cost if unused):

#### `ctx.path` – Path resolution

```lua
local absolute = ctx.path.resolve("relative/file.txt")
-- Resolves against __dirname (or cwd if buffer is unsaved)
-- Absolute paths pass through unchanged
```

#### `ctx.sandbox` – Sandbox enforcement

```lua
-- Check if a path is writable under the current sandbox policy
if not ctx.sandbox.is_path_writable(path) then
  return { success = false, error = "Sandbox: path not writable" }
end

-- Wrap a command for sandbox enforcement (returns nil + error on failure)
local wrapped_cmd, err = ctx.sandbox.wrap_command({ "bash", "-c", "echo hello" })
```

#### `ctx.truncate` – Output truncation

```lua
-- Truncate from the end (keep last N lines/bytes) – use for streaming output
local result = ctx.truncate.truncate_tail(full_output)
-- result.content, result.truncated, result.total_lines, result.output_lines, ...

-- Truncate from the start (keep first N lines/bytes) – use for file reads
local result = ctx.truncate.truncate_head(content)

-- Format byte counts for display
local size_str = ctx.truncate.format_size(12345)  -- "12.1 KB"

-- Constants
ctx.truncate.MAX_LINES  -- 2000
ctx.truncate.MAX_BYTES  -- 51200 (50 KB)
```

### `ctx:get_config()` – Tool-specific config

Returns a read-only copy of `config.tools[tool_name]`, or `nil` if no config subtree exists for this tool. The returned table is a deep copy – modifications do not affect the global config.

```lua
local tool_config = ctx:get_config()
if tool_config and tool_config.shell then
  -- Use configured shell
end
```

### Complete example

```lua
tools.register("export", {
  name = "export",
  description = "Save content to a file in the project",
  input_schema = {
    type = "object",
    properties = {
      path = { type = "string", description = "Output file path (relative or absolute)" },
      content = { type = "string", description = "Content to write" },
    },
    required = { "path", "content" },
    additionalProperties = false,
  },
  strict = true,
  async = false,
  execute = function(input, ctx)
    local path = ctx.path.resolve(input.path)

    if not ctx.sandbox.is_path_writable(path) then
      return { success = false, error = "Sandbox: write denied for " .. input.path }
    end

    -- Use tool-specific config (e.g. config.tools.export = { max_size = 102400 })
    local tool_config = ctx:get_config()
    local max_size = (tool_config and tool_config.max_size) or ctx.truncate.MAX_BYTES

    if #input.content > max_size then
      return {
        success = false,
        error = "Content exceeds " .. ctx.truncate.format_size(max_size) .. " limit",
      }
    end

    -- ... write logic ...

    return { success = true, output = "Saved " .. #input.content .. " bytes to " .. input.path }
  end,
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

| Priority | Name                              | Source                                                      |
| -------- | --------------------------------- | ----------------------------------------------------------- |
| 100      | `urn:flemma:approval:config`      | Global `tools.auto_approve` from config (list or function)  |
| 100      | `<module.path>`                   | Per-module resolver from `tools.auto_approve` module path   |
| 90       | `urn:flemma:approval:frontmatter` | Per-buffer `flemma.opt.tools.auto_approve` from frontmatter |
| 0        | `urn:flemma:approval:catch-all`   | Only when `tools.require_approval = false`                  |

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
approval.get("urn:flemma:approval:config")  -- returns the resolver entry or nil
approval.get_all()                    -- all resolvers sorted by priority (deep copy)
approval.count()                      -- number of registered resolvers
```
