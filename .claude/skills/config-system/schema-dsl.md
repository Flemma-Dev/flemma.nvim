# Schema DSL Reference

The schema (`lua/flemma/config/schema.lua`) is the single source of truth for all configuration structure, types, defaults, and validation.

## Primitives

```lua
local s = require("flemma.schema")

-- Scalars
s.string(default?)          -- s.string("anthropic")
s.integer(default?)         -- s.integer(8192)
s.number(default?)          -- s.number(0.7)
s.boolean(default?)         -- s.boolean(true)
s.enum(values, default?)    -- s.enum({"disabled","low","high"}, "low")

-- Compound
s.list(item_schema, default?)        -- ordered, supports append/remove/prepend
s.map(key_schema, value_schema)      -- open-ended dynamic keys
s.object(fields)                     -- fixed-shape, validates keys on write

-- Wrappers
s.optional(inner)                    -- nil is valid
s.union(schema_a, schema_b, ...)     -- first matching branch wins
s.literal(value)                     -- exact equality match

-- Domain-specific
s.loadable(default?)                 -- validates via flemma.loader
s.func()                             -- validates value is a function
```

## Method Chaining

All node methods return `self`:

```lua
s.object({ ... }):strict()           -- reject unknown keys (default)
s.object({ ... }):passthrough()      -- allow unknown keys
s.object({ ... }):allow_list(s.string())  -- hybrid: object fields + list ops on same path

s.optional(s.string()):describe("Human-readable description")
s.string():type_as("custom.Type")    -- override EmmyLua annotation
s.string():coerce(function(value, ctx) ... end)  -- value transformer
```

## Object Fields with Symbols

```lua
local symbols = require("flemma.symbols")

s.object({
  -- Regular fields
  timeout = s.integer(120000),
  enabled = s.boolean(true),

  -- Alias redirections (symbol key, no collision with string fields)
  [symbols.ALIASES] = {
    approve = "auto_approve",         -- alias at this level
    timeout = "parameters.timeout",   -- can cross into sub-objects
  },

  -- Lazy schema resolver for unknown keys (symbol key)
  [symbols.DISCOVER] = function(key)
    local mod = some_registry.get(key)
    if not mod then return nil end      -- nil = validation error
    return mod.metadata.config_schema   -- cached after first hit
  end,
})
```

**Resolution order for unknown keys:** real field > alias > DISCOVER > validation error.

## Coerce Transforms

Coerce runs **before validation** on every write. Also re-run by `finalize()` with populated context after modules register.

```lua
-- Signature: function(value, ctx?) -> transformed_value
-- ctx has: ctx.get(path) to read resolved config values

s.union(s.list(s.string()), s.func(), s.string())
  :coerce(function(value, ctx)
    if type(value) == "string" and value:sub(1, 1) == "$" then
      local preset = ctx and ctx.get("tools.presets." .. value:sub(2))
      return preset and preset.approve or value
    end
    return value
  end)
```

**Key coerce patterns in the schema:**
- `tools.auto_approve` — expands `$preset` strings to tool name lists
- `tools.autopilot` — coerces `boolean` to `{ enabled = bool }`
- Highlight fields — union of string (color) or object (full highlight spec)

## Adding a New Config Field

1. **Edit `definition.lua`** — add the field to the appropriate `s.object()`:
   ```lua
   my_feature = s.object({
     enabled = s.boolean(false),
     limit = s.optional(s.integer()),
   }),
   ```

2. **If the field belongs to a provider/tool/sandbox backend** — add `metadata.config_schema` on the module itself:
   ```lua
   -- In the module file
   M.metadata.config_schema = s.object({
     my_option = s.optional(s.string("default")),
   })
   ```
   The DISCOVER callback in `definition.lua` will resolve it lazily when first accessed.

3. **Run `make qa`** — the type checker and tests will catch schema mismatches.

## Adding a Top-Level Alias

In the root object of `definition.lua`:

```lua
[symbols.ALIASES] = {
  timeout = "parameters.timeout",
  thinking = "parameters.thinking",
  my_alias = "my_feature.enabled",     -- add here
},
```

Aliases resolve to canonical paths only, never to other aliases. They work at any schema level.

## Schema Node API

Every node supports:

| Method | Returns | Purpose |
|--------|---------|---------|
| `:materialize()` | default value or nil | Build default tree |
| `:validate_value(v)` | `ok, err?` | Type check a value |
| `:is_list()` | boolean | True for ListNode (and UnionNode with list branch) |
| `:is_object()` | boolean | True for ObjectNode |
| `:has_default()` | boolean | Whether node carries a default |
| `:get_child_schema(key)` | Node or nil | ObjectNode child lookup |
| `:get_item_schema()` | Node or nil | ListNode item type |
| `:resolve_alias(key)` | canonical path or nil | ObjectNode alias lookup |
| `:has_discover()` | boolean | ObjectNode has DISCOVER callback |
| `:all_known_fields()` | iterator | ObjectNode static + cached DISCOVER fields |

## Navigation

```lua
local nav = require("flemma.schema.navigation")

nav.navigate_schema(root, "tools.auto_approve")                    -- leaf node (OptionalNode preserved)
nav.navigate_schema(root, "tools.auto_approve", { unwrap_leaf = true })  -- unwrap OptionalNode
nav.unwrap_optional(node)                                          -- strip OptionalNode wrappers
```

The proxy uses `unwrap_leaf = false` (preserves OptionalNode so nil writes validate). The store uses `unwrap_leaf = true` (needs inner node for `is_list()` detection).
