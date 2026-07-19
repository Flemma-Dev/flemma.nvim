# Repository Guidelines

Flemma.nvim is a Neovim plugin for LLM-powered chat in `.chat` buffers. The buffer is the conversation — portable, re-parseable, and version-controllable. Keep each contribution focused, reversible, and well-documented so the next contributor can continue seamlessly.

To understand the codebase, explore `lua/flemma/` — modules are named descriptively and each carries a `---@class` annotation explaining its role. This file records only what the code cannot tell you: rules to follow, conventions to apply, and learnings that cost real debugging time.

## Iron Rules

Non-negotiable. The canonical statement of every hard rule lives in this block; at most one section below expands its how/why — nothing restates a rule differently.

**Build & test**

- Run `make qa` bare — never piped through `grep`/`tail`/`head`. It is silent on success and self-explanatory on failure.
- Only `make qa` runs tests — never invoke `nvim` directly with Plenary commands.
- A `make qa` failure is your problem, never "pre-existing" — the only acceptable proof otherwise is stashing your changes and confirming the failure on the clean parent commit.
- Every new feature and every bug fix ships with test coverage.
- New tests land in the module's existing spec file — create a new `_spec.lua` only for a genuinely new module or subsystem.
- Always wrap ad-hoc headless `nvim` in `timeout` (`timeout 10 nvim --headless ...`) — it can hang indefinitely on an unexpected prompt.

**Code**

- All JSON through `require("flemma.utilities.json")` — never bare `vim.json.*` or `vim.fn.json_*`.
- Never catalogue `flemma.logging` output — log lines stay inline English literals so they grep straight back to source when debugging. Every _user-visible_ string belongs in `flemma.messages` (model-facing strings — conversation, tool schemas — do too), and the surface is wider than `flemma.notify`: extmark/`virt_text` labels (spinners, tool-status indicators), interactive prompts (`vim.ui.select`/`vim.ui.input`), and float titles/borders/footers all count. Only `notify.*` is lint-enforced (the `messages` gate), so the rest is a manual sweep — grep `virt_text`, `nvim_echo`, `vim.ui.select`/`vim.ui.input`, `title =` when touching UI. NOT user-facing text (stay inline English): buffer-format tokens (role markers, `(rejected)`/`(pending)` status suffixes, `<thinking>` tags — all parse-critical) and highlight-group names.
- `error()` prose stays inline English (developer-facing, like logging) — the exception is a structured diagnostic (`error({ type=…, error=… })`) raised on user-authored `.chat` content (templating expressions, `@file`/`include()` failures): that reaches the user, so its prose belongs in `flemma.messages`. Stdlib/libuv error text such a diagnostic wraps stays a dynamic `{{ detail }}` variable — translate our wrapper, never stdlib's message.
- Join a user-facing string to another only with `\n` (layout) — never punctuation (`. `, `: `, ` `), which is language-specific grammar (a full stop is wrong in scripts that don't end sentences with one). A single message may carry an untranslatable prefix (method name like `config.apply:`, a glyph, HTML markup); two translations glued need one fuller message instead. The quotes/brackets around an interpolated value belong inside the `msgstr` too (Russian «», English ''), never hardcoded around the call.
- Every `flemma.messages` rule is enforced by `make qa`'s `messages` gate (`contrib/scripts/lint-messages.sh`): PO validity (`msgfmt --check`), keys resolve both directions, call-site `{ vars }` match `{{ placeholders }}`, `#. Variables:` comments are present, no pure-formatting entries (a `msgstr` with no translatable words), newline-only joins, and the `local messages` import name. Add ast-grep rule files under `contrib/scripts/ast-grep/rules/`, never a stray scan in the Makefile.
- All structural buffer inspection through the AST — never regex/substring matching on buffer lines.
- Never write a helper without searching for an existing one first — `utilities/` (18 modules), `ast/query.lua`, and the owning subsystem; duplicating an established helper is a review failure.
- All `require()` calls at file top — dynamic module paths go through `flemma.loader`.
- Full EmmyLua type annotations on all production code.
- Never `---@diagnostic disable` as an easy fix — use `---@cast`, `--[[@as type]]`, or restructure; suppressions only for genuine LuaLS limitations.
- Never `vim.system(cmd):wait()` in code reachable from the send pipeline — async form behind a readiness boundary.

**Commit & release**

- No commits or PRs unless the user asks; ignore staged changes the user manages separately.
- Every user-facing change carries a changeset file in the same commit — never as a follow-up.
- `make format` before every commit.
- `make types` after any config schema change.
- Never commit plan or design documents (`docs/plans/`, `docs/superpowers/`).
- Never hand-edit the `package.json` version or `CHANGELOG.md` — `pnpm changeset version` manages both.
- Renames and terminology sweeps grep the whole repo from `.` across `*.lua *.md *.chat *.json *.yml *.yaml` — never just `lua/`.

## Commands

- `make qa` — every quality gate (luacheck, type-check, imports, tests). Silent on success; on failure re-runs only the failed gates with visible output.
- `make types` — regenerate `lua/flemma/config/types.lua` after a schema change (`make qa` type-checks but does not regenerate).
- `make develop` — launch Flemma from the working directory for manual testing.
- `make format` — reformat via `treefmt` (stylua, shfmt, nixfmt, prettier, yamlfmt, taplo, po — the last normalizes `po/*.po` to `msgcat --no-wrap` for greppability); cached.

`make qa` runs the tests against every Neovim version in `$NVIM_VERSIONS`; gate names embed the version (`test-neovim-0.12.2`). A failure in only one version is a version-specific compatibility issue — check `vim.fn` signatures, API changes, and Lua runtime differences.

## Design Principles

- **Flemma is stateless; the buffer is the state.** All conversation data, tool calls, and results live in buffer text — never in memory that dies with Neovim or is lost when a `.chat` file is shared. Anything that must persist (e.g., synthetic IDs) is embedded in the buffer format and parsed back. `state.lua` holds ephemeral caches rebuilt from the buffer — never the source of truth.
- **The outgoing request is a product of _(conversation, environment)_.** The buffer determines what was said; the environment — config layers, tool registry, personality ambient state, template evaluation, model metadata — determines how it's delivered. Same buffer + same environment ⇒ same request. Every new request-pipeline input picks a side: conversation state → buffer; ambient context → environment. Never mix.
- **All structural operations go through the AST** (cached per buffer in `state.ast_cache`). If the AST lacks information you need, extend the AST rather than bypass it. Direct buffer manipulation only for content injection (tool results, streaming text) and UI (spinners, extmarks).
- **Async/blocking work in the send pipeline goes through `flemma.readiness`.** Leaf code raises `error(readiness.Suspense.new(message, boundary))`; orchestrators wrap the pipeline in `pcall`, check `readiness.is_suspense(err)`, subscribe to the boundary, and retry on completion. Boundaries are keyed by string and shared — concurrent consumers of one key share one in-flight runner. Any intermediate `pcall` silently swallows the sentinel: every pcall handler in the send path checks `is_suspense` and re-raises first. The `lint-pcall-rethrow` gate enforces this — new files in the send path must be added to its `WATCHED_FILES`.
- **"Just make it work" beats "validate and warn."** Config we can't honor on the current model gets silent graceful fallback; warnings are reserved for config with no useful interpretation.
- **Start with the smallest change that solves the problem**, in increments that isolate behaviour shifts so refactors stay reviewable.
- **Verify claims before asserting them.** Untested claims in commits, comments, and docs rot fast and mislead the next contributor — back "X is only reachable via Y" with a test.
- **Before mirroring a pattern, understand why it lives where it does.** A mirror that ignores its context becomes a leak into shared code.

## Conventions

- Every module is `local M = {}` / `return M` with a `---@class flemma.ModuleName` annotation at the top.
- Module names follow file paths (`lua/flemma/provider/adapters/openai.lua` → `flemma.provider.adapters.openai`). Public APIs belong to the domain-owning module (`flemma.tools`, `flemma.provider.registry`, …) — don't pollute `init.lua` with single-use accessors.
- `require()` exceptions: module paths arriving as strings (config, user input, `BUILTIN_*` lists) go through `flemma.loader` — Flemma's extensibility contract — and Vim string-context code (`foldexpr`, `foldtext`, keymap strings) requires inside the string. Circular dependencies go through `flemma.bridge`.
- Types: optional fields `---@field end_line? integer`; nullable unions `table|nil`; `---@alias` for discriminated unions; `---@cast` and `--[[@as type]]` for narrowing after guards.
- Naming: full descriptive names, never abbreviated (`provider_name`, not `prov_name`); verb-based functions (`build_request()`); `UPPER_SNAKE_CASE` module constants; PascalCase dot-namespaced types (`flemma.ast.DocumentNode`); private functions stay `local`.
- Files: single words preferred; snake_case for multi-word (`secret_tool.lua`); established domain concepts concatenate (`writequeue.lua`); tests end in `_spec.lua`. Integration filenames mirror the plugin repo minus `.nvim`, hyphens preserved (`nvim-treesitter-context.lua`) — internal identifiers and config keys don't follow file renames.
- Directories: **plural** means the directory is a collection — the files ARE the concept (`tools/`, `secrets/`, `utilities/`); **singular** means a subsystem with a capability (`provider/`, `preprocessor/`, `ast/`). Subfolders name a role, not provenance (`tools/definitions/builtin/`, `secrets/resolvers/`). No self-referential subfolders (`provider/providers/`), and never a `foo.lua` next to a `foo/` directory — collapse into `foo/init.lua`.
- Errors: `flemma.notify` for user-facing errors/warnings; `flemma.logging` for debug/trace; `value, err` tuples for operational results the caller handles inline; never `error()` for recoverable situations.
- Shared infrastructure — search these before writing anything (the Iron Rule's where): `utilities/` (`json`, `path`, `string` — UTF-8-safe width truncation + `escape_pattern`, `truncate` — two-axis lines+bytes, `glob`, `variables` — URN/`$VAR`/`~` expansion, `modeline`, `encoding`, `color`, `display`, `http`, `registry` — name validation, `roles` — role↔wire mapping + highlight group names, `tools` — wire encoding `.`↔`__`, `buffer`, `diagnostic`); `ast/query.lua` — AST traversal helpers, never hand-roll message/segment loops; `buffer/writequeue.lua` — ordered async buffer writes; `buffer/editing.lua` — structural edits; `messages.lua` — string catalogue over `po/flemma-harness.po` (model-facing strings: conversation text, tool schemas — English-only prompt surface, never translated) merged with `po/flemma.po` (user-facing UI strings — the translatable surface, all keys namespaced `ui.*`); keys stay unique across the files, enforced at load (`messages["job.executing.tracked"]{ job_id = id }` renders with variables; bare `messages["tool.denied"]` for consumers that already stringify, e.g. `:describe()`; `messages["tool.denied"]{}` where a real string must materialize immediately, e.g. a stored/returned field with no variables — this also forces a plural entry to render (a bare proxy passed where a real string is required, e.g. a `desc` field or `Suspense.new`, fails); keys are flat dotted identifiers, entries render lazily through the templating engine; brace-call is the house style, auto-applied after stylua by `make format` — see `contrib/scripts/format-messages-brace-call.sh`); `utilities/po.lua` — strict-subset gettext PO parser behind it, returning a uniform `Entry` (a `forms` array plus an optional compiled `plural` selector; plural entries use `msgid_plural`/`msgstr[N]` and a `Plural-Forms` header compiled by `utilities/plural_forms.lua`, chosen when a `count` variable is passed); `utilities/plural_forms.lua` — closure-tree compiler for gettext `Plural-Forms` C-expressions (EN/FR/RU/PL tested); `symbols.lua` — shared glyphs and symbol keys; `cursor.request_move()` — deferred cursor moves during streaming; `hl.lua` — highlight algebra vs `highlight.lua` — group application.
- Registration namespaces follow fixed patterns: extmark namespaces are `flemma_<domain>` created at module load; autocmd groups are `Flemma<Subsystem>` (buffer-local groups suffix `_<bufnr>`); highlight group names must start with `Flemma` (`hl.lua:set()` asserts it); extmark priorities come from the shared `PRIORITY` ladder in `ui/init.lua`, never hardcoded.
- Every extension point (provider adapter, tool definition, preprocessor rewriter, fold rule, template builtin, secrets resolver, personality style) has a registration contract documented in its subsystem's base/init module — read it before adding an instance; adding one is never just dropping in a file.
- Tool definitions access sandbox/truncate/path only through the execution context (`ctx.*`) — direct requires bypass sandbox policy enforcement; input schemas end in `.strict()` (OpenAI strict mode requires it); async tools call their callback exactly once — twice is silently ignored, never is a hang until timeout.

## Buffer Format

`.chat` files use role markers, structured headers, and fenced blocks:

- **Role markers**: `@System:`, `@You:`, `@Assistant:` at the start of a line; content extends until the next marker.
- **Tool Use** (`@Assistant`): ``**Tool Use:** `tool_name` (`tool_id`)`` followed by a fenced JSON block with the tool input.
- **Tool Result** (`@You`): `` **Tool Result:** `tool_id` `` with an optional modeline-parseable `(...)` suffix, then a fenced block with the result.
- **Job Result** (`@You`): `` **Job Result:** `job_id` `` — linked to a tool_result via the job ID; same suffix convention.
- **Status suffixes**: `(pending)` / `(approved)` / `(denied)` / `(rejected)` / `(aborted)` / `(error)`, or explicit `(status=pending sandbox=false)` for mixed metadata — unrecognized tokens round-trip via the AST node's `meta` field.
- **Thinking blocks** (`@Assistant`): `<thinking>` / `</thinking>`, optionally with `provider:signature="base64"` or the `redacted` flag.
- **Expressions**: `{{ lua_expression }}` in `@System`/`@You` messages — sandboxed environment with `math`, `string`, `table`, `utf8`, select `vim.fn`/`vim.fs` functions, and essential globals.
- **File references**: `@./path`, `@../path`, `@~/path`, `@//absolute/path`, optional `;key=value` matrix parameters (`;type=mime/type` sets the MIME type), in `@You` messages.

All tool IDs, job IDs, and metadata are embedded in buffer text so `.chat` files stay portable and re-parseable.

## Testing

- Plenary+Busted style: `_spec.lua` files with `describe`/`it` blocks; write the failing test first when the reproduction is automatable; supporting data in `tests/fixtures/` with scenario-driven names.
- Spec placement (the Iron Rule's why): every `_spec.lua` costs a Neovim process startup plus `flemma.setup`, so a file-per-change habit bloats the suite. Land tests in the owning module's spec inside a focused `describe` block; name a genuinely new spec after its module, mirroring `lua/flemma/…`; keep each block self-isolating — clear only its own `package.loaded` entries.
- When refactoring covered functionality, update the affected specs so the suite stays green; re-run `make qa` after each significant change and expect a zero exit code.
- Clear module caches in `before_each` (`package.loaded["flemma.module"] = nil`) — read existing specs for the pattern.
- Mock HTTP via `client.register_fixture()` / `client.clear_fixtures()` — see `core_spec.lua`.
- New built-in tools shift provider tool counts — use order-independent `find_*_tool()` helpers, never index-based assertions.
- Assert on observable output — window config, buffer text, extmark positions — never internal state. Internal fields stay coherent while the rendered UI is wrong; two Bar-refactor regressions shipped exactly that way.

## Workflow & Releases

- Commits use Conventional Commits (`type(scope): summary`) with a body that captures the rationale.
- If the user wants a direct commit ("just commit", "skip the diff"), skip all worktree inspection and produce a single `git commit -m` command.
- UI adjustments are validated in headless Neovim — never attach screenshots or recordings.
- For large or risky refactors, draft a plan and confirm with the user before implementation.
- Changesets: `.changeset/<descriptive-slug>.md` with frontmatter `"@flemma-dev/flemma.nvim": patch|minor|major` and a one-line summary. `patch` = fixes and internal improvements; `minor` = new features or config options; `major` = breaking changes to API, config, or buffer format. Skip for pure refactors, CI/tooling, test-only changes, and CLAUDE.md updates.
- Releasing: `pnpm changeset version` consumes pending changesets, then commit the result; a GitHub Actions workflow opens a "Version Packages" PR as changesets accumulate on `main`. Each minor release gets a single-word typographic codename via the `release-naming` skill (logged in the `Incipit` ledger).
- Session closure: `make format`, then `make qa`, then note outstanding follow-ups the next agent will need.

## Gotchas & Pitfalls

One entry per learning: **bold symptom** → fix. Add new ones as they're earned — only if they clear the Knowledge Management bar.

**Lua/LuaJIT/Neovim**

- **`tostring(5.0)` returns `"5"` in LuaJIT**, not `"5.0"` — account for it in assertions and formatting of numeric results.
- **`a and b or c` fails when `b` is falsy** — `true and false or x` yields `x`. Explicit `if/else` whenever the true-branch value can be `false` or `nil`.
- **`os.tmpname()` creates and leaks a file on LuaJIT** — it `mkstemp()`s into shared `/tmp` and returns the name. Use `vim.fn.tempname()` (private per-instance dir, removed on exit).
- **`vim.NIL` is truthy** — JSON `null` decoded without `luanil` passes `if x then` guards and crashes on math/string ops. This is why the JSON Iron Rule exists.
- **`nvim_set_option_value` with only `win` acts like `:set`, not `:setlocal`** — it mutates the global value too; pass `{ win = w, scope = "local" }` for any window-local intent.
- **`vim.deepcopy` clones table keys, not just values** — symbol-keyed tables silently lose identity lookups; copy them with `symbols.deepcopy()`.
- **Replacing buffer lines pushes extmarks to the start of the replaced range** — reposition after structural injection (see `indicators.reposition_tool_indicators()`).

**Project**

- **Stale `vim-pack-dir` copy shadows working-directory changes** — headless runs must `set rtp^=` (prepend), never `+=`; verify with `debug.getinfo(require('flemma.ui').some_fn, 'S').source`.
- **Provider `new()` metatable chains break subtly** — each provider sets the full chain atomically in its `setmetatable` literal before `self:_new_response_buffer()`; intermediate bases exist (`moonshot → openai_chat → base`).
- **Tool header backticks are parse-critical** — ``**Tool Use:** `name` (`id`)`` and `` **Tool Result:** `id` `` need exact backtick wrapping or parsing fails.
- **Fixed paths under `${TMPDIR:-/tmp}` collide across parallel test processes** — `make qa` runs specs concurrently across Neovim versions and buffer numbers repeat per process, so one process's cleanup lands inside another's create→assert window. Use `vim.fn.tempname()` roots or the pid-scoped unnamed-store default.
- **Hook-payload mocks must honor type contracts** — `hooks.dispatch()` reaches every subscriber registered by `flemma.setup()`, and errors in `vim.schedule`d continuations fail no test. Build payloads with real constructors (`session.Request.new(...)`) and disable subsystems the spec doesn't exercise.
- **Registry `pairs()` order is nondeterministic** — sort by name when building tool arrays or deterministic prompt caching breaks.
- **Custom secrets resolvers must implement `resolve_async(self, credential, ctx, callback)`** — the walker prefers it; a sync `:resolve` doing `vim.system(cmd):wait()` blocks the editor. `provider:resolve_credential()` returns `flemma.secrets.Result|nil` only — failures flow through suspense boundaries, not return values.
- **AST positions are 1-indexed; `nvim_buf_*` and extmark rows are 0-indexed** — every boundary crossing subtracts one; off-by-ones here put indicators on the wrong lines.
- **Tool lists for provider requests must come from `tools.get_for_prompt()`** — it blocks on `ensure_ready()`; reading the registry directly lets async MCP sources establish a partial prompt-cache prefix, invalidating the cache for the rest of the conversation.
- **`make format` reports high file-change counts that don't reflect real drift** — treefmt reformats, then `format-messages-brace-call.sh` fixes brace-call style; the two passes touch many files but cancel out. Trust `git status`/`git diff` for what actually changed, not the formatter's stdout.

## Knowledge Management

CLAUDE.md is the single source of truth for project knowledge — version-controlled and shared with every contributor and agent. No local memory files; no splitting into linked files (only known paths auto-load; linked files get missed).

What belongs here is **normative** (tells the next actor what to do — rules, conventions, principles) or **hard-won** (a learning that cost real debugging time) — and only if it is **broadly applicable**: something a contributor could trip over anywhere, or must know before they'd find the right file. Hard-won measures cost, not reach, and placement follows reach — a learning confined to one module lives in a code comment at its point of use, not here. What never belongs is anything the codebase already says — code, comments, `---@class` annotations, filenames. A new MUST/NEVER lands as an Iron Rules one-liner; a new cross-cutting learning lands as a symptom→fix entry in Gotchas & Pitfalls.
