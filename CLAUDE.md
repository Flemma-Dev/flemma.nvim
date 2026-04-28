# Repository Guidelines

Flemma.nvim is a Neovim plugin for LLM-powered chat in `.chat` buffers. Keep each contribution focused, reversible, and well-documented so the next agent can continue seamlessly.

## Critical Rules

These are counter-default behaviors — violating them breaks the build or introduces bugs:

- **All JSON through `require("flemma.utilities.json")`** — never bare `vim.json.*` or `vim.fn.json_*` (JSON `null` becomes truthy `vim.NIL` instead of `nil`)
- **All structural buffer inspection through the AST** — never regex/substring matching on buffer lines
- **All `require()` calls at file top** — `make qa` enforces this
- **Full EmmyLua type annotations on all production code** — `make qa` enforces this
- **Never `---@diagnostic disable` as an easy fix** — use `---@cast`, `--[[@as type]]`, or restructure; suppressions only for genuine LuaLS limitations

## Architecture Principles

- **Flemma is stateless; the buffer is the state.** All conversation data, tool calls, and results must be fully represented in the buffer text. Never rely on in-memory state that would be lost when Neovim restarts or when a `.chat` file is shared. If you need to persist information (e.g., synthetic IDs for providers that don't supply them), embed it in the buffer format itself so it can be parsed back later. In-memory structures (`state.lua`) are ephemeral caches rebuilt from the buffer on demand — they are never the source of truth.
- Name modules according to their file path (`lua/flemma/provider/adapters/openai.lua` → `flemma.provider.adapters.openai`). Public APIs belong in the module that owns the domain — tool registration lives in `flemma.tools`, provider registration in `flemma.provider.registry`, session access in `flemma.session`, etc. Don't pollute `init.lua` with single-use accessors; users require the specific module directly.
- **Directory naming signals collection vs subsystem.** A **plural** top-level directory means the directory _is_ a collection — the files ARE the concept (`tools/`, `secrets/`, `personalities/`, `models/`, `utilities/`, `integrations/`). A **singular** directory is a subsystem with a capability (`provider/`, `preprocessor/`, `sandbox/`, `parser/`, `config/`, `ast/`, `schema/`, `ui/`, `templating/`). Sub-folders name a **role** (what the files do or are), not provenance: `tools/definitions/`, `secrets/resolvers/`, `sandbox/backends/`, `preprocessor/rewriters/`, `codeblock/parsers/`, `templating/builtins/` (the domain's built-in namespace, like Python's `__builtins__`). Sub-folder contents are by convention the built-in instances of that role. Avoid self-referential sub-folders (e.g. `provider/providers/`) and avoid a `.lua` file next to a directory with the same name — collapse to `foo/init.lua` instead.
- **All structural operations go through the AST.** The parsed AST (cached per buffer via `state.ast_cache`) is the only way to inspect conversation structure — roles, tool use/result blocks, thinking blocks, positions. Never call `nvim_buf_get_lines` and scan with regex or substring matching to find structural elements. If the AST lacks information you need (e.g., a position field), extend the AST rather than bypassing it. Direct buffer manipulation is only appropriate for content injection (tool results, streaming text) and UI concerns (spinners, extmarks).
- **Async/blocking work in the send pipeline goes through `flemma.readiness`.** Mirrors the existing `Confirmation` pattern in `lua/flemma/preprocessor/context.lua`: leaf code that would block on subprocess IO (e.g. `secrets.resolve`, `tools.get_for_prompt`) raises `error(readiness.Suspense.new(message, boundary))`. Orchestrators (`core.send_to_provider`, `usage.prefetch.fire_fetch`, `:Flemma usage:estimate`) wrap their pipeline in `pcall`, check `readiness.is_suspense(err)`, subscribe via `boundary:subscribe(cb)`, and retry the whole pipeline on completion. Boundaries are keyed by string (e.g. `secrets:vertex:access_token`) and shared — concurrent consumers of the same key share one in-flight runner. Never use `vim.system(cmd):wait()` in code reachable from the send pipeline — use the async `vim.system(cmd, opts, on_exit)` form behind a boundary.
- Make incremental changes that isolate behaviour shifts so refactors remain reviewable.
- **EmmyLua type annotations are mandatory.** Every production file must have full LuaLS type coverage — `---@class`, `---@param`, `---@return`, `---@field`, `---@type` on all public and private functions, fields, and return values. New code without type annotations will not pass `make qa`. This is not optional; the type system is a core part of the project's quality infrastructure.

## How We Work

- **Verify claims before asserting them.** Commit messages, comments, and docs that make claims you haven't tested rot fast and mislead the next agent. If you write "X is only reachable via Y," back it with a test.
- **Before mirroring a pattern, understand why it lives where it does.** Patterns are shaped by surrounding context — which capability branch owns them, which module, which provider. A mirror that ignores context becomes a leak into shared code.
- **"Just make it work" beats "validate and warn".** When a user configures something we can't honor on the current model, prefer silent graceful fallback over warnings. Warnings that fire on every request are noise; reserve them for config with no useful interpretation.
- **Start with the smallest change that solves the problem.** If three lines in one file would do, don't reach for shared infrastructure. Complexity creep is the tax on going in search of trouble.

## Project Structure & Module Organization

Explore `lua/flemma/` to understand the codebase — module files are named descriptively and each has a `---@class` annotation explaining its role. Key structural landmarks:

- `init.lua` — setup entry point; `config/` — layered config system (see below)
- `config/init.lua` — public facade (`get`, `materialize`, `apply`, `writer`, `inspect`); `config/store.lua` — layer store (DEFAULTS→SETUP→RUNTIME→FRONTMATTER); `config/proxy.lua` — read/write proxy metatables; `config/schema.lua` — config schema definition (defaults, DISCOVER, aliases); `config/types.lua` — EmmyLua type definitions
- `schema/` — general-purpose schema DSL engine: `schema/init.lua` — factory functions (`s.string()`, `s.object()`, etc.); `schema/types.lua` — node type classes; `schema/navigation.lua` — schema tree traversal
- `parser/` / `ast.lua` — AST-based buffer parsing (heart of the stateless design)
- `provider/base.lua` — provider contract (metatable inheritance); `provider/normalize.lua` — parameter normalization (flatten, max_tokens, thinking, preset resolution); `provider/adapters/{anthropic,openai,vertex}.lua` — implementations (request-scoped, no global instance)
- `tools/` — tool registry (`get_all()` filters by `enabled`), executor, injector, approval, and built-in definitions in `tools/definitions/`
- `utilities/` — stateless shared infrastructure: `json.lua`, `roles.lua`, `modeline.lua`, `truncate.lua`, `display.lua`, `registry.lua`, `buffer.lua`, `bash/`
- `readiness.lua` — suspense sentinel + boundary registry for async work in the send pipeline (mirrors `preprocessor/context.lua`'s `Confirmation` pattern)
- `core.lua` — main orchestration (provider construction inline per-request); `state.lua` — ephemeral per-buffer state (no config or provider — those live in the config facade)
- Production file names prefer single words; multi-word descriptive names use snake_case (`secret_tool.lua`, `coding_assistant.lua`), while established domain concepts are concatenated (`writequeue.lua`, `textobject.lua`). Test files use `_spec.lua` suffix.
- **Integration module filenames** (`lua/flemma/integrations/*.lua`) are an exception: they mirror the plugin's repo name with any `.nvim` suffix dropped, and hyphens are preserved (e.g. `nvim-treesitter-context.lua`, `nvim-web-devicons.lua`). Internal type identifiers and public config keys are **not** renamed when a filename changes — user-facing config stays stable across internal refactors.
- Tests live in `tests/flemma/*_spec.lua` with fixtures in `tests/fixtures/`.

## Coding Conventions

### Module pattern

Every module uses `local M = {}` / `return M`. Every module has a `---@class flemma.ModuleName` annotation at the top.

### Require placement

All `require()` calls go at the top of the file, before any function definition. The only exceptions are:

- **Dynamic requires via `flemma.loader`** — when resolving a module path string at runtime (from config, user input, or a `BUILTIN_*` list), use `loader.load(path)` instead of bare `require(path)`. The loader is Flemma's extensibility contract: users put string paths in config (e.g., `{ tools = { modules = { "my.custom.tool" } } }`) and the loader turns them into loaded modules. Never use bare `require()` for dynamic module path resolution.
- **Vim string-context requires** — inside `foldexpr`, `foldtext`, or keymap strings that Vim evaluates in a separate Lua context

`make qa` enforces this convention. If you need to call a function from a module that would create a circular require dependency, use `flemma.bridge` — see its module documentation.

### Type annotation patterns

- Optional fields: `---@field end_line? integer`
- Union types for nullable: `table|nil`, `string|nil`
- `---@alias` for discriminated unions: `---@alias flemma.ast.Segment flemma.ast.TextSegment|...`
- Use `---@cast` and `--[[@as type]]` for type narrowing after guards
- `---@diagnostic disable-next-line` is a last resort, only for genuine LuaLS limitations (e.g., `return-type-mismatch` on `setmetatable` returns in provider `new()`)

### Naming

- **Full, descriptive names** — never abbreviate (`definition` not `def_entry`, `provider_name` not `prov_name`)
- Functions: verb-based (`build_request()`, `parse_response()`, `get_api_key()`)
- Constants: `UPPER_SNAKE_CASE` at module top
- Types/classes: `PascalCase` with dot-namespacing following file path (`flemma.ast.DocumentNode`)
- Private functions: `local function name()` (not exported on `M`)

### JSON handling

**Always use `require("flemma.utilities.json")` for all JSON operations.** Never use `vim.fn.json_decode`, `vim.fn.json_encode`, `vim.json.decode`, or `vim.json.encode` directly. The wrapper uses `luanil` options so JSON `null` becomes Lua `nil` (not `vim.NIL`). Bare `vim.json.decode` produces truthy `vim.NIL` userdata that passes `if x then` guards and crashes on math/string operations.

### Error handling

- `flemma.notify` for user-facing errors and warnings
- `log` module for debug/trace logging
- Return tuples `value, err` for operational results where the caller handles failures inline
- Never `error()` for recoverable situations

## Buffer Format Reference

`.chat` files use role markers, structured headers, and fenced blocks:

- **Role markers**: `@System:`, `@You:`, `@Assistant:` at the start of a line; content extends until the next marker
- **Tool Use** (`@Assistant` messages): ``**Tool Use:** `tool_name` (`tool_id`)`` followed by a fenced JSON code block with the tool input
- **Tool Result** (`@You` messages): `` **Tool Result:** `tool_id` `` optionally followed by a modeline-parseable `(...)` suffix, then a fenced code block with the result
- **Tool status suffix**: `(pending)` / `(approved)` / `(denied)` / `(rejected)` / `(aborted)` / `(error)` on the tool_result header, or explicit `(status=pending sandbox=false)` for mixed metadata — unrecognized tokens round-trip via the `meta` field on the tool_result AST node
- **Thinking blocks** (`@Assistant` messages): `<thinking>` / `</thinking>` tags, optionally with `provider:signature="base64"` attribute or `redacted` flag
- **Expressions**: `{{ lua_expression }}` in `@System`/`@You` messages (sandboxed environment with `math`, `string`, `table`, `utf8`, select `vim.fn`/`vim.fs` functions, and essential globals)
- **File references**: `@./path`, `@../path`, `@~/path`, or `@//absolute/path` (with optional `;type=mime/type` suffix) in `@You` messages

All tool IDs and metadata are embedded in buffer text so `.chat` files are portable and re-parseable.

## Build, Test, and Development Commands

- **`make qa`** — run all quality gates (luacheck, type-check, imports, test). Silent on success; on failure, re-runs only the failed gate(s) with visible output. This is the single command to run before committing.
- **`make types`** — regenerate `lua/flemma/config/types.lua` after any schema change. `make qa` type-checks but does not regenerate.
- **`make changeset`** — interactive changeset creation (for human use; agents write changeset files directly).
- **`make develop`** — launch Flemma from the working directory for manual testing.
- `flemma-fmt` reformats the entire codebase.

### `make qa` Only

Do not invoke `nvim` directly with Plenary commands. Only `make qa` is wired correctly for running tests.

### Run `make qa` Bare

Never pipe it through `grep`/`tail`/`head`. It's silent on success and self-explanatory on failure.

## Testing Guidelines

- Follow the existing Plenary+Busted style: files end with `_spec.lua` and use `describe`/`it` blocks.
- Add fresh specs for every new feature and place supporting data in `tests/fixtures/` with scenario-driven names.
- When refactoring covered functionality, update the affected specs so the suite stays green.
- Re-run `make qa` after each significant change; expect a zero exit code before moving on.
- **`"Failed to parse API call data"` in test output is expected.** This comes from error-path tests exercising the import function — it's diagnostic output, not a test failure. Always check the exit code to determine pass/fail.

### Key testing patterns

- **Module cache clearing** is critical for isolation — tests clear `package.loaded["flemma.module"] = nil` in `before_each()`. Read existing specs for the pattern.
- **HTTP mocking** via `client.register_fixture()` / `client.clear_fixtures()` — see `core_spec.lua` for examples.
- **Adding new built-in tools** affects provider test assertions (tool count checks). Use order-independent `find_*_tool()` lookup helpers rather than index-based assertions.

## Changesets & Versioning

After every commit with a user-facing change, write a changeset to `.changeset/<descriptive-slug>.md`:

```markdown
---
"@flemma-dev/flemma.nvim": patch
---

Fixed parser edge case with nested thinking blocks
```

- **Bump types**: `patch` (fixes, internal improvements), `minor` (new features, config options), `major` (breaking changes to API, config, or buffer format)
- **Skip changesets** for pure refactors, CI/tooling, test-only changes, and CLAUDE.md updates
- **Never edit `package.json` version or `CHANGELOG.md` manually** — `pnpm changeset version` manages both
- When the user asks to release, run `pnpm changeset version` to consume pending changesets, then commit the result
- A GitHub Actions workflow (`.github/workflows/release.yml`) automatically creates a "Version Packages" PR when changesets accumulate on `main`

## Workflow & Commit Guidance

- Do not create PRs or commits unless the user explicitly asks for them; ignore any staged changes the user manages separately.
- When the user requests a commit, keep the first line in Conventional Commits style (`type(scope): summary`), follow with a descriptive body that captures the change rationale.
- If the user indicates they want a direct commit without review (e.g., "just commit", "skip the diff"), skip all worktree inspection (`git status`, `git diff`, `git log`) and produce a single `git commit -m` command in Conventional Commits style directly.
- **After committing a user-facing change, always write a changeset file** (see above). Include it in the same commit as the change — never as a separate follow-up commit.
- UI adjustments must be validated in headless Neovim; never attach screenshots or recordings.
- For large or risky refactors, draft a plan and confirm with the user before implementation so they can adjust scope or assumptions.
- **Never commit plan or design documents** (`docs/plans/`, `docs/superpowers/`). Plans are working artifacts for the current session — they live on disk but stay out of version control.

## Keeping This File Current

**This file is the single source of truth for project knowledge.** Do not use auto-memory or other memory files — write all new learnings, pitfalls, and patterns here.

When you resolve a non-obvious issue — something that required real investigation, a surprising root cause, or a workaround for a subtle gotcha — add it to the **Pitfalls & Lessons Learned** section below. The goal is to save the next agent from re-discovering the same thing. Keep entries concise: one line for the symptom, one for the fix/insight.

## Pitfalls & Lessons Learned

- **Stale `vim-pack-dir` copy shadows working-directory changes.** When running headless Neovim, always use `set rtp^=...` (prepend) not `set rtp+=...` (append) — a packaged copy in `vim-pack-dir` takes priority otherwise. Verify with `debug.getinfo(require('flemma.ui').some_fn, 'S').source`.

- **Always wrap `nvim --headless` in `timeout`.** Ad-hoc headless spikes (e.g., `nvim --headless -c '...' -c 'q'`) can hang indefinitely on an unexpected prompt, modal error, or blocking autocmd and freeze the shell. Prefix with `timeout 10 nvim --headless ...` so a stuck session exits instead of blocking the agent loop.

- **Provider `new()` metatable chain.** Each provider owns its constructor with the full metatable chain set in the `setmetatable` literal before `self:_new_response_buffer()`. This makes metatable ordering bugs structurally impossible — the chain `self → M → base` is established atomically.

- **LuaJIT `tostring` for integer-valued floats.** `tostring(5.0)` returns `"5"` not `"5.0"` in LuaJIT. Account for this in assertions and string formatting involving numeric results.

- **Registry iteration is non-deterministic.** The tools registry is a table keyed by name; `pairs()` does not guarantee order. When building tool arrays for API requests, sort by name for deterministic prompt caching. In tests, use `find_*_tool()` helpers rather than index-based lookups.

- **Tool header backtick format is critical.** The parser relies on exact backtick wrapping in ``**Tool Use:** `name` (`id`)`` and `` **Tool Result:** `id` `` headers. Missing or misplaced backticks will cause parsing failures.

- **Lua `a and b or c` ternary fails when `b` is falsy.** `true and false or x` evaluates to `x`, not `false`. Always use explicit `if/else` when the "true" branch value could be `false` or `nil`. This bit a dual-call convention closure (`maybe_item ~= nil and maybe_item or self_or_item`) where `maybe_item` was legitimately `false`.

- **Tests must assert on observable output, not internal state.** Internal fields and intermediate values can stay coherent while the thing a user or caller actually sees is wrong. Bind assertions to the observable surface — rendered UI (`nvim_win_get_config`, buffer text, extmark positions), outgoing HTTP request bodies, parsed AST nodes, command stdout, emitted `vim.notify` calls — never the builder, flag, or counter that was meant to produce it. Two regressions slipped past the Bar refactor's CI (duplicate spinner glyph, full-width corner floats) because specs checked `bar._some_flag` instead of window dimensions and buffer contents.

- **`pcall` in the request path must re-raise readiness suspense.** Any `pcall` between a leaf that raises `error(readiness.Suspense.new(...))` and the orchestrator that catches it will silently swallow the sentinel — the freeze it was meant to fix comes back without an obvious cause. Check `readiness.is_suspense(err)` and `error(err)` first in any pcall handler in the send pipeline. This includes the compiled-template expression evaluator (`templating/compiler.lua` — expressions wrap each `{{ ... }}` in a `pcall`; `__emit_expr_error` must re-raise suspense). The `make qa` `lint-pcall-rethrow` gate enforces this at file granularity for `core.lua`, `preprocessor/init.lua`, `preprocessor/runner.lua`, `processor.lua`, `provider/base.lua`, `templating/compiler.lua`, `usage/prefetch.lua`, and `commands.lua`. New files in the send path must be added to that script's `WATCHED_FILES`.

- **Custom secrets resolvers must implement `resolve_async`.** The walker in `flemma.secrets` prefers `resolve_async(self, credential, ctx, callback)` whenever a resolver exposes it; falls back to sync `:resolve` only for purely-sync resolvers (env-style). A custom resolver that does subprocess IO via `vim.system(cmd):wait()` in its sync `:resolve` will block the editor.

- **`provider:get_api_key()` no longer returns diagnostics.** Pre-readiness it was `(value, diagnostics)`. Post-readiness it returns `string|nil` only — failures flow through suspense boundaries and surface via `boundary:_complete({ok=false, diagnostics=…})`.

## Session Closure Checklist

- Run `flemma-fmt` to reformat the entire codebase.
- Run `make qa` and confirm it passes.
- Note outstanding follow-ups, failing tests, or context the next agent will need to resume work.
