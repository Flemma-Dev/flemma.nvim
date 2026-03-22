# Store, Proxy, and Lens Reference

## Store (`flemma.config.store`)

The store is **schema-free** — it stores operations and resolves paths. It has no knowledge of types or list semantics. Callers classify paths via the schema.

### Operations

```lua
store.record(layer, bufnr, "set", "provider", "anthropic")
store.record(layer, bufnr, "append", "tools.auto_approve", "bash")
store.record(layer, bufnr, "remove", "tools.auto_approve", "$default")
store.record(layer, bufnr, "prepend", "tools.modules", "my.tool")
```

- `bufnr` identifies the buffer for FRONTMATTER (L40). Ignored for global layers.
- `bufnr` is **asserted non-nil** for FRONTMATTER operations.

### Resolution

```lua
-- Scalar resolution (top-down, first set wins)
store.resolve("provider", bufnr)

-- List resolution (bottom-up, accumulate ops)
store.resolve("tools.auto_approve", bufnr, { is_list = true })

-- With source layer indicator
store.resolve_with_source("provider", bufnr)  -- value, "S"
store.resolve_with_source("tools", bufnr, { is_list = true })  -- value, "D+F"
```

**Scalar resolution:** Walk L40 → L30 → L20 → L10. First layer with `set` wins.

**List resolution:** Walk L10 → L20 → L30 → L40, building accumulator:
- `set` → reset accumulator
- `append` → add to end (dedup: if present, move to end)
- `prepend` → add to start (dedup: if present, move to start)
- `remove` → remove item (no-op if absent)

Source indicator concatenates contributing layer initials: `"D"`, `"S+F"`, `"D+S+R+F"`.

### Other Store API

```lua
store.init()                                  -- reset all layers
store.clear(layer, bufnr?)                    -- clear ops for one layer
store.dump_layer(layer, bufnr?)               -- deep copy of ops array
store.layer_has_set(layer, bufnr?, path)      -- boolean: has set op?
store.layer_has_op(layer, bufnr?, op, path, value?)  -- boolean: has specific op?
store.transform_ops(path, fn, ctx, bufnr?, opts?)    -- transform ops via coerce fn
store.make_coerce_context(bufnr?, is_list_fn?)       -- build context for transforms
```

## Read Proxy

Returned by `config.get(bufnr?)`. Read-only. Resolves through all layers.

```lua
local cfg = config.get(bufnr)
cfg.provider                    -- scalar read via store.resolve
cfg.tools.timeout               -- nested: proxy returns sub-proxy for objects
cfg.thinking                    -- alias resolves to parameters.thinking
cfg.provider = "x"             -- ERROR: read proxy is frozen
```

**How it works:** `__index` navigates the schema tree. At each level, aliases are checked (`resolve_alias`), then child schema nodes. Object nodes return a new sub-proxy scoped to that path. Leaf nodes resolve from the store.

## Write Proxy

Returned by `config.writer(bufnr?, layer)`. Targets a specific layer with schema validation.

```lua
local w = config.writer(bufnr, config.LAYERS.FRONTMATTER)
w[symbols.CLEAR]()              -- clear layer, returns self for chaining
w.provider = "openai"           -- records: set "provider" "openai"
w.parameters.timeout = 1200     -- records: set "parameters.timeout" 1200
w.thinking = "high"             -- alias: records set at "parameters.thinking"
```

**Writes are validated** against the schema before recording. Unknown keys on strict objects trigger DISCOVER (if available) or error. Coerce runs before validation.

### List Proxy

Write proxy for list-typed fields. Exposes methods and operators.

```lua
w.tools.modules:append("my.tool")    -- records append op
w.tools.modules:remove("old.tool")   -- records remove op
w.tools.modules:prepend("first")     -- records prepend op

-- Operators (same semantics)
w.tools.modules = w.tools.modules + "my.tool"   -- append
w.tools.modules = w.tools.modules - "old.tool"  -- remove
w.tools.modules = w.tools.modules ^ "first"     -- prepend

-- Full replacement
w.tools.modules = { "only", "these" }           -- records set op
```

**Operator chaining caveat:** Operators return the proxy sentinel, so `w.f = w.f + "a"` is a no-op assignment (the ops were already recorded by the `+`). The net effect is correct — only the append fires.

### Hybrid Proxy

For ObjectNode with `:allow_list()` (e.g., `tools`). Supports both sub-key navigation and list ops.

```lua
w.tools.timeout = 5000          -- sub-key write (object behavior)
w.tools:append("calculator")    -- list append (list behavior)
w.tools = { "bash", "grep" }   -- list set (sequential table assignment)
```

## Lens (Frozen Scoped View)

Read-only proxy rooted at a sub-path. Replaces `vim.deepcopy()` for passing config to consumers.

### Single-Path Lens

```lua
local bash_cfg = config.lens(bufnr, "tools.bash")
bash_cfg.cwd              -- reads config.tools.bash.cwd
bash_cfg.cwd = "/tmp"     -- ERROR: frozen
```

### Multi-Path Composed Lens (Path-First Priority)

```lua
local params = config.lens(bufnr, {
  "parameters.anthropic",   -- most specific, checked first
  "parameters",             -- general fallback
})

params.thinking_budget     -- checks anthropic-specific first (all layers),
                           -- then general (all layers)
```

**Path-first priority:** Most specific path checked through ALL layers before falling back. A provider-specific value in SETUP beats a general value in FRONTMATTER. This is like CSS specificity — writing to a more specific path makes the value harder to override from a less specific path at a higher layer.

## Facade Lifecycle API

```lua
-- Boot
config.init(schema)                           -- reset store, materialize L10 defaults
config.apply(layer, opts, { defer_discover = true })  -- bulk write from plain table
config.finalize(layer, deferred?)             -- replay deferred + re-run coerce

-- Frontmatter cycle
config.prepare_frontmatter(bufnr)             -- clear L40, return write proxy
config.coerce_frontmatter(bufnr)              -- run coerce on L40 ops

-- Registration
config.register_module_defaults(parent, name, schema)  -- materialize discovered defaults into L10
config.record_default(op, path, value)                  -- single op on L10
```

`prepare_frontmatter` + user code writes + `coerce_frontmatter` is the complete frontmatter evaluation cycle. The facade clears L40 before each evaluation — frontmatter is rebuilt from scratch every time.
