# Config Overhaul Progress

## Completed

- [x] Schema DSL (`flemma.config.schema` + `flemma.config.schema.types`) + `symbols.ALIASES`/`symbols.DISCOVER` — `1fa30ad` — 2026-03-19
- [x] Layer store (`flemma.config.store` + `tests/flemma/config/store_spec.lua`) — `dbdbbd2` — 2026-03-19
- [x] Proxy metatables (`flemma.config.proxy` + `tests/flemma/config/proxy_spec.lua`) + shared schema navigation (`flemma.config.schema.navigation`) — `43e49ee` — 2026-03-19
- [x] Alias, list ops, DISCOVER test suites (69 tests total across 3 files) — `4fb725f` — 2026-03-19
- [x] Lens test suite (`tests/flemma/config/lens_spec.lua`, 21 tests) — single-path, multi-path, path-first priority, alias resolution, nested object navigation, buffer isolation, freezing — `91b9922` — 2026-03-19
- [x] Public API facade (`flemma.config.facade`) + integration test suite (`tests/flemma/config/integration_spec.lua`, 28 tests) — defaults materialization, apply from plain table, multi-layer composition, alias flow e2e, provider lens composition, buffer isolation, introspection — `91b9922` — 2026-03-19
- [x] Schema definition (`flemma.config.schema.definition`) + definition test suite (`tests/flemma/config/definition_spec.lua`, 36 tests) — full translation of config.lua into schema DSL, provider parameter schemas, DISCOVER callbacks, aliases, union/map default support — `1cfbbea` — 2026-03-20
- [x] `defer_discover` + `apply_deferred()` in facade + `materialize()` + setup wiring (15 new integration tests) — uncommitted — 2026-03-20

## Pending Tests

_None._

## Decisions & Deviations

- **DISCOVER misses are intentionally not cached.** During the two-pass boot, a DISCOVER callback returns nil on pass 1 (modules not yet registered) but may succeed on pass 2. Caching nil would permanently block future successful resolutions. The correct behavior: cache only hits; invoke the callback fresh for every miss. This is a feature, not a bug.

- **`BooleanNode` needs no `has_default()` override.** `false ~= nil` is `true` in Lua — `ScalarNode:has_default()` handles boolean defaults correctly without any subclass override. Dead overrides that are identical to the parent are noise, not clarity.

- **`LoadableNode` should inherit from `StringNode`.** A loadable value IS-A string with an additional constraint. Inheriting from `StringNode` eliminates the duplicate type check and gives `LoadableNode` `has_default()`/`materialize()` for free.

- **`ObjectNode:materialize()` returns `nil` (not `{}`) when no child has a default.** This avoids writing empty tables to the defaults layer. A non-empty object where all fields have no defaults also returns nil (same rationale).

- **`EnumNode` error-path allocation is not worth pre-computing.** The formatted-values string is only built on validation failure, which is an exceptional path. Premature optimization; leave it as-is.

- **Alias keys in `validate_value()` are passed through without validation.** Alias resolution and value dispatch belong to the proxy/store, not the schema. `validate_value` only rejects truly unknown keys (not aliases, not DISCOVER-resolved keys).

- **Virtual stubs on `Node` base class** (`get_child_schema`, `get_inner_schema`, `resolve_alias`, `get_item_schema`, `is_list`, `is_object`, `has_discover`, `all_known_fields`). Lua has no interfaces; the base class defines stubs returning safe defaults (nil/false), subclasses override. This eliminates duck-type checks at call sites (`if node.resolve_alias then`) and makes the node contract explicit. `OptionalNode` delegates `is_list()` and `is_object()` to its inner schema so optional wrappers remain transparent to consumers.

- **`bufnr` is asserted non-nil for FRONTMATTER operations.** `bufnr or 0` was removed — it silently accepted nil callsites and accumulated ops under a fake key 0, creating subtle cross-buffer bleed bugs. All FRONTMATTER callers must now pass an explicit bufnr.

- **Schema navigation extracted to `flemma.config.schema.navigation`.** `unwrap_optional` and `navigate_schema` were duplicated between store and proxy with intentional leaf-unwrapping differences. Shared module with `opts.unwrap_leaf` parameter: store uses `{ unwrap_leaf = true }` for `is_list()` detection; proxy uses default (false) so `OptionalNode.validate_value` accepts nil writes.

- **`navigate_schema` preserves OptionalNode on leaf by default.** The proxy needs the leaf's OptionalNode wrapper intact so `validate_value(nil)` works for optional fields. The store needs the unwrapped node for `is_list()` detection. Verified in Neovim/LuaJIT that `__newindex` IS called for nil assignments to proxy tables (reviewer concern was wrong).

- **Layer constants (`LAYER_NAMES`, `GLOBAL_LAYER_NUMS`, `global_ops` init) use `M.LAYERS.*`** rather than hardcoded integers. Avoids magic numbers and makes the layer definitions the single source of truth.

- **Unified `proxy.lens()` replaces separate `lens()` and `composed_lens()`.** A single-path lens is just a composed lens with one path. The unified implementation normalizes string paths to `{ path }`, resolves aliases per-path, and returns narrowed lenses for object-typed keys (supporting nested navigation). This eliminates the behavioral split between single-path (full read-proxy via `make_proxy`) and multi-path (custom flat-lookup metatable).

- **Public API at `flemma.config.facade` during overhaul.** Legacy `lua/flemma/config.lua` shadows `lua/flemma/config/init.lua` in Lua's module resolution (`?.lua` matches before `?/init.lua`). The public API lives at `flemma.config.facade` until the legacy file is deleted during refactoring, then becomes `flemma.config` (init.lua).

- **`UnionNode` delegates `has_default()`/`materialize()` to branches.** Many config fields are union types with defaults (highlight values, `text_object`, `notifications.border`, `max_tokens`, `thinking`). `has_default()` returns true if any branch has a default; `materialize()` returns the default from the first branch that has one. This enables schema materialization for union-typed fields without adding a separate default mechanism.

- **`MapNode` supports optional default parameter.** `tools.presets` and top-level `presets` both default to `{}`. Without map defaults, these fields resolve to nil (breaking consumers that iterate with `pairs()`). The default parameter parallels ListNode's existing default support. Backward-compatible: omitting the parameter preserves the original nil-materialization behavior.

- **`model` has no schema default (nil).** The design spec's example shows `model = s.string("claude-sonnet-4-20250514")`, but the current config has `model = nil` (provider supplies the default). Hardcoding a model in the global schema is wrong since model defaults are provider-specific. Using `s.optional(s.string())` matches current behavior — model gets set during provider initialization.

- **DISCOVER callbacks use pcall for forward-compatibility.** The callbacks reference `flemma.provider.registry` and `flemma.tools`, which don't yet expose `metadata.config_schema`. The pcall + nil-checks make the callbacks safe to invoke (they return nil for all keys) until the registries are updated during Session B wiring.

- **`materialize_resolved()` always returns `{}` for object nodes, not `nil`.** Unlike `ObjectNode:materialize()` (which returns nil for objects with no defaulted children to avoid empty ops in the defaults layer), the facade's materialize produces plain tables for all objects. Consumers expect intermediate objects to exist (e.g., `config.parameters.thinking` without nil-checking `config.parameters`). Matches `vim.tbl_deep_extend` behavior.

- **New config system runs alongside old during transition.** `state.get_config()` still returns the old `vim.tbl_deep_extend`-merged table. The new system initializes in parallel: validates known keys, defers DISCOVER-backed keys, replays after module registration. Full `state.get_config()` replacement is blocked by: (a) DISCOVER callbacks can't resolve (tools/providers lack `metadata.config_schema`), (b) existing consumers use `pairs()`, `vim.deepcopy()`, and direct mutation on the returned table — patterns incompatible with a read proxy. The shim is deferred to when tool/provider config schemas are added.

## Workflow Notes

- **Run `make qa` bare — never pipe it.** It is silent on success and self-explanatory on failure. Piping through `grep`/`tail`/`head` defeats its design and can hide output.

- **Don't swallow bugs with workarounds — assert the real constraint.** When a condition guards against misuse, check the misuse first, then assert. Example: `if layer ~= nil and key == CLEAR` silently returns nil for CLEAR on a read proxy — the bug is that someone called clear on a read proxy, and they should hear about it. The correct pattern is `if key == CLEAR then assert(layer ~= nil, "...") end`. Working around the symptom (nil return, non-string key guard) instead of asserting the root cause creates subtle bugs that pass tests for the wrong reasons.

## Considerations for Next

**Session B partially complete.** `defer_discover`, `apply_deferred()`, `materialize()` implemented and tested. New config system initializes at boot alongside old system. 385 tests across 10 suites.

### What was accomplished in Session B

1. **`defer_discover` in `facade.apply()`** — Two-pass mechanism: pass 1 defers writes to unknown keys on DISCOVER-backed objects; `apply_deferred()` replays them after module registration. 8 integration tests cover: single/multi deferral, no-deferral passthrough, non-DISCOVER errors fatal in pass 1, pass 2 failures for genuinely unknown keys, known keys not deferred, alias resolution not deferred.

2. **`materialize()` on facade** — Walks schema tree (static + DISCOVER-cached fields), resolves every path from the store, returns a deep-copied plain table. 7 integration tests cover: defaults, setup/runtime/frontmatter layers, buffer isolation, mutation safety, DISCOVER-cached fields, list resolution.

3. **`has_discover()` + `all_known_fields()` on Node/ObjectNode** — Schema introspection methods enabling the facade's defer check and materializer.

4. **Setup wiring** — `flemma.setup()` now initializes the new config system (schema + defaults + user opts with defer_discover) alongside the old `vim.tbl_deep_extend` merge. Deferred writes replayed after all module registrations.

### What remains for the shim (deferred to a future session)

The `state.get_config()` → `config.get()` shim is blocked by two things:

1. **DISCOVER callbacks can't resolve.** Built-in tool configs (`bash`, `grep`, `find`, `ls`) are behind `tools[DISCOVER]` in the new schema but are static fields in the old `config.lua`. Until tools expose `metadata.config_schema`, `materialize()` produces a table missing these fields. **Fix:** Add `metadata.config_schema` to each built-in tool definition.

2. **Consumer patterns incompatible with proxy.** Production code uses `pairs()`, `vim.deepcopy()`, `vim.tbl_deep_extend()`, and direct mutation on `state.get_config()` return values (4 mutation sites, 3 deepcopy sites, multiple iteration sites). `materialize()` solves this for reads, but `state.set_config()` callers that mutate-and-writeback need rewiring. **Fix:** Rewire mutation sites to use `config.writer()`.

### Suggested next session: Tool/Provider config schemas

Goal: Add `metadata.config_schema` to built-in tools and providers so DISCOVER resolves, then replace `state.get_config()` with `config.materialize()`.

**Tasks:**
1. Add `metadata.config_schema` to each built-in tool (bash, grep, find, ls) using schema DSL definitions matching current config types
2. Add `metadata.config_schema` to each built-in provider (anthropic, openai, vertex) — these already have inline schemas in `definition.lua`, move them to the provider modules
3. Update DISCOVER callbacks to use the real `metadata.config_schema` (remove pcall wrapper)
4. Replace `vim.tbl_deep_extend` merge in setup with `config.materialize()` feeding `state.set_config()`
5. Rewire `config_manager.apply_config()` and `autopilot.set_enabled()` to use `config.writer(nil, LAYERS.RUNTIME)` instead of mutating the returned table

### Open items

- Rename `flemma.config.facade` → `flemma.config` (init.lua) when legacy `config.lua` is deleted
- `state.get_config()` shim deferred (see above)
- **Upgrade `apply_deferred` failure severity.** Currently `init.lua` logs pass 2 failures at `debug` level because DISCOVER can't resolve yet. The spec says pass 2 failures are fatal. When tools/providers expose `metadata.config_schema` (task 3 above), change `log.debug` to `error()` or `vim.notify(..., ERROR)` so genuinely unknown config keys are surfaced to the user.

## Future Work (post-TDD, pre-refactor)

- **DISCOVER defaults materialize at registration time.** The lazy DISCOVER path can't materialize defaults for schemas that haven't been discovered yet. When a module registers (tools via `register_tools()`, providers via `register_providers()`), the registration code has the schema in hand (`M.metadata.config_schema`) and should materialize its defaults into L10 at that point. This means `config.dump_resolved()` shows all registered module defaults without requiring prior access, and DISCOVER still handles validation for unknown keys. The boot sequence already has the right slot: pass 1 writes setup opts → modules register (materialize defaults here) → pass 2 replays deferred writes. Implement when the real boot sequence is wired up during the refactoring phase. The current `discover_spec.lua` test asserts `is_nil` for unregistered discovered defaults — update it when this lands. **Spec also needs updating.**

- **`config.dump_resolved(bufnr)` for `:Flemma status verbose`.** The design spec (lines 541-572) defines a verbose status view that shows per-layer ops and a fully resolved config tree with source annotations. `dump_resolved` walks the schema, resolves every path, and returns a materialized tree with `{ value, source }` at each leaf. Needed before the `:Flemma status` refactoring. `config.inspect(bufnr, path)` handles single-path queries; `dump_resolved` is the whole-tree variant.

- **Sandbox as registry-style module.** bwrap is currently special-cased with top-level config (`sandbox.enabled`, `sandbox.backend`, plus bwrap-specific fields). Should be reworked to follow the tool/provider pattern: `BUILTIN_SANDBOXES` list, `loader.load()` for extensibility, `M.metadata.config_schema` on each backend, config at `sandbox.<backend_name>` with DISCOVER resolution. This eliminates bwrap-specific types from the global schema and makes custom sandbox backends pluggable. **Spec needs a new section** for this — add it when the refactoring phase begins so the sandbox migration is designed alongside the other module rewiring.

- **Move provider parameter schemas to provider modules.** AnthropicParametersSchema, OpenAIParametersSchema, VertexParametersSchema are currently defined inline in `config/schema/definition.lua`. The spec says provider modules own their `metadata.config_schema`. Move each schema to its provider module and have the definition file import them. Do this when `metadata.config_schema` is added to providers during the refactoring phase.

- **`sandbox.backends` passthrough → DISCOVER.** Currently uses `:passthrough()` on the backends object. The spec mentions future sandbox extensibility as a registry-style module. Replace passthrough with DISCOVER resolution when the sandbox redesign lands.

- **`resolve_thinking()` reads flat fields from composed lens.** `base.resolve_thinking()` reads `params.thinking_budget` and `params.reasoning` as flat fields. In the new schema, these live under provider-specific sub-objects (`parameters.anthropic.thinking_budget`, `parameters.openai.reasoning`). The composed lens wiring in Session B must ensure these paths resolve correctly via path-first priority — the provider-specific path is checked through all layers before the general `parameters` fallback.
