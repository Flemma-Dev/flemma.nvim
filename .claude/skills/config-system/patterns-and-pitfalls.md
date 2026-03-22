# Common Patterns and Pitfalls

## Reading Config in Production Code

```lua
local config = require("flemma.config")

-- Most common: static key reads
local cfg = config.get(bufnr)
local timeout = cfg.tools.timeout
local provider = cfg.provider

-- When you need pairs(), dynamic keys, or vim.deepcopy
local t = config.materialize(bufnr)
for k, v in pairs(t.parameters) do ... end
local tool_cfg = t.tools[tool_name]
```

## Writing Config at Runtime

```lua
local config = require("flemma.config")
local symbols = require("flemma.symbols")

-- Runtime writes (e.g., :Flemma switch)
local w = config.writer(nil, config.LAYERS.RUNTIME)
w.provider = "openai"
w.model = "gpt-4o"
w.parameters.timeout = 600

-- Frontmatter writes (inside frontmatter evaluation)
local w = config.prepare_frontmatter(bufnr)
w.parameters.thinking = "high"
w.tools:append("calculator")
```

Runtime ops **accumulate** across commands. Later `set` on the same path overrides earlier ones; untouched paths persist.

## Adding a New Config Field

1. Edit `lua/flemma/config/schema.lua`
2. Add the field to the appropriate `s.object()`
3. Run `make qa`

For provider/tool/sandbox-specific config, add `metadata.config_schema` on the module — DISCOVER resolves it lazily.

## Testing Config-Dependent Code

### Facade Initialization Pattern

Every test that touches config needs this in `before_each`:

```lua
local config_facade = require("flemma.config")
local definition = require("flemma.config.schema")

before_each(function()
  -- Clear module caches for isolation
  package.loaded["flemma.config"] = nil
  package.loaded["flemma.config.store"] = nil
  package.loaded["flemma.config.proxy"] = nil
  package.loaded["flemma.config.schema"] = nil

  -- Re-require after clearing
  config_facade = require("flemma.config")
  definition = require("flemma.config.schema")

  -- Initialize with schema defaults
  config_facade.init(definition)
end)
```

### Applying Test Config

```lua
-- Apply setup values
config_facade.apply(config_facade.LAYERS.SETUP, {
  provider = "anthropic",
  model = "claude-sonnet-4-20250514",
  tools = { timeout = 5000 },
})

-- For code that needs materialize()
local cfg = config_facade.materialize()
```

### Testing Frontmatter Overrides

```lua
-- Write to frontmatter layer for a buffer
local w = config_facade.writer(bufnr, config_facade.LAYERS.FRONTMATTER)
w.parameters.thinking = "high"
w.tools.auto_approve = { "bash", "grep" }

-- Read back
local cfg = config_facade.get(bufnr)
assert.equals("high", cfg.parameters.thinking)
```

### Pipeline Tests

`pipeline.run()` requires `opts.bufnr`:

```lua
pipeline.run(lines, { bufnr = 0 })
```

## Critical Pitfalls

### Clear Modules Together

When re-requiring the config facade in tests, also clear store, proxy, and definition — stale cross-references cause silent misrouting:

```lua
package.loaded["flemma.config"] = nil
package.loaded["flemma.config.store"] = nil
package.loaded["flemma.config.proxy"] = nil
package.loaded["flemma.config.schema"] = nil
```

### Clear Executor with Sandbox

`executor.lua` captures `sandbox_module` at require time. If you clear `flemma.sandbox` without clearing `flemma.tools.executor`, sandbox checks silently pass:

```lua
package.loaded["flemma.tools.executor"] = nil
package.loaded["flemma.sandbox"] = nil
```

### `apply_recursive` Aborts on First Error

If any sub-path fails validation, the entire `apply()` aborts — no partial writes. Don't mix DISCOVER-requiring keys with valid fields in the same `apply()` call unless modules are already registered.

### Hybrid Object Reads Return Sub-Proxy

`cfg.tools` on a read proxy returns an **object sub-proxy** (for `cfg.tools.timeout`), not the list value. To get the resolved tool name list, use `config.inspect(bufnr, "tools")` or `store.resolve("tools", bufnr, { is_list = true })`.

### DISCOVER Misses Are Not Cached

Returning `nil` from DISCOVER doesn't cache — the callback fires again next time. This is intentional for the two-pass boot where modules register between passes.

### `make qa` Only

Do not invoke `nvim` directly with Plenary commands. Only `make qa` is wired correctly for running tests.

### Run `make qa` Bare

Never pipe it through `grep`/`tail`/`head`. It's silent on success and self-explanatory on failure.

### `__pairs` Guard Is Ineffective Under LuaJIT

Config proxies define `__pairs` that errors to prevent accidental iteration on proxy objects. But Neovim uses LuaJIT (Lua 5.1 semantics), which ignores `__pairs`. Calling `pairs()` on a proxy silently returns an empty iterator instead of erroring. **Always use `config.materialize()` when you need `pairs()`, dynamic key access, `vim.deepcopy()`, or `vim.inspect()`.**

### `get()` vs `materialize()` Decision Tree

| Need | Use |
|------|-----|
| Static key reads (`cfg.provider`, `cfg.tools.timeout`) | `config.get(bufnr)` |
| `pairs()` iteration | `config.materialize(bufnr)` |
| Dynamic key access (`t[variable]`) | `config.materialize(bufnr)` |
| `vim.deepcopy()` / `vim.inspect()` | `config.materialize(bufnr)` |
| User-provided callbacks receiving config | `config.materialize(bufnr)` |

## Provider Parameter Resolution

Providers use composed lenses for parameter resolution:

```lua
local params = config.lens(bufnr, {
  "parameters." .. provider_name,   -- provider-specific first
  "parameters",                      -- general fallback
})
```

Path-first priority means provider-specific params in SETUP beat general params in FRONTMATTER. Write provider-specific params to `parameters.<provider>.*` and general params to `parameters.*`.

## Frontmatter Integration

`flemma.opt` IS a `config.writer(bufnr, FRONTMATTER)`. The frontmatter execution cycle:

1. `config.prepare_frontmatter(bufnr)` — clears L40, returns write proxy
2. Frontmatter code executes with `flemma.opt = writer`
3. `config.finalize(FRONTMATTER, nil, reporter, bufnr)` — runs coerce + deferred validation on L40 ops

Between evaluations, L40 retains its state. The layer is only rebuilt on explicit evaluation (before send, before status display).
