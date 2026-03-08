# Repository Guidelines

Flemma.nvim is a Neovim plugin for LLM-powered chat in `.chat` buffers. Keep each contribution focused, reversible, and well-documented so the next agent can continue seamlessly.

## Critical Rules

These are counter-default behaviors — violating them breaks the build or introduces bugs:

- **All JSON through `require("flemma.utilities.json")`** — never bare `vim.json.*` or `vim.fn.json_*` (JSON `null` becomes truthy `vim.NIL` instead of `nil`)
- **All structural buffer inspection through the AST** — never regex/substring matching on buffer lines
- **All `require()` calls at file top** — `make lint-inline-requires` enforces this
- **Full EmmyLua type annotations on all production code** — `make check` enforces this
- **Never `---@diagnostic disable` as an easy fix** — use `---@cast`, `--[[@as type]]`, or restructure; suppressions only for genuine LuaLS limitations

## Architecture Principles

- **Flemma is stateless; the buffer is the state.** All conversation data, tool calls, and results must be fully represented in the buffer text. Never rely on in-memory state that would be lost when Neovim restarts or when a `.chat` file is shared. If you need to persist information (e.g., synthetic IDs for providers that don't supply them), embed it in the buffer format itself so it can be parsed back later. In-memory structures (`state.lua`) are ephemeral caches rebuilt from the buffer on demand — they are never the source of truth.
- Name modules according to their file path (`lua/flemma/provider/providers/openai.lua` → `flemma.provider.providers.openai`). Public APIs belong in the module that owns the domain — tool registration lives in `flemma.tools`, provider registration in `flemma.provider.registry`, session access in `flemma.session`, etc. Don't pollute `init.lua` with single-use accessors; users require the specific module directly.
- **All structural operations go through the AST.** The parsed AST (cached per buffer via `state.ast_cache`) is the only way to inspect conversation structure — roles, tool use/result blocks, thinking blocks, positions. Never call `nvim_buf_get_lines` and scan with regex or substring matching to find structural elements. If the AST lacks information you need (e.g., a position field), extend the AST rather than bypassing it. Direct buffer manipulation is only appropriate for content injection (tool results, streaming text) and UI concerns (spinners, extmarks).
- Make incremental changes that isolate behaviour shifts so refactors remain reviewable.
- **EmmyLua type annotations are mandatory.** Every production file must have full LuaLS type coverage — `---@class`, `---@param`, `---@return`, `---@field`, `---@type` on all public and private functions, fields, and return values. New code without type annotations will not pass `make check`. This is not optional; the type system is a core part of the project's quality infrastructure.

## Project Structure & Module Organization

Explore `lua/flemma/` to understand the codebase — module files are named descriptively and each has a `---@class` annotation explaining its role. Key structural landmarks:

- `init.lua` — setup entry point; `config.lua` — defaults and type definitions (`flemma.Config.Opts`, `flemma.Config`)
- `parser.lua` / `ast.lua` — AST-based buffer parsing (heart of the stateless design)
- `provider/base.lua` — provider contract (metatable inheritance); `provider/providers/{anthropic,openai,vertex}.lua` — implementations
- `tools/` — tool registry (`get_all()` filters by `enabled`), executor, injector, approval, and built-in definitions in `tools/definitions/`
- `utilities/` — stateless shared infrastructure: `json.lua`, `roles.lua`, `modeline.lua`, `truncate.lua`, `display.lua`, `folding.lua`, `buffer.lua`, `bash/`
- `core.lua` — main orchestration; `state.lua` — ephemeral per-buffer state; `config.lua` — `vim.tbl_deep_extend` merge, `state.get_config()` for runtime access
- Production file names never contain underscores; test files use `_spec.lua` suffix.
- Tests live in `tests/flemma/*_spec.lua` with fixtures in `tests/fixtures/`.

## Coding Conventions

### Module pattern

Every module uses `local M = {}` / `return M`. Every module has a `---@class flemma.ModuleName` annotation at the top.

### Require placement

All `require()` calls go at the top of the file, before any function definition. The only exceptions are:

- **Dynamic requires** — module path constructed at runtime from a variable (e.g., `require(provider_module)` in registry code)
- **Vim string-context requires** — inside `foldexpr`, `foldtext`, or keymap strings that Vim evaluates in a separate Lua context

`make lint-inline-requires` enforces this convention. If you need to call a core function from a module that core requires (circular dependency), use `flemma.core.bridge` — see its module documentation.

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

- `vim.notify()` for user-facing errors and warnings
- `log` module for debug/trace logging
- Return tuples `value, err` for operational results (e.g., `config_manager.prepare_config()`)
- Never `error()` for recoverable situations

## Buffer Format Reference

`.chat` files use role markers, structured headers, and fenced blocks:

- **Role markers**: `@System:`, `@You:`, `@Assistant:` at the start of a line; content extends until the next marker
- **Tool Use** (`@Assistant` messages): ``**Tool Use:** `tool_name` (`tool_id`)`` followed by a fenced JSON code block with the tool input
- **Tool Result** (`@You` messages): `` **Tool Result:** `tool_id` `` with optional ` (error)` suffix, followed by a fenced code block with the result
- **Thinking blocks** (`@Assistant` messages): `<thinking>` / `</thinking>` tags, optionally with `provider:signature="base64"` attribute or `redacted` flag
- **Tool status blocks**: `` `flemma:tool status=<status>` `` fence tag on tool_result placeholders (`pending`, `approved`, `denied`, `rejected`)
- **Expressions**: `{{ lua_expression }}` in `@System`/`@You` messages (sandboxed environment with `math`, `string`, `table`, `utf8`, select `vim.fn`/`vim.fs` functions, and essential globals)
- **File references**: `@./path/to/file` or `@./file;type=mime/type` in `@You` messages

All tool IDs and metadata are embedded in buffer text so `.chat` files are portable and re-parseable.

## Build, Test, and Development Commands

- **`make qa`** — run all quality gates (luacheck, types, imports, test). Silent on success; on failure, re-runs only the failed gate(s) with visible output. This is the single command to run before committing.
- **`make changeset`** — interactive changeset creation (for human use; agents write changeset files directly).
- **`make develop`** — launch Flemma from the working directory for manual testing.
- `flemma-fmt` reformats the entire codebase.

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
- **After committing a user-facing change, always write a changeset file** (see above). Include it in the same commit or as an immediate follow-up commit.
- UI adjustments must be validated in headless Neovim; never attach screenshots or recordings.
- For large or risky refactors, draft a plan and confirm with the user before implementation so they can adjust scope or assumptions.
- **Never commit plan or design documents** (`docs/plans/`). Plans are working artifacts for the current session — they live on disk but stay out of version control.

## Keeping This File Current

**This file is the single source of truth for project knowledge.** Do not use auto-memory or other memory files — write all new learnings, pitfalls, and patterns here.

When you resolve a non-obvious issue — something that required real investigation, a surprising root cause, or a workaround for a subtle gotcha — add it to the **Pitfalls & Lessons Learned** section below. The goal is to save the next agent from re-discovering the same thing. Keep entries concise: one line for the symptom, one for the fix/insight.

## Pitfalls & Lessons Learned

- **Stale `vim-pack-dir` copy shadows working-directory changes.** When running headless Neovim, always use `set rtp^=...` (prepend) not `set rtp+=...` (append) — a packaged copy in `vim-pack-dir` takes priority otherwise. Verify with `debug.getinfo(require('flemma.ui').some_fn, 'S').source`.

- **Provider `new()` metatable ordering.** `base.new()` sets `__index = base`, so calling `provider:reset()` before the provider-specific `setmetatable` call will invoke `base.reset()` instead of the provider's `M.reset()`. Always set the provider metatable BEFORE calling `reset()`.

- **LuaJIT `tostring` for integer-valued floats.** `tostring(5.0)` returns `"5"` not `"5.0"` in LuaJIT. Account for this in assertions and string formatting involving numeric results.

- **Registry iteration is non-deterministic.** The tools registry is a table keyed by name; `pairs()` does not guarantee order. When building tool arrays for API requests, sort by name for deterministic prompt caching. In tests, use `find_*_tool()` helpers rather than index-based lookups.

- **Tool header backtick format is critical.** The parser relies on exact backtick wrapping in ``**Tool Use:** `name` (`id`)`` and `` **Tool Result:** `id` `` headers. Missing or misplaced backticks will cause parsing failures.

## Session Closure Checklist

- Run `flemma-fmt` to reformat the entire codebase.
- Run `make qa` and confirm it passes.
- Note outstanding follow-ups, failing tests, or context the next agent will need to resume work.
