# Custom Tools

Flemma's tool system is extensible. You can register your own tools to let models interact with external services, run project-specific commands, or integrate with other plugins.

For built-in tools, approval flow, and general tool usage, see the [Tool Calling](../README.md#tool-calling) section in the README.

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
