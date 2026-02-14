# Repository Guidelines

Flemma.nvim is a Neovim plugin for LLM-powered chat in `.chat` buffers. Keep each contribution focused, reversible, and well-documented so the next agent can continue seamlessly.

## Architecture Principles

- **Flemma is stateless; the buffer is the state.** All conversation data, tool calls, and results must be fully represented in the buffer text. Never rely on in-memory state that would be lost when Neovim restarts or when a `.chat` file is shared. If you need to persist information (e.g., synthetic IDs for providers that don't supply them), embed it in the buffer format itself so it can be parsed back later. In-memory structures (`state.lua`) are ephemeral caches rebuilt from the buffer on demand — they are never the source of truth.
- Name modules according to their file path (`lua/flemma/provider/providers/openai.lua` → `flemma.provider.providers.openai`). Public APIs belong in the module that owns the domain — tool registration lives in `flemma.tools`, provider registration in `flemma.provider.registry`, session access in `flemma.session`, etc. Don't pollute `init.lua` with single-use accessors; users require the specific module directly.
- **All structural operations go through the AST.** The parsed AST (cached per buffer via `state.ast_cache`) is the only way to inspect conversation structure — roles, tool use/result blocks, thinking blocks, positions. Never call `nvim_buf_get_lines` and scan with regex or substring matching to find structural elements. If the AST lacks information you need (e.g., a position field), extend the AST rather than bypassing it. Direct buffer manipulation is only appropriate for content injection (tool results, streaming text) and UI concerns (spinners, extmarks).
- Favor incremental changes that isolate behaviour shifts so refactors remain reviewable.
- Document non-obvious reasoning inline with concise comments only when the code is not self-explanatory.
- **EmmyLua type annotations are mandatory.** Every production file must have full LuaLS type coverage — `---@class`, `---@param`, `---@return`, `---@field`, `---@type` on all public and private functions, fields, and return values. New code without type annotations will not pass `make check`. This is not optional; the type system is a core part of the project's quality infrastructure. **Never reach for `---@diagnostic disable` as an easy fix** — always diagnose the root cause and use proper type narrowing (`---@cast`, `--[[@as type]]`, restructuring code). Only use diagnostic suppressions when genuinely hitting a LuaLS toolchain limitation (e.g., `setmetatable` return types).

## Project Structure & Module Organization

Explore `lua/flemma/` to understand the codebase — module files are named descriptively and each has a `---@class` annotation explaining its role. Key structural landmarks:

- `init.lua` — setup entry point; `config.lua` — defaults and type definitions (`flemma.Config.Opts`, `flemma.Config`)
- `parser.lua` / `ast.lua` — AST-based buffer parsing (heart of the stateless design)
- `provider/base.lua` — provider contract; `provider/providers/{anthropic,openai,vertex}.lua` — implementations
- `tools/` — tool registry, executor, injector, approval, and built-in definitions in `tools/definitions/`
- `core.lua` — main orchestration; `state.lua` — ephemeral per-buffer state
- Production file names never contain underscores; test files use `_spec.lua` suffix.
- Tests live in `tests/flemma/*_spec.lua` with fixtures in `tests/fixtures/`.

## Coding Conventions

### Module pattern

Every module uses `local M = {}` / `return M`. Every module has a `---@class flemma.ModuleName` annotation at the top.

### Type annotation patterns

- Optional fields: `---@field end_line? integer`
- Union types for nullable: `table|nil`, `string|nil`
- `---@alias` for discriminated unions: `---@alias flemma.ast.Segment flemma.ast.TextSegment|...`
- Prefer `---@cast` and `--[[@as type]]` for type narrowing after guards — these are the correct tools for the job
- `---@diagnostic disable-next-line` is a last resort, only for genuine LuaLS limitations (e.g., `return-type-mismatch` on `setmetatable` returns in provider `new()`)

### Naming

- **Full, descriptive names** — never abbreviate (`definition` not `def_entry`, `provider_name` not `prov_name`)
- Functions: verb-based (`build_request()`, `parse_response()`, `get_api_key()`)
- Constants: `UPPER_SNAKE_CASE` at module top
- Types/classes: `PascalCase` with dot-namespacing following file path (`flemma.ast.DocumentNode`)
- Private functions: `local function name()` (not exported on `M`)

### Error handling

- `vim.notify()` for user-facing errors and warnings
- `log` module for debug/trace logging
- Return tuples `value, err` for operational results (e.g., `config_manager.prepare_config()`)
- Never `error()` for recoverable situations

### Provider inheritance

Providers inherit from `base.lua` via metatable chains — read any provider in `provider/providers/` for the pattern. See the metatable ordering pitfall below.

### Tool definitions

Read any file in `tools/definitions/` for the pattern. `tools/registry.lua` has `get_all()` which filters by `enabled`.

### Config merging

See `init.lua` for the `vim.tbl_deep_extend` merge and `state.get_config()` for runtime access.

## Buffer Format Reference

`.chat` files use role markers, structured headers, and fenced blocks:

- **Role markers**: `@System:`, `@You:`, `@Assistant:` at the start of a line; content extends until the next marker
- **Tool Use** (`@Assistant` messages): ``**Tool Use:** `tool_name` (`tool_id`)`` followed by a fenced JSON code block with the tool input
- **Tool Result** (`@You` messages): `` **Tool Result:** `tool_id` `` with optional ` (error)` suffix, followed by a fenced code block with the result
- **Thinking blocks** (`@Assistant` messages): `<thinking>` / `</thinking>` tags, optionally with `provider:signature="base64"` attribute or `redacted` flag
- **Pending marker**: ` ``flemma:pending ` fence tag on tool_result placeholders awaiting approval/execution
- **Expressions**: `{{ lua_expression }}` in `@System`/`@You` messages (sandboxed environment with `math`, `string`, `table`, `utf8`, select `vim.fn`/`vim.fs` functions, and essential globals)
- **File references**: `@./path/to/file` or `@./file;type=mime/type` in `@You` messages

All tool IDs and metadata are embedded in buffer text so `.chat` files are portable and re-parseable.

## Build, Test, and Development Commands

- **`make test`** — run the full Plenary+Busted test suite. Use `make test >/dev/null 2>&1` mid-session to check exit codes without flooding the transcript; run plain `make test` when debugging failures or before ending a session.
- **`make lint`** — run `luacheck` on `lua/` and `tests/`.
- **`make check`** — run `lua-language-server --check` on production code.
- **`make changeset`** — interactive changeset creation (for human use; agents write changeset files directly).
- **`make develop`** — launch Flemma from the working directory for manual testing.
- All three quality gates (`test`, `lint`, `check`) must pass before committing.
- `flemma-fmt` reformats the entire codebase.

## Testing Guidelines

- Follow the existing Plenary+Busted style: files end with `_spec.lua` and use `describe`/`it` blocks.
- Add fresh specs for every new feature and place supporting data in `tests/fixtures/` with scenario-driven names.
- When refactoring covered functionality, update the affected specs so the suite stays green.
- Re-run `make test` after each significant change; expect a zero exit code before moving on.
- **`"Failed to parse API call data"` in test output is expected.** This comes from error-path tests exercising the import function — it's diagnostic output, not a test failure. Always check the exit code to determine pass/fail.

### Key testing patterns

- **Module cache clearing** is critical for isolation — tests clear `package.loaded["flemma.module"] = nil` in `before_each()`. Read existing specs for the pattern.
- **HTTP mocking** via `client.register_fixture()` / `client.clear_fixtures()` — see `core_spec.lua` for examples.
- **Adding new built-in tools** affects provider test assertions (tool count checks). Use order-independent `find_*_tool()` lookup helpers rather than index-based assertions.

## Changesets & Versioning

Flemma uses [changesets](https://github.com/changesets/changesets) for version management and changelog generation. The project follows **semver** (starting from `0.1.0`). **Changesets are fully agent-managed** — the user should never need to run `pnpm changeset` or `make changeset` themselves.

### Agent responsibilities

1. **After every commit that contains a user-facing change**, write a changeset file to `.changeset/`. This is non-negotiable — every behavioral change must be tracked.
2. **When the user asks to release** (e.g., "bump a patch", "release a minor"), run `pnpm changeset version` to consume all pending changesets, bump `package.json`, and update `CHANGELOG.md`. Then commit the result.

### How to write a changeset file

Changeset files are Markdown with YAML frontmatter. Write them directly — no interactive command needed:

```markdown
---
"@flemma-dev/flemma.nvim": patch
---

Fixed parser edge case with nested thinking blocks
```

- **Filename**: use a short descriptive slug, e.g., `.changeset/fix-nested-thinking.md`. Lowercase, hyphens, no spaces.
- **Bump type** in the YAML frontmatter — one of `patch`, `minor`, or `major`:
  - **patch** — bug fixes, internal improvements, documentation
  - **minor** — new features, new configuration options, new commands
  - **major** — breaking changes to the public API, config structure, or buffer format
- **Summary** — one or two sentences describing the change from a user's perspective. This text ends up in `CHANGELOG.md`.

### When to skip a changeset

Pure refactors with no behavior change, CI/tooling changes, test-only changes, and updates to `CLAUDE.md` do not need changesets.

### Rules

- **Never edit `package.json` version manually** — `pnpm changeset version` manages it.
- **Never edit `CHANGELOG.md` by hand** for new entries — it's generated from changeset summaries.
- A GitHub Actions workflow (`.github/workflows/release.yml`) automatically creates a "Version Packages" PR when changesets accumulate on `main`.

## Workflow & Commit Guidance

- Do not create PRs or commits unless the user explicitly asks for them; ignore any staged changes the user manages separately.
- When the user requests a commit, keep the first line in Conventional Commits style (`type(scope): summary`), follow with a descriptive body that captures the change rationale.
- If the user indicates they want a direct commit without review (e.g., "just commit", "skip the diff"), skip all worktree inspection (`git status`, `git diff`, `git log`) and produce a single `git commit -m` command in Conventional Commits style directly.
- **After committing a user-facing change, always write a changeset file** (see Changesets & Versioning above). Include it in the same commit or as an immediate follow-up commit.
- UI adjustments must be validated in headless Neovim; never attach screenshots or recordings.
- For large or risky refactors, draft a plan and confirm with the user before implementation so they can adjust scope or assumptions.

## Keeping This File Current

**This file is the single source of truth for project knowledge.** Do not use auto-memory or other memory files — write all new learnings, pitfalls, and patterns here.

When you resolve a non-obvious issue — something that required real investigation, a surprising root cause, or a workaround for a subtle gotcha — add it to the **Pitfalls & Lessons Learned** section below. The goal is to save the next agent from re-discovering the same thing. Keep entries concise: one line for the symptom, one for the fix/insight.

## Pitfalls & Lessons Learned

- **Stale `vim-pack-dir` copy shadows working-directory changes.** A packaged copy of Flemma may exist in `vim-pack-dir` early in `rtp`. When running headless Neovim with `--cmd "set rtp+=..."`, that stale copy takes priority. Always prepend with `rtp^=`:

  ```bash
  # WRONG — packaged copy shadows your edits:
  nvim --headless --clean -u NONE --cmd "set rtp+=/data/public/github.com/Flemma-Dev/flemma.nvim" ...

  # CORRECT — your working copy takes priority:
  nvim --headless --clean -u NONE --cmd "set rtp^=/data/public/github.com/Flemma-Dev/flemma.nvim" ...
  ```

  If your changes seem to have no effect, verify with `debug.getinfo(require('flemma.ui').some_fn, 'S').source` — it should point to your working directory, not a `vim-pack-dir` path.

- **Provider `new()` metatable ordering.** `base.new()` sets `__index = base`, so calling `provider:reset()` before the provider-specific `setmetatable` call will invoke `base.reset()` instead of the provider's `M.reset()`. Always set the provider metatable BEFORE calling `reset()`.

- **LuaJIT `tostring` for integer-valued floats.** `tostring(5.0)` returns `"5"` not `"5.0"` in LuaJIT. Account for this in assertions and string formatting involving numeric results.

- **Registry iteration is non-deterministic.** The tools registry is a table keyed by name; `pairs()` does not guarantee order. When building tool arrays for API requests, sort by name for deterministic prompt caching. In tests, use `find_*_tool()` helpers rather than index-based lookups.

- **Tool header backtick format is critical.** The parser relies on exact backtick wrapping in ``**Tool Use:** `name` (`id`)`` and `` **Tool Result:** `id` `` headers. Missing or misplaced backticks will cause parsing failures.

- **Don't abbreviate variable names.** Use full, descriptive names (`definition` not `def_entry`, `provider_name` not `prov_name`). The codebase consistently spells things out; cryptic abbreviations stand out and hurt readability.

## Session Closure Checklist

- Run `flemma-fmt` to reformat the entire codebase.
- Run all three quality gates and confirm they pass: `make test` (no redirection — verify exit code 0), `make lint`, `make check`.
- Note outstanding follow-ups, failing tests, or context the next agent will need to resume work.
