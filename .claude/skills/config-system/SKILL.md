---
name: config-system
description: Use when reading, writing, extending, or testing Flemma configuration — covers the CoW layer store, schema DSL, proxy/lens API, and common patterns. Trigger on any work touching flemma.config, flemma.opt, config.get, config.writer, config.materialize, config.lens, schema definition, DISCOVER callbacks, or setup/frontmatter wiring.
---

# Flemma Config System

Copy-on-Write layers with a declarative schema. One system, one API, one mental model.

## Architecture

4 layers store **operations** (not values). Reads replay ops across layers.

| Priority | Layer        | Scope      | Written by                      |
|----------|--------------|------------|---------------------------------|
| L10      | DEFAULTS     | global     | Schema materialization at boot  |
| L20      | SETUP        | global     | `require("flemma").setup(opts)` |
| L30      | RUNTIME      | global     | `:Flemma switch`, runtime cmds  |
| L40      | FRONTMATTER  | per-buffer | `flemma.opt.*` in frontmatter   |

**Scalars:** Top-down (L40 first), first `set` wins.
**Lists:** Bottom-up (L10 first), accumulate `set`/`append`/`remove`/`prepend`.

## Module Map

```
lua/flemma/config/
  init.lua              -- Public facade (flemma.config)
  store.lua             -- Layer store: ops log, resolution
  proxy.lua             -- Read/write/list/lens proxy metatables
  schema/
    init.lua            -- Schema DSL factory (s.string, s.object, etc.)
    types.lua           -- Node type hierarchy
    definition.lua      -- THE schema (source of truth for all config)
    navigation.lua      -- Schema tree traversal helpers
```

## API Quick Reference

```lua
local config = require("flemma.config")
local symbols = require("flemma.symbols")

-- READ (most code does this)
local cfg = config.get(bufnr)        -- read proxy
cfg.tools.timeout                     -- nested reads
cfg.thinking                          -- alias -> parameters.thinking

-- MATERIALIZE (when you need a plain table)
local t = config.materialize(bufnr)   -- for pairs(), deepcopy, dynamic keys

-- WRITE
local w = config.writer(bufnr, config.LAYERS.RUNTIME)
w[symbols.CLEAR]()                    -- clear layer (returns self)
w.provider = "openai"                 -- scalar set
w.tools.modules:append("my.tool")     -- list append / :remove() / :prepend()

-- LENS (frozen scoped view)
config.lens(bufnr, "tools.bash")
config.lens(bufnr, { "parameters.anthropic", "parameters" })  -- path-first priority

-- INTROSPECT
config.inspect(bufnr, "provider")     -- { value, layer = "S" }
config.LAYERS                         -- { DEFAULTS=10, SETUP=20, RUNTIME=30, FRONTMATTER=40 }
```

### get() vs materialize()

| Need | Use |
|------|-----|
| Static key reads (`cfg.tools.timeout`) | `get(bufnr)` |
| `pairs()` / iteration / dynamic keys | `materialize(bufnr)` |
| `vim.deepcopy()` / `vim.inspect()` | `materialize(bufnr)` |
| Callbacks receiving config | `materialize(bufnr)` |

## Key Invariants

- **Store is schema-free.** Callers pass `{ is_list = true }` to resolution. The facade owns the schema.
- **Providers are request-scoped.** Created in `send_to_provider()`, GC'd after. No global instance.
- **All config reads go through the facade** — `config.get()` or `config.materialize()`.
- **DISCOVER callbacks lazy-require.** `definition.lua` is pure data — inline `require()` in callbacks avoids circular deps.
- **`auto_approve` always defaults to `{ "$standard" }`.** "Not configured" doesn't exist.
- **Hybrid objects** (`tools`) support sub-key navigation AND list ops on the same path.

## Reference Files

Read these when you need depth on a specific area:

| File | When to read |
|------|-------------|
| `schema-dsl.md` | Adding config fields, extending schema, understanding validation/coerce |
| `store-and-proxy.md` | Resolution mechanics, proxy behavior, lens composition, write patterns |
| `patterns-and-pitfalls.md` | Writing/testing config-dependent code, avoiding known gotchas |

All reference files are in this skill's directory (`.claude/skills/config-system/`).
