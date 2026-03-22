---
"@flemma-dev/flemma.nvim": minor
---

Replaced the configuration system with a layered, schema-backed copy-on-write store.

The new system introduces a schema DSL for declarative config shape definition, a four-layer store (DEFAULTS, SETUP, RUNTIME, FRONTMATTER) with separate scalar (top-down first-set-wins) and list (bottom-up accumulation) resolution, read/write proxy metatables for ergonomic access, and a DISCOVER callback pattern that lets tool, provider, and sandbox modules register their own config schemas at load time without coupling the schema definition to heavy modules.

All configuration access now goes through a single public facade (`require("flemma.config")`). The legacy flat merge (`vim.tbl_deep_extend` in `config.lua`), the global config cache (`state.get_config` / `state.set_config`), and the per-buffer opt overlay (`buffer/opt.lua`) have all been removed. Frontmatter evaluation writes directly to the FRONTMATTER layer of the store, and `flemma.opt` is now a write proxy into that layer.

Providers are now request-scoped — constructed inline per `send_to_provider()` call with per-buffer parameters, captured in closures, and GC'd after the request completes. The global mutable provider instance, the parameter override diffing machinery, and `config_manager.lua` have been dissolved into `core.lua` (orchestration) and `provider/normalize.lua` (pure parameter normalization functions).

The approval system is unified into a single config resolver that reads the resolved `tools.auto_approve` from the layer store, replacing the previous two-resolver pattern (config + frontmatter at separate priorities). Preset `deny` lists have been removed — an auto-approve policy that denies is a contradiction.

`:Flemma status` now shows right-aligned layer source indicators (D/S/R/F) on provider, model, parameter, and tool lines, and a verbose view with per-layer ops and a schema-walked resolved config tree.

Test coverage includes 9 new config test suites (store, proxy, schema, definition, alias, list ops, DISCOVER, lens, integration) alongside migration of ~30 existing test files to the new facade.
