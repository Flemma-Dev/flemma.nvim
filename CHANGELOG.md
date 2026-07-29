# Changelog

## 0.14.0

### Minor Changes

- c3c0662: mcporter tool calls now honour a call timeout. Flemma passes `--timeout` (milliseconds) to `mcporter call`, derived from `tools.mcporter.timeout`, and exposes an optional per-call `timeout` (seconds) in every discovered tool's input schema — mirroring the built-in `bash` tool — so the model can extend the budget for slow tools such as deep research. Previously neither the configured timeout nor a model-supplied `timeout` reached mcporter: the value was serialized into the tool arguments and silently ignored while mcporter fell back to its own default. A grace window now lets mcporter report its own timeout before Flemma force-kills the subprocess, and a server-owned `timeout` parameter is left untouched.
- a2b8065: Model strings accept URI matrix parameters: `flemma.opt.model = "vertex/gemini-3.1-pro-preview;project_id=x"` decomposes into provider, model, and provider-scoped parameters everywhere a model is named (config, `:Flemma switch`, presets), with source-order precedence, `;key=nil` clearing, and deterministic command-line-over-preset overrides in both grammars. `@file` references accept the same multi-key `;key=value` options (quote a parameterized MIME: `;type='text/plain;charset=utf-8'`). Preset parameters normalize to the config shape — provider-specific keys nest under the provider namespace.
- 37864f3: Refreshed model definitions and pricing across all four providers (July 24, 2026):
  - **Anthropic** — added Claude Opus 5 (`claude-opus-5`, $5/$25 per MTok, 1M context, 128K output) and Claude Fable 5 (`claude-fable-5`, $10/$50, 1M/128K), both adaptive-thinking. Corrected Claude Sonnet 4.6's max output to 128K (was 64K), and raised the `max` thinking level to the API's `max` effort on Sonnet 4.6 and Sonnet 5 — per Anthropic's effort docs, `max` is available on every adaptive-thinking model (Opus 4.5, which has effort but not adaptive thinking, still clamps to `high`). The intermediate `xhigh` level — available on Fable 5, Opus 5, Opus 4.8, Opus 4.7 and Sonnet 5 — remains unreachable, since Flemma's canonical levels stop at `max`. Replaced the family-wide `min_cache_tokens` approximation with the documented per-model minimum cacheable prefix, which is not monotonic across generations: 512 for Opus 5 and Fable 5; 1024 for Opus 4.8, Sonnet 5, Sonnet 4.6, Sonnet 4.5, and Opus 4.1; 2048 for Opus 4.7; 4096 for Opus 4.6, Opus 4.5, and Haiku 4.5. This corrects the cache-percentage indicator, which previously hid cache stats on prompts that were in fact cacheable (Opus 5, Opus 4.8, Sonnet) and showed them on prompts that were not (Opus 4.6, Opus 4.5).
  - **OpenAI** — added the GPT-5.6 family: `gpt-5.6-sol` (with its `gpt-5.6` alias, $5/$30), `gpt-5.6-terra` ($2.50/$15), and `gpt-5.6-luna` ($1/$6), all 1.05M context / 128K output and the first OpenAI models with a native `max` reasoning effort and a billed cache-write rate ($6.25/$3.125/$1.25 per MTok). Dropped eleven models shut down on July 23, 2026 (`gpt-5-codex`, the four `gpt-5.1-*` variants, `gpt-5.2-codex`, `o3-deep-research`, `o4-mini-deep-research`, `computer-use-preview`, and the two `*-search-preview` models). `gpt-5`, `gpt-5-mini`, `gpt-5-nano`, `gpt-5-pro`, `o3`, and `o3-pro` are now marked deprecated (retiring December 11, 2026); the stale deprecation note on `gpt-5.1` was removed.
  - **Google (Vertex AI)** — added Gemini 3.6 Flash (`gemini-3.6-flash`, $1.50/$7.50) and Gemini 3.5 Flash-Lite (`gemini-3.5-flash-lite`, $0.30/$2.50). Dropped `gemini-2.0-flash` and `gemini-2.0-flash-lite` (and their `-001` snapshots), retired June 1, 2026. Gemini 2.5 models are noted as retiring October 16, 2026.
  - **Moonshot AI** — added Kimi K3 (`kimi-k3`, $3/$15 per MTok, $0.30 cache hit, 1M context, 128K output). K3 always reasons and configures depth through the top-level `reasoning_effort` field rather than the K2 family's `thinking` object. The `moonshot-v1-*` line is noted as sunsetting August 31, 2026.

- 2ec02c4: Survive `viewoptions+=folds`: while a chat buffer is active, `folds` is stripped from `viewoptions` so `:mkview` no longer persists stale fold state (tweakable via `editing.manage_viewoptions`), and fold settings clobbered by a `:loadview` of a pre-existing view (`foldmethod=manual`, `foldexpr=0`) are now detected and fully re-applied — previously only `foldmethod` was restored, leaving a dead foldexpr and no folds at all.

### Patch Changes

- 16b5d0c: Fixed a crash when a Flemma module is `require()`d before `setup()` runs. The experimental Codex adapter registers its ChatGPT secrets resolver as a load-time side effect, and that path asserted the config system was already initialized — so merely requiring the adapter in isolation threw `config.init() must be called before register_module_defaults()`. This broke tools that load every module in a bare Neovim, most notably nixpkgs packaging (`nvimRequireCheck`). Config now queues module-default registrations that arrive before initialization and flushes them once `setup()` supplies the schema, so any module can be required standalone and its defaults still land.
- 1489470: Fixed fence overlay rendering for wide and nested code fences — bar now scales to the actual backtick count, and inner backtick lines inside a wider fence are no longer overlaid
- d458544: Fix `provider/model` shorthand (e.g., `flemma.opt.model = "anthropic/claude-opus-4-8"`) in setup opts and frontmatter — previously only worked in `:Flemma switch` commands.
- be8eec2: Foreign thinking is now injected as tagless prose ("Here is some context to help you: …", closed by a lone `---` rule) instead of an XML-style wrapper. Anything framing the model's own prior turns is eventually reproduced verbatim in replies, so the framing must stay harmless when echoed — tag pairs re-enter the conversation as structure. The framing lives in the string catalogue (`thinking.foreign.wrap` in `po/flemma-harness.po`).
- 93089d2: Fix the `flemma.jobs.status` tool's `job_id` parameter: its guidance text was passed as `s.string(<default>)`, so it shipped as a JSON Schema `default` (a nonsense default value) with no `description` for the model. It now renders as the parameter's `description`, so the model finally sees how to fill in `job_id`.
- 37864f3: The unified `thinking` parameter now controls reasoning depth on Kimi K3. K3 configures thinking through the top-level `reasoning_effort` field rather than the K2 family's `thinking` object, so setting `thinking` had no effect and every request reasoned at the server default of `max` — the most expensive setting, with no way to make K3 cheaper or faster. Flemma's canonical levels now map onto the three values the API accepts: `minimal` and `low` send `low`, `medium` and `high` send `high`, and `max` sends `max`. K3 cannot stop reasoning, so thinking turned off sends `low` — the floor — rather than omitting the field and silently inheriting `max`. Temperature is locked to 1.0, which Moonshot fixes on K3 as it does across the K2.x line.
- a64c027: Corrected three model limits that were wrong against provider documentation:
  - `gpt-5-pro` reserves 272K of its 400K context window for output, leaving 128K for input — the inverse of every other GPT-5 model. Its `max_input_tokens` had been set to 272000 (the output figure), so the context indicator showed a request as half-full when it was already over the limit.
  - `gemini-2.5-pro`'s thinking budget floor is 128, not 1. Only 2.5 Flash accepts a budget of 1; thinking cannot be turned off on 2.5 Pro at all.
  - `gpt-5.3-codex-spark`'s input limit is 96000 (its 128K context window minus the 32K output reservation), not 100000. Its entry now records that it is a research preview with restricted API access and that its pricing mirrors `gpt-5.3-codex` rather than a published rate.

  Also dropped `thinking_budgets` from the Gemini 3 entries that still carried them. Google publishes a `thinkingBudget` range for Gemini 2.5 only, Gemini 3 uses `thinkingLevel`, and a request carrying both parameters returns an error. The budgets were never sent — but they clamped numeric budgets before mapping them to a level, so the same configured budget resolved to a different `thinkingLevel` on `gemini-3-flash-preview` than on `gemini-3.5-flash`.

- a64c027: Fixed the request Flemma sends to `kimi-k2.7-code` and `kimi-k2.7-code-highspeed`. Both were declared as thinking-toggle models, so turning thinking off sent `thinking = {"type": "disabled"}` with `temperature = 0.6` — a combination the API rejects outright, since thinking on the K2.7 Code family is always on and cannot be disabled. They are now declared `forced`: no `thinking` object is sent at all (Moonshot documents it as omittable, and the only form it accepts when set explicitly is `{"type":"enabled","keep":"all"}`), and temperature is locked to the 1.0 the API fixes it at. Parameter validation now warns about fixed sampling parameters on every K2.x/K3 model rather than only the toggleable ones.
- ce89e46: Fix assistant turns being silently emptied by an unterminated `<thinking>` block: the collected content is now preserved as thinking instead of dropping the rest of the turn from the AST. `</thinking>` still only closes a block on a line of its own — the token followed by content is treated as thinking prose (HTML/XML examples, format transcripts).
- 6e7796f: Externalized conversation messages, tool definition strings, and the full user-facing surface into gettext PO catalogues, split by audience: `po/flemma-harness.po` holds model-facing strings (conversation text, tool descriptions, runtime tool output and error messages, shared truncation-overflow notices, and each tool's coding-assistant personality snippet and guidelines — English-only prompt surface), `po/flemma.po` holds user-facing UI strings (the translatable surface, all keys namespaced `ui.*`). Covers notifications (usage, rejection popup, tool actions, :Flemma commands, send-pipeline guards, provider switch/initialize, diagnostics, build-prompt failures, autopilot, presets, hooks, secrets, config validation, sandbox, migration, response truncation, max-tokens clamping, request/cURL errors), keymap descriptions, inline progress-spinner and tool-status indicator labels (the `virt_text` waiting/executing/pending/complete/failed states and the streamed-character counter), user-triggered template diagnostics (file references, includes, expression errors, `@file` open/read failures), and buffer parse diagnostics for malformed tool-use/tool-result blocks. Adds gettext plural support — `msgid_plural`/`msgstr[N]` selected by a compiled `Plural-Forms` expression (EN/FR/RU/PL), fixing e.g. "1 orphaned job resolved" vs "N orphaned jobs resolved". A `make qa` gate (`lint-messages.sh`) validates key resolution, call-site↔template variables, `#. Variables:` comments, no pure-formatting entries, and newline-only joins between translations. Rendered strings are unchanged (still English by default); keys stay unique across the files, enforced when the catalogue loads.
- 3968948: Fix Gemini 3+ rejecting conversations migrated from another provider (HTTP 400): tool calls without a native Vertex thought signature now carry Google's documented migrated-trace placeholder, and buffered API error bodies are logged so failures stay diagnosable from the log file.
- ea64058: Fixed Vertex AI service-account authentication. The gcloud secrets resolver handed the service-account key to `gcloud auth print-access-token` via `GOOGLE_APPLICATION_CREDENTIALS`, but that subcommand ignores the variable and silently uses the active `gcloud auth login` account — so the service account was never actually used, and Vertex broke whenever the user login required reauthentication. Service-account keys are now minted through `gcloud auth application-default print-access-token` (with the cloud-platform scope), which reads the key and is immune to user reauth.

## 0.13.1

### Patch Changes

- e4a907d: Fixed `read`/`write`/`edit` so `$FLEMMA_TOOLS_STORE_PATH/<file>` resolves to the buffer's store directory — the same place `flemma.save_to` writes. Previously a tool could save a file with `flemma.save_to: "$FLEMMA_TOOLS_STORE_PATH/…"` and then get "File not found" reading it back.
- 801b63f: `config.materialize()` now expands a `$preset` model reference into its concrete provider, model, and merged parameters as part of materialization. Previously every call site that needed the effective config had to wrap materialize in `normalize.resolve_preset(...)` — a two-step dance that was easy to forget, leaving `$preset` aliases unexpanded and reaching model logic as literal strings. Preset expansion now lives with the config facade (the other config-domain expansion, e.g. `$preset` list references, already did); `normalize.resolve_preset` is removed. `config.get()`/`config.inspect()` continue to return the raw alias, which is what setup's one-time `presets.resolve_default` reads.

## 0.13.0

### Minor Changes

- 731ee95: Add inline approval widget on the closing fence line of pending tool results. Shows a pause icon, optional tool label, and keybind hints when the cursor is within range. Approved-but-not-executed tools show a check icon; executing and terminal-status tools show an hourglass with the label. All labels render on the fence line — never as virtual lines inside the fenced block.
- 0a40d7a: Auto-scroll viewport during streaming responses. The cursor follows new content to the bottom (tail mode), disengages when the user moves away (breakaway), and re-engages when the user navigates back to the last line (re-attach). All non-forced cursor moves respect breakaway state so the user can freely explore the buffer during autopilot.
- eab0d0b: Tool capabilities now gate harness parameter injection — `disables_background` prevents `flemma.background` and `disables_save_to` prevents `flemma.save_to` from appearing in a tool's schema. Harness tools declare both, fixing duplicate store files when the LLM copied `flemma.save_to` onto status checks. Existing capabilities renamed to verb_target convention: `emits_template`, `auto_approves_if_sandboxed`.
- 38e64f0: Added experimental Codex provider for ChatGPT subscription authentication. Users with a ChatGPT subscription can now use their existing `codex login` token to drive Flemma, without needing a separate OpenAI Platform API key.

  Enable via `providers.modules = { "flemma.provider.adapters.experimental.codex" }` in your Flemma setup config.

  Also includes:
  - `providers.modules` config key for registering non-built-in provider adapters
  - `provider/model` slash syntax (`codex/gpt-5.5`) for `:Flemma switch`, presets, and frontmatter
  - `openai_responses.lua` intermediate base for Responses API wire format reuse
  - `resolve_credential()` on provider base for metadata-rich credential resolution

- 2afb5cd: Added local token estimation for Codex provider and fixed preset resolution in usage prefetch
- 57fca24: Add `editing.compact_headers` config option (default `true`) to omit the blank line between Tool Use, Tool Result, and Job Result headers and their fenced code blocks
- 9ded5a0: Replace string-based highlight DSL with composable `flemma.hl` builder API. All highlight construction — config defaults and internal derivations — now uses lazy ops (`h.link`, `h.from`, `h.themed`, `h.coalesce`, `h.diff`, `h.attrs`, `h.hex`) with chainable methods (`:blend`, `:pick`, `:omit`, `:contrast`, `:tint`, `:mute`, `:style`, `:merge`) and terminal `:get()`/`:set()`. The old string syntax (`"Normal+bg:#101010"`, `"Folded!bg"`, `{ dark = "...", light = "..." }`) is removed entirely. `highlights.role_style` replaced by `highlights.role_name` (an HlOp). `highlights.defaults` removed.
- 3c01208: Highlight config fields now accept plain strings: a group name coerces to `h.link()`, a `#RRGGBB` hex value coerces to `h.hex()`. This removes the need to `require("flemma.hl")` for simple overrides.
- 8a161a4: Add `h.none()` to the `flemma.hl` highlight builder — a no-op op whose `:get()` resolves to nothing and `:set()` does nothing. Use it as a config value to leave a highlight group unmanaged by Flemma (e.g. `highlights = { thinking_tag = h.none() }`), so the colorscheme or your own definition stands.
- 8157711: HlOps `tint`, `mute`, and `blend` now accept an optional ratio parameter and an HlOp color source, enabling expressions like `h.from("Normal"):tint("bg", h.from("DiagnosticWarn"):pick("fg"), 0.10)`
- 8bf2cee: Added inline rejection popup that replaces `vim.ui.input` for tool rejection feedback. The floating window overlays the tool result fence block with `╌` borders, supports multi-line editing via Vim motions, and is fully configurable (`ui.rejection.enabled`, `ui.rejection.winblend`, `highlights.rejection_input`, `highlights.rejection_border`). Set `ui.rejection.enabled = false` to revert to the original command-line prompt.
- cc80506: Updated model definitions and pricing:
  - **Anthropic** — added Claude Sonnet 5 (`claude-sonnet-5`): adaptive thinking, $3/$15 per MTok standard (introductory $2/$10 through August 31, 2026), 1M context, 128K max output (mirrors Sonnet 4.6's request surface). Added alongside Claude Sonnet 4.6, which remains the default Anthropic model.

- 9dbd329: Updated model definitions and pricing:
  - **Anthropic** — added Claude Opus 4.8 (`claude-opus-4-8`): adaptive-thinking-only, $5/$25 per MTok, 1M context, 128K max output (mirrors Opus 4.7's request surface). Removed Claude Opus 4 (`claude-opus-4-0` / `claude-opus-4-20250514`) and Claude Sonnet 4 (`claude-sonnet-4-0` / `claude-sonnet-4-20250514`), which retired on June 15, 2026 and now return errors. Noted Claude Opus 4.1's deprecation (retiring August 5, 2026).
  - **Moonshot** — added Kimi K2.7 Code (`kimi-k2.7-code`, $0.95/$4.00) and its faster `kimi-k2.7-code-highspeed` tier ($1.90/$8.00), both with toggleable thinking. Added explicit cache-read pricing to the legacy Moonshot V1 models (uniform, no cache discount).

- 55922cb: Removed `:Flemma import` command and Claude Workbench import support
- c15f633: Secrets resolvers now own their config schema (`metadata.config_schema`), composed into the `secrets` config namespace via DISCOVER — the same pattern provider adapters and sandbox backends use. Defaults materialize when a resolver registers, and custom resolvers can declare their own `secrets.<name>` options. `secrets.chatgpt.auth_file` is now a configurable `setup()` key (effective when the experimental Codex adapter is loaded, which self-registers the ChatGPT resolver).
- 832b93b: Surface subscription rate limits (5-hour, weekly) from Codex/ChatGPT response headers in the usage bar and as lualine statusline resolvers
- f86af3b: Add `:tint(attr, hex)` and `:mute(attr, hex)` theme-aware blend methods to the `flemma.hl` builder. `:tint()` offsets away from the theme background (making colours more distinct), `:mute()` offsets toward it (making colours more subdued). Both automatically flip blend direction based on `vim.o.background`, replacing verbose `h.themed()` + flipped `+`/`-` patterns with single-line calls.
- 34691fd: Added treesitter-powered syntax highlighting for tool preview virt_lines. Bash commands now render with per-token syntax coloring. Any tool can opt in by returning `highlight = { lang = "language_name" }` from its `format_preview` method. Falls back silently to flat highlighting when the treesitter grammar is unavailable.
- ac56bc9: Added tool result store for durable materialization of tool output.

  Tool results can be materialized to deterministic file paths alongside the .chat file (opt-in via `tools.store.materialize`, layout via `tools.store.path_format`). Truncation overflow now always lands at the durable store location, replacing ephemeral `$TMPDIR` files. Breaking: `tools.truncate.output_path_format` is removed — truncation overflow now routes through the store.

  New config: `tools.store.{path_format, unnamed_path_format, materialize, preview, backup}`.

- f90efda: Added `flemma.save_to` and renamed the background parameter to `flemma.background`.

  Every tool schema now carries an optional `flemma.save_to` parameter: the model can redirect full tool output to a file and the conversation receives a short preview plus the saved path instead. The `bash` tool exports `$FLEMMA_TOOLS_STORE_PATH` pointing at the conversation's store directory, which is sandbox-writable by default via the new `urn:flemma:store` policy variable. The background-execution parameter is now namespaced as `flemma.background`; both harness parameters are stripped from tool input before execution and respect strict-mode schema invariants.

  `tools.store.materialize` now defaults to `false` — only truncation overflow and explicit `flemma.save_to` redirects write to the store unless opted in.

### Patch Changes

- 4f10bd6: Fixed approval preview: leading symbol always shown, generic multiline previews put tool name on its own line, continuation indent respects buffer shiftwidth
- 7063a39: Improved tool throttle notification to show queued count and running slots instead of cryptic "Executing 0/1" format
- 0642363: Terminate SSE stream after response.completed to avoid idle connection tail
- 9b13f26: Fix line highlight groups (`FlemmaLine*`) being lost after a colorscheme change. Groups are now re-established on every `apply_syntax()` call instead of once at setup time.
- bfb6e6c: Highlight groups now refresh automatically when switching colorschemes mid-session. A `ColorScheme` autocmd re-runs `apply_syntax()`, and since builder operations resolve lazily with no cache, all groups pick up the new colorscheme's colours immediately.
- ee99627: Fixed background parameter not being injected into tool schemas for Chat Completions providers (Moonshot/Kimi)
- cd8159c: Fixed CursorLine not highlighting text in chat buffers when line_highlights is disabled
- 69639c3: Fixed parser bug where malformed JSON in a tool_use block caused all subsequent tool_use blocks in the same message to be skipped.
- 7142363: Fixed tool preview backgrounds leaving black bands after window resize (e.g. opening/closing a sidebar)
- b2802ae: Fixed "Unknown tool" errors appearing on first send when async tool sources (e.g., MCPorter) are still loading and frontmatter references tools from lazy modules
- 628fd22: Fixed "N more lines" indicator in tool previews not inheriting the role line background highlight
- b1bd6b3: Show status text and colored icons in fold previews for rejected, denied, and aborted tool results
- 7e61cb3: Tool use blocks now fold whenever a matching tool result exists, regardless of the result's status
- dd2aae5: Surface actionable diagnostic when gcloud credentials expire instead of a bare exit code
- b64ede9: Eliminate all raw `nvim_get_hl`/`nvim_set_hl` calls from `highlight.lua`, fully delegating to `hl.lua` builder ops. Add `h.default(attr)` constructor for Normal-with-fallback resolution. Expose `highlights.tool_label` and `highlights.progress_accent` as configurable schema entries.
- e633490: Background job results are now delivered on every send — autopilot cycles included — instead of waiting for the conversation to reach full idle. Previously a completed job's result could arrive several turns late while the model polled `flemma.jobs.status`, with each poll itself postponing delivery. The status tool also no longer reports finished jobs as a bare "queued": completed-but-undelivered jobs report `completed (delivery pending)` with `elapsed_seconds` frozen at the job's actual runtime.
- 9401492: Fix missing usage bar and session recording when using preset-based providers
- 095bb11: HTTP request body files no longer litter `/tmp`. The client wrote every request body via `os.tmpname()`, which on LuaJIT `mkstemp()`s a `/tmp/lua_XXXXXX` file that nothing ever removed (one leaked, empty file per request), and the `flemma_lua_*` body beside it — world-readable — survived whenever Neovim was killed before the request's `on_exit` fired. Bodies now live in Neovim's private per-instance temp directory (`vim.fn.tempname()`, mode 0700), which Neovim removes wholesale on exit.
- 83049ce: Unnamed-buffer store paths are now process-unique. The default `tools.store.unnamed_path_format` is `${TMPDIR:-/tmp}/flemma/unnamed/{{ flemma.pid }}/{{ bufnr }}/{{ source }}_{{ name }}_{{ id }}.txt` (previously `…/flemma/unnamed-{{ bufnr }}/…`). Buffer numbers restart in every Neovim instance, so concurrent instances sharing `$TMPDIR` could commingle results in — and delete — each other's unnamed store directories, intermittently dropping the sandbox `urn:flemma:store` grant. `{{ flemma.pid }}` is also available to custom store path formats, and the per-process subtree keeps `$TMPDIR/flemma` to a single `unnamed/` directory.
- 93e5c97: Reject completed tools early: show error before opening the rejection UI instead of after the user submits feedback
- 1f0352a: Fixed the sandboxed `bash` tool hanging on Neovim 0.12+ when a command invokes an interactive pager. The 0.12+ terminal (PTY) backend gives commands a tty on stdout, so `git` (and `less`/`man`) launch the user's pager; the window-less terminal buffer's PTY is only a few rows tall, so any multi-line output (such as `git log`) pages and blocks until the tool times out. The terminal backend now sets `GIT_PAGER=cat` and `PAGER=cat`, matching the non-PTY backend's behavior (piped stdout never triggers a pager). This also resolves the earlier "Error: missing file" symptom, which was the same pager failing fast under bubblewrap's `--new-session`.
- 73f24ae: Fixed sandboxed commands failing outright when a configured `rw_paths` entry does not exist on disk (e.g. the lazily-created tool result store directory): nonexistent paths now drop out of the resolved policy instead of producing a bwrap mount error, degrading to "not writable" until the directory exists.
- 95a886f: Fix statusline muted text rendering with colorschemes that use `reverse` on StatusLine (e.g., wildcharm). Derived groups now strip `reverse`/`bold`/`cterm` via `:pick()` and use `nocombine` to prevent attribute bleedthrough in `%#Group#` statusline escapes. Remove `ExpectOp` — replaced by `:pick(..., { strict = true })`.
- 245df16: The tool label (`FlemmaToolLabel`) — the approved tool-result footer and the label shown in folded message previews — now renders in the muted preview color with an italic accent instead of inheriting the bright `Normal` foreground. It is built by merging the `tool_label` accent onto `tool_preview` (the `progress_accent` pattern), so the approved footer no longer jars against the muted command-preview lines above it. Set a `fg` in `highlights.tool_label` to recolor the label.
- b1639c3: Repeated `setup()` calls no longer stack duplicate usage-bar hook subscribers — each `usage.setup()` now disposes its previous `request:finished`/`buffer:destroyed` subscriptions before re-registering.

## 0.12.0

### Minor Changes

- fa02a31: Added glob pattern support in `auto_approve` lists — entries containing `*` match tool names (e.g., `"flemma:*"`). The `$standard` preset now includes `flemma:*` to auto-approve harness tools.
- 5af8a62: Added background job support for async tools. Tools can run in the background without blocking the conversation — the model requests it via `background: true`, or the user moves an executing tool mid-flight with `<M-b>` (`:Flemma tool:background`). Completed results are delivered as `**Job Result:**` blocks when the conversation reaches idle. Orphaned jobs are detected and resolved on file reload.
  - `flemma:jobs:status` harness tool lets the model query job status
  - Jobs observability bar shows active count, spinner, and autopilot resume countdown (`ui.jobs.position`)
  - `tools.autopilot.resume_delay` (default 2000ms) debounces auto-continue after job completion; Ctrl+C cancels
  - Cursor-aware Ctrl+C with double-tap RAGE cancel (cancels all tools and the active request)
  - `hooks.on(name, callback)` Lua subscriber API alongside User autocmds
  - New hooks: `conversation:idle`, `job:submitted`, `job:completed`, `autopilot:resume-scheduled/cancelled/resumed`
  - Job result blocks: syntax highlighting, folding, fold text preview, LSP hover and go-to-definition

- fa02a31: Migrated conceal keybindings from `<Space><Space>` to `yoe` (toggle), `]oe` (enable), `[oe` (disable), following Neovim's option-toggle convention
- dedaac7: Eliminated 88% per-keystroke overhead in .chat buffers caused by Neovim's treesitter `conceal_lines` interaction with `conceallevel>=2`. Typing latency drops from ~36ms to ~4ms per keystroke on large buffers. Fenced code block delimiters are now styled with configurable overlay extmarks instead of being hidden via conceal. Adds `experimental.patch_markdown_conceal` config flag and `highlights.fence_label`/`highlights.fence_bar` highlight groups. Frontmatter folds now work at any conceallevel.
- 54ac02d: Added op-prefix syntax for list-valued config fields (+append, ^prepend, !remove, $spread from preset). Presets now support a `tools` field for controlling available tools via `:Flemma switch`.
- e84f62f: Run test suite against multiple Neovim versions (0.11 and 0.12) in parallel during `make qa`
- aac445f: Bash tool now executes commands in a Neovim terminal buffer instead of a raw job pipe. Output behavior is unchanged but programs that detect TTY on stdout may produce different formatting (e.g., colored output, columnar layout). stdin is redirected from /dev/null to prevent interactive programs from blocking.
- fa02a31: Redesigned tool result indicators with a two-extmark model: inline `⬢` icon + EOL status text, each with dedicated highlight groups (`FlemmaToolIcon{Pending,Executing,Success,Error}` and `FlemmaTool{Pending,Executing,Success,Error}`)
- 34179cc: Changed tool name separator from `:` to `.` for consistency with MCP and conventional namespace syntax. Existing `.chat` files are migrated automatically on open. Tool modules can now export `.approval` to register approval resolvers via `tools.modules`, replacing the module-path-in-auto_approve pattern.
- 6113f7e: Added zy/zY keybindings to fold conversation turns to first/last message, hiding intermediate tool use and results for a quick overview

### Patch Changes

- e042cfb: Fixed bar float windows getting stuck on screen when dismissed during a command-line window (q:, q/, q?)
- e3c2fa4: Fixed silent data loss in bash tool output on Neovim 0.11.x under load (libuv#4992). The terminal backend is now gated to 0.12+ where the PTY flush bug is fixed; 0.11.x uses a jobstart+sink backend that collects output reliably via callbacks.
- 09015cc: Fence overlay extmarks are now only shown when conceallevel >= 2; toggling conceal off reveals raw ``` delimiters. Markdown buffers in the same session regain native fence concealing via automatic highlighter restoration.
- d76312f: Decode wire-format tool names (e.g., `trello__tool_name` → `trello.tool_name`) in the progress bar
- 2a6b02f: Fixed async tool sources (e.g., mcporter) seeing schema defaults instead of user config when their config schema is DISCOVER-resolved
- 1e8774a: Improved typing responsiveness on large .chat buffers by deferring fold evaluation during insert mode
- 3d31a34: Fixed empty tool input encoding as `[]` instead of `{}` — the Anthropic streaming response sends no input deltas for empty tool input, causing the sink to read as `""` which failed JSON decode and fell back to an untagged `{}` that encoded as `[]`
- 54ac02d: Fixed `get_for_prompt` to respect an explicit empty tools list from non-DEFAULTS layers
- 34ff016: Fixed E5108 crash when pressing Alt+Enter to execute a tool while tool discovery is still in progress
- e2e6e82: Fence bar/label extmarks now get contrast-adjusted highlights when overlapping with CursorLine, ensuring readability on colorschemes where the default fence foreground blends into the CursorLine background
- 078fc97: Fixed unreliable auto-folding of `<thinking>` blocks in multi-turn conversations
- 9644ab9: Fold text previews now fall back gracefully when a tool's preview formatter encounters unexpected input
- f9f8d26: Fixed job ID collisions when reopening `.chat` files from a previous session — duplicate IDs caused job completions to be injected adjacent to the wrong tool_result, corrupting conversation history
- 85fe6f8: Fixed activity bar segment ordering so the resume countdown appears before the job count, keeping jobs visually stable regardless of whether a resume timer is active
- c267e7f: Fixed "Unknown tool" errors when executing tools from lazy-loaded third-party modules
- 1e9cf37: Fixed MCPorter tool calls failing when input is empty (e.g., `trello:list_workspaces`) — `json.encode({})` produces `[]` which mcporter rejects as not a JSON object
- 242ef24: Fixed background tool execution when tool definitions finish loading during tool result processing.
- c7d0a22: Fixed infinite "Tool is already executing" loop after undoing and resending a response with background tool calls
- fa02a31: Renamed `tool:finished` hook to `tool:completed` (`FlemmaToolFinished` → `FlemmaToolCompleted`)
- e72aed3: Bash tool now sets terminal scrollback to `-1` (Neovim's maximum) instead of a hardcoded `100000`, automatically using the highest supported value for the running Neovim version.
- 5dfbb63: SVG files are now treated as text instead of binary images, fixing read tool and file reference handling for text-based image formats
- 7914d16: Fixed Tool Use blocks not folding simultaneously with their Tool Result blocks
- 34ff016: Fixed manual tool approval (Alt+Enter) ignoring the `background` execution flag, causing tools to run foreground instead of as background jobs
- 6cc04c5: Updated all provider model data: removed retired models (Claude Haiku 3, Moonshot K2 series), added new Vertex models (Gemini 3.5 Flash, 3 Pro, 3.1 Flash Lite), fixed OpenAI chat-latest context limits and deprecation annotations, and corrected Moonshot vision model exclusions

## 0.11.0

### Minor Changes

- 2d4298f: Added `@//path` file reference syntax for absolute paths — `@//tmp/image.png` resolves to `/tmp/image.png`. The read tool now emits `@//` references for absolute paths instead of incorrectly prepending `./`.
- 6b36e48: Extract reusable Bar UI utility and reorganise ui config namespace.

  **Breaking changes (default behaviour is unchanged for users who did not customise these keys):**
  - Config namespace moves under `ui`. Rename `notifications.*` → `ui.usage.*` and `progress.*` → `ui.progress.*`.
  - Removed config keys: `notifications.limit`, `notifications.border`, `notifications.zindex`, `notifications.position`, `progress.zindex`. Stacking, the underline border, and the z-index overrides are gone by design.
  - Highlight groups `FlemmaNotificationsBar`, `FlemmaNotificationsSecondary`, `FlemmaNotificationsMuted`, `FlemmaNotificationsCacheGood`, `FlemmaNotificationsCacheBad` rename to `FlemmaUsageBar{,Secondary,Muted,CacheGood,CacheBad}`. `FlemmaNotificationsBottom` is removed with the border feature. Fallback chains and computed colours preserved exactly.
  - User command `:Flemma notification:recall` renames to `:Flemma usage:recall`.

  **New capabilities:**
  - Usage bar and progress bar each gain a `position` option; choose from `top`, `bottom`, `top left`, `top right`, `bottom left`, `bottom right`. Defaults unchanged (`top` for usage, `bottom left` for progress).

  **Internal structure (informational):**
  - `lua/flemma/bar.lua` moves to `lua/flemma/ui/bar/layout.lua` and gains an `apply_rendered_highlights` helper.
  - New module `lua/flemma/ui/bar/init.lua` provides a handle-based `Bar.new(opts)` with `set_icon` / `set_segments` / `set_highlight` / `update` / `dismiss` / `is_dismissed` methods, six positions, mutual exclusion, and lifecycle autocmds.
  - `lua/flemma/notifications.lua` is deleted; its driver logic lives in `lua/flemma/usage.lua`.
  - Progress float in `lua/flemma/ui/init.lua` rewires to `Bar`; the inline "Waiting"/"Thinking" virt_text path and the off-screen fallback are preserved unchanged.

- 9e265cf: Added `<Space><Space>` keymap to toggle conceallevel between the configured level and 0 in chat buffers. Configurable via `keymaps.normal.conceal_toggle`; only registered when `editing.conceal` is active. The toggle re-opens the frontmatter fold to prevent it from auto-collapsing during the transition.
- e8be40b: Restructured config schema: moved orphaned top-level keys under their parent groups.

  **Migration:** rename the following keys in your `setup()` call:

  | Old path      | New path                |
  | ------------- | ----------------------- |
  | `defaults`    | `highlights.defaults`   |
  | `role_style`  | `highlights.role_style` |
  | `pricing`     | `ui.pricing`            |
  | `statusline`  | `ui.statusline`         |
  | `text_object` | `keymaps.text_object`   |

- 9eadd16: First `.chat` buffer open and first `:Flemma send` no longer freeze the editor while resolving credentials (e.g. `gcloud auth print-access-token`). Subprocess resolvers now run async; the send pipeline raises a readiness suspense on cache miss, subscribes to the async work, and retries automatically on completion with a "Resolving …" notification.
- ca12afd: Preserve foreign thinking blocks when switching providers mid-conversation. When an assistant message contains thinking from a different provider, the thinking summary is wrapped in `<thinking>` tags and injected as text content, giving the new model context on the previous model's reasoning.
- b41bef0: Added `editing.conceal` with default `"2nv"` — Flemma now hides markdown syntax (bold, italic, link markers, etc.) in chat windows while reading or selecting, and reveals it when you move the cursor onto a line in Insert or Command mode. The value is a compact `{conceallevel}{concealcursor}` string; set it to `false` to opt out and keep whatever conceal settings your colorscheme/config provides. See `docs/conceal.md` for the format and the intentionally-unfixed `line_highlights` + `Conceal` interaction (a Neovim drawline design, documented inline).

  This is the first of a series of "reduce noise by default" changes — chat buffers already carry role markers, tool blocks, thinking blocks, rulers, and usage bars; removing visible markdown markup on top of that makes assistant prose much easier to read. The old behaviour is one line away: `editing = { conceal = false }`.

- fff4af8: Added `:Flemma usage:estimate` — delegates to the active provider's `try_estimate_usage` hook. The Anthropic adapter queries `POST /v1/messages/count_tokens` with the exact body a real send would produce (minus `max_tokens`, `stream`, `temperature`) and reports input tokens, estimated cost, and per-MTok pricing via `flemma.notify.info`.
- 38f2bad: Added support for Kimi K2.6 (`kimi-k2.6`) and promoted it to the default Moonshot model. Pricing per platform.kimi.ai/docs/pricing/chat-k26: $0.95/M input, $0.16/M cache read, $4.00/M output, 256K context. K2 preview/turbo/thinking variants are now flagged with their May 25, 2026 retirement date.

  Also introduced a provider-specific extension point on `flemma.models.ModelInfo`: an optional `meta` table whose shape is documented by the owning adapter. Moonshot uses `meta.thinking_mode = "forced" | "optional"` to drive thinking behaviour directly from the model data instead of hardcoded tables in the adapter.

- 4b1ccd3: Replaced tmux-style statusline and truncate formats with Lua template formats.
- 3325423: Added opt-in lualine segment `#{buffer.tokens.input}` showing projected input tokens for the next request, fetched via the active provider (Anthropic today) and debounced 2.5s after the user pauses editing. The default `statusline.format` now includes the segment with an `↑` marker; users with a custom `statusline.format` are unaffected unless they add the variable.

  Internal: `try_estimate_usage(bufnr, on_result)` is now callback-mandatory — notify/format moved to the `:Flemma usage:estimate` command dispatcher so adapter implementations stay pure-data. New hook `usage:estimated` / `FlemmaUsageEstimated` fires when a buffer's token estimate changes.

- 5b12dc7: Added GPT-5.5 and GPT-5.5 pro model definitions for OpenAI
- de4e185: Added support for Claude Opus 4.7 (`claude-opus-4-7`) with adaptive thinking. Opus 4.7 is adaptive-only (manual `budget_tokens` is rejected), and its default thinking display is `"omitted"` — Flemma now sends `display: "summarized"` explicitly on all adaptive requests so thinking text is returned.

  Added an Anthropic-specific `effort` parameter (`parameters.anthropic.effort = "xhigh"`) as an escape hatch for effort values outside Flemma's canonical enum, mirroring OpenAI's `reasoning` override. This makes Opus 4.7's new `xhigh` level reachable.

- e511779: Show the active tool name in the progress bar during tool call streaming (e.g. `write · 475 characters · 14s`)
- 0dcddd0: `statusline.format` now accepts either a single string or a list of strings. When a list is provided, entries are concatenated with `""` at render time, letting you break the default into readable pieces without manual `table.concat` calls.
- 0dcddd0: Added `FlemmaStatusTextMuted` highlight group — a theme-neutral dim variant of `StatusLine` derived via Flemma's hl expression composer (`StatusLine±fg:#666666`). Use `%#FlemmaStatusTextMuted#…%*` in `statusline.format` to dim fragments while keeping the statusline background continuous.

  When rendered through the bundled lualine component, both escapes are auto-rewritten at render time so they anchor to the active section hl rather than plain `StatusLine`:
  - `%*` → section's default hl (restores `lualine_c_normal` etc. instead of falling back to `StatusLine`)
  - `%#FlemmaStatusTextMuted#` → a memoised render-time group combining the section's bg with the muted fg, so embedded muted text keeps bg continuity across mode tints

  The render-time group is cached on the component and only re-set when the section bg or muted fg actually changes (mode switch or colorscheme), keeping the statusline redraw hot path cheap. Outside lualine, both escapes pass through untouched — vim handles `%*` natively and the static `FlemmaStatusTextMuted` group (anchored to `StatusLine.bg`) is used directly.

  The shipped `statusline.format` default now surfaces session request count + cost and the buffer token estimate alongside the model name, with muted separators between segments. See `lua/flemma/config/schema.lua` for the literal list; users with a custom `statusline.format` are unaffected.

- 8bf8557: Added `thinking.foreign` config option to control whether foreign thinking blocks are included in requests. The `thinking` parameter now accepts an object form `{ level = "high", foreign = "preserve" }` alongside the existing scalar shorthand (coerced automatically).
- df68d3f: Unified tool result status into a parenthesized header suffix. The pending / approved / denied / rejected / aborted lifecycle states and the previously-separate `(error)` marker now all live in the `**Tool Result:**` header via a modeline-parseable suffix — e.g. ``**Tool Result:** `toolu_01` (pending)``.

  The old `flemma:tool status=<status>` fenced-block format has been retired. The fence below a tool_result is now always a plain code block. On the AST, `is_error` is gone; `status = "error"` replaces it, and any non-status tokens in the header suffix (e.g. `(status=pending sandbox=false)`) round-trip through a new `meta` field for future metadata support.

  No migration is provided. In-flight conversations with old `flemma:tool` placeholders must be upgraded manually — the `(error)` suffix continues to parse correctly, so completed conversations with errored tool results are unaffected. The header suffix also survives `conceallevel = 2` (the default since 0.11), so pending tools remain visibly approvable without disabling markdown conceal.

  Also adds `:Flemma tool:approve` and `:Flemma tool:reject [message]` commands mirroring the existing `:Flemma tool:execute` entry point, so the header status can be toggled programmatically or by keymap without hand-editing. `tool:reject` accepts an optional message that is written into the fence body as the rejection reason visible to the model.

  Classified as `minor` rather than `major` because the format change is bounded: completed conversations (the `(error)` case and all plain tool results) round-trip unchanged, and the only affected buffers are ones paused mid-approval — a transient state, not persisted work.

- f1c86cb: Added distinct syntax highlight groups for every concise status suffix on `**Tool Result:**` headers, mirroring the long-standing `(error)` treatment:
  - `(pending)` → `FlemmaToolResultPending` → `DiagnosticInfo`
  - `(approved)` → `FlemmaToolResultApproved` → `DiagnosticOk`
  - `(rejected)` → `FlemmaToolResultRejected` → `DiagnosticWarn`
  - `(denied)` → `FlemmaToolResultDenied` → `DiagnosticError`
  - `(aborted)` → `FlemmaToolResultAborted` → `DiagnosticError`
  - `(error)` → `FlemmaToolResultError` → `DiagnosticError` (unchanged)

  Each is configurable through `highlights.tool_result_<status>` in setup, and each default is set with `default = true` so colourschemes can override without opt-out ceremony. Only the bare-word suffix is decorated — the explicit modeline form `(status=approved sandbox=false)` stays plain, keeping the visual rule "concise = coloured, explicit = metadata."

- 45968a7: Changed the default `turns.padding` from `{ left = 1, right = 0 }` to `{ left = 0, right = 1 }` so the turn indicator hugs the sign column with breathing room on the right.
- 36b50d1: Added `try_estimate_usage` to the Vertex AI and Moonshot adapters, bringing `:Flemma usage:estimate` and the opt-in `#{buffer.tokens.input}` lualine segment to both providers. Vertex queries the `{model}:countTokens` REST endpoint (strips `generationConfig`); Moonshot queries `POST /v1/tokenizers/estimate-token-count` (strips `stream`/`max_tokens`/`temperature`/`thinking`). Both endpoints are free and rate-limited separately from generation.

### Patch Changes

- 37b40ff: Enabled eager input streaming for Anthropic tool calls, eliminating multi-second delays in the progress bar during large tool argument generation
- 1f76b59: Fixed two conceal-related bugs. (1) Opening a `.chat` buffer was mutating the user's **global** `conceallevel` / `concealcursor` because `nvim_set_option_value` with only a `win` key behaves like `:set`, not `:setlocal`; Flemma now passes `scope = "local"` so chat settings stay window-scoped. (2) Splitting or `:tabedit`-ing from a chat window copied chat's `conceallevel` into the new (non-chat) window because Neovim duplicates window-local options on window creation. Flemma now restores the global conceal on the new window when a non-chat buffer lands there with chat's conceal fingerprint still applied.
- 63a877a: Suppress suspense notifications (e.g., "Resolving Anthropic API key...") when the dependency resolves within 600ms
- 92346da: Fixed the first diagnostic line collapsing onto the `Flemma:` title when the request is blocked by multiple diagnostics. The diagnostic renderer now starts with a leading blank so the prefix sits on its own line above the list.
- a4eb39e: Fixed duplicate error notifications when the API returns a single-line JSON error body (e.g. Anthropic 429 rate limit). `_handle_non_sse_line` was buffering the line and emitting `on_error`, after which `finalize_response`'s `_check_buffered_response` re-parsed the same buffered body and emitted the error again. The line is now only buffered when it can't be handled directly, so `_check_buffered_response` only runs on genuinely unhandled bodies (multi-line JSON, non-JSON, etc.).
- 694aa8b: Fixed frontmatter block vanishing at `conceallevel >= 1`. Neovim's bundled `markdown/highlights.scm` sets `conceal_lines = ""` on fenced-code-block delimiters — at `conceallevel >= 1` the fence rows render as zero-height. Because the frontmatter fold placeholder was anchored on the now-concealed opening fence, the whole collapsed fold disappeared with it. Flemma now skips the frontmatter fold when `vim.wo.conceallevel >= 1`: the delimiter lines stay concealed, the body renders inline with its language highlighting, and there is no collapsed placeholder to lose. The behaviour is driven by the live window option, so toggling `editing.conceal` at runtime switches modes without a buffer reload. See `docs/conceal.md` "Folds and `conceal_lines`" for the drawline layering that forces this.
- 375b544: Fixed `<Space>` throwing `E490: No fold found` when pressed on frontmatter while conceal is on. Flemma now shows a short info message naming the active conceallevel instead of an error.
- 98f0924: Fixed a ghost progress-bar icon that could linger in the gutter after a request completed. Bar's `WinClosed` handler released both float handles (`_float_winid` and `_gutter_winid`) whenever either float was closed externally, but did not close the twin float — leaving it orphaned beyond the reach of any subsequent `_render` or `dismiss()` call. The handler now closes the still-open twin before scheduling the re-render, so the progress bar fully clears when the agent finishes.
- 90c4903: Closed a remaining gap in the ghost progress-bar fix: even after the `WinClosed` twin-close patch, an orphan gutter float could survive when the close path didn't fire `WinClosed` (close inside a non-nested autocmd, `:tabclose` cascade silence) or when `pcall(nvim_win_close)` silently failed. `Bar:dismiss` now force-deletes the bar's scratch buffers, which Neovim resolves by closing every window showing them — reaching orphan floats the bar lost track of.
- e613f18: `normalize.resolve_max_tokens` now honours `min_output_tokens` on model info as a lower bound. Values below the model's minimum are raised to the minimum with a warning, and percentage-based `max_tokens` values use the larger of `MIN_MAX_TOKENS` or the model's minimum as their floor. Affects Moonshot Kimi K2.x thinking-capable models where the API rejects `max_tokens` below 16,000.
- 79d4eca: Routed all internal notifications through the new `flemma.notify` module — centralising dispatch, implicit `vim.schedule` wrapping, `once`-dedup, and lazy nvim-notify backend detection. Users with rcarriga/nvim-notify installed automatically get rich notifications (titles, icons, replace-in-place, dedup); users on vanilla `vim.notify` see no behavior change.
- 451f5eb: Fixed plugin installation failure on nixpkgs (and other eager require-checkers) when rcarriga/nvim-notify is not installed. `flemma.integrations.nvim_notify` used to hard-require `notify` at module load; it now pcalls the require so the module loads cleanly in isolation and `flemma.notify` falls back to `vim.notify`. Users with nvim-notify installed see no behavior change.
- bb8af07: Added optional `nvim-treesitter-context` integration that disables the sticky-context window on `.chat` buffers. Wire `require("flemma.integrations.nvim-treesitter-context").on_attach` (or `.wrap(existing)`) into your treesitter-context config. Internal rename: `flemma.integrations.devicons` → `flemma.integrations.nvim-web-devicons` and `flemma.integrations.nvim_notify` → `flemma.integrations.nvim-notify` — user-facing config keys (`integrations.devicons.*`) and internal type identifiers (`flemma.integrations.Devicons`, `flemma.integrations.NvimNotify`) are unchanged.
- 5a42488: Preserve OpenAI assistant message phases when replaying Responses API history.
- aa4a591: Omit OpenAI `reasoning` request fields for models that do not support reasoning effort, while preserving docs-backed effort mappings for pro reasoning models.
- c591f7d: Fixed `thinking = false` on OpenAI reasoning models to send `reasoning.effort = "none"` instead of silently defaulting to the model's default effort level
- 387b2e4: Added OpenAI support for `:Flemma usage:estimate` and the opt-in `#{buffer.tokens.input}` statusline segment via `POST /v1/responses/input_tokens`.
- 0527b76: Fixed preset parameter merge bypassing schema coercion (e.g., `thinking = "low"` staying as a raw string instead of being normalized to `{ level = "low", foreign = "preserve" }`)
- 1547404: Refactor: consolidated try_estimate_usage orchestration into a shared base.send_count_tokens helper. Adapters now declare only endpoint, body transformer, and response parser.
- 22f5297: Fixed inconsistent `FlemmaToolUseTitle` / `FlemmaToolResultTitle` highlighting where only the first `**Tool Use:**` / `**Tool Result:**` header in a role block received the dedicated highlight while subsequent ones were rendered as plain text. Vim's default syntax sync (`maxlines=60`) could leave the outer `FlemmaSystem` / `FlemmaUser` / `FlemmaAssistant` region unmatched after a fenced code block between headers, so the contained `FlemmaToolUse` / `FlemmaToolResult` regions had nowhere to anchor. Added `syntax sync match … grouphere` directives on the three role markers so every header now picks up its title highlight regardless of position. The issue became visually obvious once `editing.conceal = "2nv"` hid the `**` markers, but was latent in all prior versions.
- b03d3ca: Refreshed the default visuals:
  - Tool fold icons now distinguish request from response: `⬡` (hollow hexagon) for tool_use and `⬢` (filled hexagon) for tool_result, replacing the shared `◆` glyph. Both share the `FlemmaToolIcon` highlight group.
  - `@System` and `@You` messages now carry subtle background tints by default (`#101112` / `#202122`), making role transitions legible even when rulers are hidden. `@Assistant` stays on `Normal` so the eye rests on the LLM output.
  - Thinking blocks softened to dark gray on near-black (`bg:#000000 fg:#333333`), replacing the prior teal-tinted palette.

  Override any of these under `highlights.*` and `line_highlights.*` to restore the previous look.

- cdbf9a0: Fixed tool-result previews vanishing at `conceallevel>=1`. Tree-sitter's markdown query sets `conceal_lines = ""` on fenced-code delimiter lines, so anchoring virtual-line extmarks on the opening fence caused them to be hidden along with the delimiter. Now the virt_line anchors on the blank line between the `**Tool Result:**` header and the opening fence when conceal is active, keeping the preview visible under the default `editing.conceal = "2nv"`. The original inside-the-fence anchor is preserved at `conceallevel=0`.
- ee446b4: Fixed tool preview virt_lines showing Normal bg instead of the surrounding role bg when `line_highlights` is enabled. `line_hl_group` on a range extmark does not propagate to virtual lines Neovim inserts inside that range, so the preview row rendered a visible stripe against the `@You` role's tinted background (exposed by the refreshed default palette that gave `@You` a distinct bg). The preview text chunk now combines `FlemmaToolPreview` fg with `FlemmaLineUser` bg, and a padding chunk extends that bg across the text area width to match how `line_hl_group` fills real buffer lines.
- ab29deb: Fixed file references with spaces in filenames (e.g., `image (1).png`) breaking the preprocessor — the read tool now URL-encodes paths before emitting `@./path;type=mime` references
- 0b6bdba: Fixed Vertex adapter reporting a spurious error when Gemini returns an empty response with `finishReason: "STOP"`
- 268ef56: Fixed Vertex adapter using "unknown" for `functionResponse` names when tool IDs originate from another provider (e.g., Anthropic's `toolu_*` format)

## 0.10.0

### Minor Changes

- 72eeb7a: Added binary content support in tool results. The read tool now detects binary files (images, PDFs) and emits file references instead of raw bytes. Providers that support mixed content (Anthropic, OpenAI Responses, Vertex) send images and PDFs natively; providers that don't (OpenAI Chat, Moonshot) fall back to text placeholders with a diagnostic warning.
- 65f80df: Added mcporter tool integration: dynamically discovers MCP servers and registers their tools as Flemma tool definitions. Configure via `tools.mcporter` with include/exclude glob patterns. Disabled by default.
- 5ddd354: Added `mime.detect(filepath)` as the single public entry point for MIME detection — tries extension-based lookup first, falls back to the `file` command. Added `mime.is_binary(mime_type)` for classifying MIME types as binary vs textual. The previous `get_mime_type()` and `get_mime_by_extension()` methods are now internal.
- f921664: Promoted LSP and exploration tools (find, grep, ls) out of experimental. LSP is now configured via `lsp = { enabled = true }` (top-level). The three exploration tools are enabled by default. The `experimental` config section is now empty and strict — any keys passed to it will produce a validation error.
- 5ddd354: Added `@~/path` file reference syntax for home-directory relative paths, alongside the existing `@./` and `@../`. The `~` is expanded at evaluation time, keeping `.chat` files portable across machines.
- ad7227e: Use colon as internal tool name separator with wire encoding to double underscore for LLM APIs
- e3f6e0e: Added shared tool output overflow handling: when bash or MCP tool results exceed 2000 lines or 50KB, the full output is saved to a configurable temp file and the model receives truncated content with instructions to read the full output. The overflow path format is configurable via `tools.truncate.output_path_format`.
- 1e20943: Added `User-Agent: flemma.nvim/X.Y.Z Neovim/A.B.C` header to all API requests, backed by a version module that is automatically kept in sync with releases via CI

### Patch Changes

- e86eafe: Fixed autopilot skipping throttled auto-approved tools when pending (non-auto-approved) tools coexist in the same response
- 2cdde26: Fixed HTTP 417 errors from Vertex AI caused by cURL's default `Expect: 100-continue` header
- 0de4dd0: Status buffer now auto-refreshes when async tool sources finish loading, replacing the "loading" indicator with a "finished" confirmation
- e698820: Fixed tool preview disappearing during execution. The virtual line preview (e.g., `bash: print Hello — $ sleep 5 && echo Hello`) now remains visible while a tool is executing, not just while pending approval.

## 0.9.0

### Minor Changes

- 1d9b496: Auto-generate EmmyLua config types from the schema DSL via `make types`
- 568f684: Added Moonshot AI (Kimi) provider with support for kimi-k2.5 thinking, tool calling, and all Kimi/Moonshot models. Introduced a reusable Chat Completions base class (openai_chat.lua) for OpenAI-compatible APIs.
- f4714f9: Temperature is now optional with no default. Previously Flemma always sent `temperature: 0.7` to provider APIs, which caused reasoning-native models (gpt-5-mini, o-series) to reject requests entirely. Temperature is now omitted unless explicitly set by the user, letting each API use its own default (typically 1.0).

  If you previously relied on the implicit 0.7 default for less random responses, add `temperature = 0.7` to your setup config or chat frontmatter.

  Note: temperature is no longer silently stripped when set alongside reasoning/thinking. If you explicitly set both, the API will reject the request — correct this by removing the temperature setting.

- c5aac07: Split monolithic models.lua into per-provider data modules under lua/flemma/models/, allowing providers to declare their own model data via metadata.models. Added pricing.high_cost_threshold config option (default 30) replacing the hardcoded constant.
- 3aa501b: Removed the signs feature and replaced it with a `turns` config schema (`turns.enabled`, `turns.padding`, `turns.hl`) and a `FlemmaTurn` highlight group linked to `FlemmaRuler`.
- 2bb0d2a: Expose `os.date`, `os.time`, `os.clock`, and `os.difftime` in the template sandbox, enabling date/time formatting in expressions (e.g., `{{ os.date("%B %d, %Y") }}`). Dangerous `os.*` functions (`execute`, `exit`, `getenv`, `remove`, etc.) remain excluded.
- 6278037: Extended the modeline parser with quote-aware tokenization, type coercion for positional arguments, single and double quote support with backslash escaping, comma-separated list values, and empty value handling (`key=` → nil, `key=""` → empty string).
- 0371511: `<Space>` now toggles the entire message fold instead of the fold under the cursor. Nested folds (thinking, tool use/result) are closed along the way so the message reopens cleanly. Frontmatter folds are also toggled when the cursor is outside any message. Use `za` for the previous per-fold toggle behavior.
- d7cea2e: Added turn detection and statuscolumn rendering module for visual turn boundaries in the gutter
- fcf28d7: Template expressions now handle `}}` and `%}` inside Lua string literals, comments, and table constructors without breaking. Previously, `{{ "email={{ customer.email }}" }}` would crash because the parser matched the first `}}` it found regardless of context.
- 0ba2eba: Added `print()` support in template code blocks — `{% print("text") %}` now emits directly into the template output instead of going to stdout. Arguments are concatenated with no separators and no trailing newline, giving full whitespace control to the template author.
- ccd9646: Unified presets: `config.tools.presets` merged into top-level `presets`. Presets can now carry `provider`, `model`, `parameters`, and `auto_approve` fields — enabling composite presets like `$explore` that switch both model and tool approval in one `:Flemma switch` call. Built-in `$default` renamed to `$standard` (approves read, write, edit, find, grep, ls); `$readonly` updated to include find, grep, ls. Read-only tools (find, grep, ls) are now approved via the `$standard` preset instead of the sandbox auto-approval path. Schema validates preset key `$` prefix at finalize via new `MapNode` deferred key validation. `:Flemma status` now shows (R) icon for runtime-sourced tool approvals.

### Patch Changes

- 8b4b516: Send document title metadata on Anthropic PDF blocks so Claude can see the filename
- 5dd4c2d: Fixed Anthropic API rejection when text content appears after tool_use blocks in assistant messages by reordering content blocks to text-before-tool_use
- f848083: Centralized sink buffer name sanitization in the sink module. Callers no longer need to sanitize names themselves — `sink.create()` handles it automatically, keeping alphanumerics, dots, hyphens, underscores, and colons while collapsing consecutive hyphens. Sink buffer names are now more readable (e.g. `flemma://sink/http/https:-api.anthropic.com-v1-messages#1` instead of `flemma://sink/http/https-//api-anthropic-com/v1/messages#1`). Removed unused `contrib/extras/sink_viewer.lua`.
- e031c1f: Fixed crash and stuck spinner when a provider request completes while the command-line window (q:) is open
- b9c9f6e: Standardized vim.notify prefix to "Flemma: " across all notification call sites
- c2bc110: Silenced test suite output: passing specs emit a one-line summary, failing specs show only the failure details
- b8ad1a9: Fixed `:Flemma switch` ignoring `key=` syntax for clearing parameters (e.g., `temperature=` to unset a setup default)
- 4befc56: Unified all monetary formatting into a single `format_money` function with smart precision: integers show no decimals, values >= $1 use 2, values in [0.01, 1) use 3, and sub-cent values use 4 (trailing zeros past the 2nd decimal are stripped)
- 486a03a: Updated model definitions and pricing: added gpt-5.4-mini, gpt-5.4-nano, gpt-5.4-2026-03-05; updated context windows for claude-opus-4-6, claude-sonnet-4-6 (1M), gpt-5.4, gpt-5.4-pro (922K); fixed o4-mini cache pricing; removed retired models (gemini-3-pro-preview, gpt-4-0125-preview, gpt-4-1106-preview, gpt-4-0314)

## 0.8.0

### Minor Changes

- 4ca6f8e: Added `editing.auto_prompt` option (default `true`) that prepends `@You:` to empty `.chat` buffers on open, giving new users a clear starting point.
- d8a1187: Replaced the configuration system with a layered, schema-backed copy-on-write store.

  The new system introduces a schema DSL for declarative config shape definition, a four-layer store (DEFAULTS, SETUP, RUNTIME, FRONTMATTER) with separate scalar (top-down first-set-wins) and list (bottom-up accumulation) resolution, read/write proxy metatables for ergonomic access, and a DISCOVER callback pattern that lets tool, provider, and sandbox modules register their own config schemas at load time without coupling the schema definition to heavy modules.

  All configuration access now goes through a single public facade (`require("flemma.config")`). The legacy flat merge (`vim.tbl_deep_extend` in `config.lua`), the global config cache (`state.get_config` / `state.set_config`), and the per-buffer opt overlay (`buffer/opt.lua`) have all been removed. Frontmatter evaluation writes directly to the FRONTMATTER layer of the store, and `flemma.opt` is now a write proxy into that layer.

  Providers are now request-scoped — constructed inline per `send_to_provider()` call with per-buffer parameters, captured in closures, and GC'd after the request completes. The global mutable provider instance, the parameter override diffing machinery, and `config_manager.lua` have been dissolved into `core.lua` (orchestration) and `provider/normalize.lua` (pure parameter normalization functions).

  The approval system is unified into a single config resolver that reads the resolved `tools.auto_approve` from the layer store, replacing the previous two-resolver pattern (config + frontmatter at separate priorities). Preset `deny` lists have been removed — an auto-approve policy that denies is a contradiction.

  `:Flemma status` now shows right-aligned layer source indicators (D/S/R/F) on provider, model, parameter, and tool lines, and a verbose view with per-layer ops and a schema-walked resolved config tree.

  Test coverage includes 9 new config test suites (store, proxy, schema, definition, alias, list ops, DISCOVER, lens, integration) alongside migration of ~30 existing test files to the new facade.

- 1cda981: Add deferred semantic validation to config schema nodes. Tool names in frontmatter and setup config are now validated against the tool registry at finalize time, with "did you mean?" suggestions for typos.
- fb5f241: Added devicons integration that auto-registers a .chat file icon with nvim-web-devicons (or other compatible devicons plugins). Enabled by default — configure via `integrations.devicons.enabled` and `integrations.devicons.icon`.
- 3fcb594: Fold previews now show tool labels (the LLM's stated intent) prominently, with raw technical detail visually subordinate.

  Tool `format_preview` functions can now return `{ label?, detail? }` instead of a plain string, where `detail` may be a `string[]` (joined with double-space upstream for uniform display). Built-in tools (bash, read, write, edit, grep, find, ls) have been updated to use the structured return. String-returning `format_preview` functions are fully backward-compatible. New highlight groups `FlemmaToolLabel` (italic) and `FlemmaToolDetail` (default: Comment) style the two pieces independently. Label and detail are separated by an em-dash (`—`) in both folds and tool preview virtual lines.

- 2c7661e: JSON frontmatter now supports MongoDB-style operators ($set, $append, $remove, $prepend) for config writes via the `flemma` key
- 4248502: The lualine component now accepts a `format` option directly in the section config, which takes precedence over `statusline.format` in the Flemma config:

  ```lua
  { "flemma", format = "#{provider}:#{model}" }
  ```

- 8d5b6a6: Passively evaluate frontmatter on InsertLeave, TextChanged, and BufEnter so integrations like lualine see up-to-date config values without waiting for a request send. On error, the last successful frontmatter parse is preserved.

  Refactored `config.finalize()` to return validation failures as data instead of accepting a reporter callback, making codeblock parsers pure data functions with no `vim.notify` side effects. Callers now decide when and how to surface diagnostics.

  `:Flemma status` renders frontmatter diagnostics (parse errors, runtime errors, and validation failures) as DiagnosticError lines in the status buffer.

- 948f341: Added `secrets.gcloud.path` config option to override the gcloud binary path, and introduced the generic `flemma.config.ConfigAware<T>` interface with `flemma.secrets.Context` for typed per-resolver config access
- 9da24c7: Show resolved thinking value in Parameters section (e.g., "minimal → low") instead of opaque Model Info line
- a43f5a9: Redesigned `:Flemma status` display with box-drawing tree layout and extmark-based highlighting, replacing the flat text format and vim syntax file.
- d23d58d: Added per-item config layer source indicators to Autopilot and Sandbox status sections; removed redundant section-level source from Tools header; suppressed defaults-only (D) indicators
- 6f486ef: Unified schema engine: schema DSL nodes can now define tool input schemas via `to_json_schema()` serialization, as an alternative to raw JSON Schema tables. Added `s.nullable()` for required-but-nullable fields, chainable `:optional()` and `:nullable()` modifiers, and converted all built-in tools to use the DSL.

### Patch Changes

- 68c476c: Fixed auto_write crashing when an external process modifies the .chat file on disk mid-request, which left autopilot and request state broken
- 60b8997: Unknown commands now suggest the closest match ("Did you mean 'ast:diff'?"). Also fixed a double-colon in sub-command hints when the input has a trailing colon.
- 37bba97: Fixed abort markers being stripped from historical assistant messages, which caused prompt-cache busting when the conversation grew
- 2ba5d67: Fixed approval status marking all approved tools with frontmatter indicator when only some were added by frontmatter
- e8a83b5: Fixed frontmatter marker not showing on pending/denied tools in approval status section
- 1864552: Fixed race condition where autopilot emitted "Cannot send while tool execution is in progress" when an LLM response contained both sync and async tool_use blocks.
- 48241a8: Fixed per-buffer config layer edge cases: frontmatter ops now release memory on buffer delete, provider switch notification detects higher-priority overrides, and secrets invalidation is scoped to user-initiated switches only
- 2884e7a: Fixed diagnostics accumulating across repeated requests (doubling, tripling, etc.) due to mutating the AST snapshot's error list in-place.
- 0c71954: Fixed race condition where autopilot emitted "Tool … is already executing" during heavy tool use with mixed sync/async tools in the same response.
- 2b71602: Fixed gf and LSP goto-definition on {{ include() }} expressions — navigation now uses a path-only include that resolves file paths without compiling target content, fixing failures on files containing literal {{ }} documentation
- 78213f6: Fixed tool preview virt_lines not appearing when autopilot pauses on pending tool approval
- 58f6b63: Fixed blank separator line between @You: and @Assistant: not being foldable while the assistant is streaming a response
- 6cecb3a: Fixed `:Flemma status` showing stale autopilot state on second invocation when the cursor was already in the status split
- 670e671: Fixed truncation splitting multi-byte UTF-8 characters, which produced invalid JSON request bodies rejected by the API with "surrogates not allowed"
- c1ed4d7: Removed vestigial `reset()` from provider lifecycle — providers are request-scoped and single-use, so initialization is inlined into `new()` and the redundant pre-request reset in client.lua is removed
- 6667fb8: Resolver diagnostics: when credential resolution fails, every resolver now reports why it couldn't help, surfaced as indented sub-lines in the failure notification
- 7aa1050: Improved diagnostic error messages: config proxy, eval, and JSON parser errors now use structured error tables instead of plain strings, producing cleaner user-facing output without noisy Lua source locations and redundant context wrappers.
- 7e21ed3: Unified validation failure diagnostic output across JSON and Lua frontmatter paths

## 0.7.0

### Minor Changes

- d36de50: Added `ast:diff` command for side-by-side comparison of raw and rewritten ASTs, with syntax highlighting, folding, and cursor-aware scrolling. LSP hover now uses the same tree dump format for consistent AST inspection.
- ba903a8: Add booting indicator for async tool sources: `#{booting}` lualine variable, `FlemmaBootComplete` autocmd, and ⏳ indicator in `:Flemma status`
- 464a909: Added optional bufferline.nvim integration that shows a busy icon on `.chat` tabs while a request is in-flight. Configure with `get_element_icon = require("flemma.integrations.bufferline").get_element_icon` in your bufferline setup. Custom icons supported via `get_element_icon({ icon = "+" })`.
- 235b8e1: Added centralized cursor engine with focus-stealing prevention. System-initiated cursor moves (tool results, response completion, autopilot) are now deferred until user idle, preventing cursor hijacking during agent loops. User-initiated moves (send, navigation) execute immediately.
- 0c6e6cb: Added experimental in-process LSP server for chat buffers with hover and goto-definition support. Enable with `experimental = { lsp = true }` in setup. Every buffer position returns a hover result: segments (expressions, thinking blocks, tool use/result, text) show structured dumps, role markers show message summaries with segment breakdowns, and frontmatter shows language and code. Goto-definition (`gd`, `<C-]>`, etc.) on `@./file` references and `{{ include() }}` expressions jumps to the referenced file, reusing the navigation module's path resolution.
- 92bd667: Added three exploration tools for LLM-powered codebase navigation: `grep` (content search with rg/grep fallback, --json match counting, per-line truncation), `find` (file discovery with fd/git-ls-files/find fallback, recursive patterns, configurable excludes), and `ls` (directory listing with depth control). All tools use existing truncation, sink, and sandbox infrastructure. Executor cwd resolution generalized from bash-specific to per-tool.
- cf30657: Added file drift detection: warns when `@./file` references change between requests, helping identify cache breaks and potential LLM confusion from stale conversation context
- 393e18d: Added `<Space>` keymap to toggle folds in `.chat` buffers. Configurable via `keymaps.normal.fold_toggle`; automatically skipped when the key conflicts with `mapleader`.
- 749c1c7: Added hooks module for external plugin integration. Flemma now dispatches User autocmds at key lifecycle points: FlemmaRequestSending, FlemmaRequestFinished (with status: completed/cancelled/errored), FlemmaToolExecuting, and FlemmaToolFinished (with status: success/error). Existing autocmds (FlemmaBootComplete, FlemmaSinkCreated, FlemmaSinkDestroyed) migrated to the new hooks infrastructure.
- e6ecdd8: Added `gf` navigation for file references and include expressions in chat buffers. Cursor on `@./file` or `{{ include('path') }}` and press `gf` to open the file or `<C-w>f` for a split. Paths are resolved using the same logic as the expression evaluator, including frontmatter variables and buffer-relative resolution.
- 3c6f1d5: Added LSP go-to-definition navigation between tool_use and tool_result siblings in `.chat` buffers
- b7e5c50: Added `tools.max_concurrent` config option to limit per-buffer tool execution concurrency (default: 2, set 0 for unlimited)
- ba9b05b: Added personality system for dynamic system prompt generation via `{{ include('urn:flemma:personality:<name>') }}`. Includes a `coding-assistant` personality that assembles tool listings, guidelines, environment context, and project-specific files into a complete system prompt. Tool definitions can contribute personality-scoped parts (snippets, guidelines, etc.) via a new `personalities` field.
- 19dc325: Added preprocessor/rewriter pipeline for extensible AST transforms before expression evaluation. File references (@./file) are now handled by a rewriter instead of inline parser logic.
- 80fc278: Added persistent progress indicator showing character count, elapsed time, and phase-specific animation throughout the full request lifecycle including tool use buffering. The indicator appears as a floating window at the bottom of the chat window when the progress line is off-screen, with spinner icon placed in the gutter to match notification bar layout. Configurable via `progress.highlight` and `progress.zindex`.
- 308767b: Preprocessor rewriter modules can now declare their own Vim syntax rules and highlight groups via `get_vim_syntax(config)`, removing the need to modify the main syntax file when adding new rewriters.
- fcbce89: Sandbox variable expansion overhaul and DNS fix:
  - Path variables in `rw_paths` now use `urn:flemma:cwd` and `urn:flemma:buffer:path` instead of `$CWD` and `$FLEMMA_BUFFER_PATH` (breaking change for custom configs)
  - Added `$ENV` and `${ENV:-default}` expansion with bash-style fallback syntax
  - Default `rw_paths` now includes `${TMPDIR:-/tmp}`, `${XDG_CACHE_HOME:-~/.cache}`, and `${XDG_DATA_HOME:-~/.local/share}` for package manager compatibility
  - Removed `--tmpfs /run` from bwrap backend, fixing DNS resolution on NixOS/systemd (nscd socket was hidden)
  - Paths are now prefix-deduplicated (parent subsumes child)
  - `:Flemma status` and `:Flemma sandbox:status` now show resolved rw_paths, network, and privilege policy

- f08cb7a: Added pluggable secrets module for credential resolution. Providers now declare
  what credentials they need (kind + service) and platform-aware resolvers handle
  lookup from environment variables, GNOME Keyring (Linux), macOS Keychain, and
  gcloud CLI. Includes TTL-aware caching with configurable freshness scaling.
  Existing keyring entries stored under the previous scheme are still supported
  via legacy fallback.
- 08ecd55: Added template code blocks (`{% lua code %}`) for conditionals, loops, and logic in @System and @You messages. Added optional whitespace trimming (`{%- -%}`, `{{- -}}`). Added parameterized includes: `include('file.md', { name = "Alice" })`. Included files now support full template syntax at any depth. Binary include mode now uses symbol keys (`[symbols.BINARY]`, `[symbols.MIME]`) instead of reserved string keys, so `binary` and `mime` can be used as template variable names.
- 8032850: Template machinery consolidated under `flemma.templating/` namespace. Environment is now extensible via `templating.modules` config. Populators are functions that build the Lua table available to `{{ }}` and `{% %}` blocks. Ships two built-in populators: `stdlib` (standard library) and `iterators` (provides `values()` and `each()` for concise array iteration).
- 4927995: Increased default request timeout from 120s to 600s for modern thinking LLMs
- bfc8f91: Added tmux-style format strings for the lualine statusline component. The new `statusline.format` config replaces `thinking_format` with a composable syntax supporting variable expansion (`#{model}`, `#{provider}`, `#{thinking}`), ternary conditionals (`#{?cond,true,false}`), string comparisons, and boolean operators. Variables are lazy-evaluated — only referenced variables trigger data lookups.
- 5e14653: Added per-buffer tool execution concurrency limiting to prevent system overload from large batches of heavy tool calls
- b43de9f: Updated default models: OpenAI `gpt-5` → `gpt-5.4`, Vertex AI `gemini-2.5-pro` → `gemini-3.1-pro-preview`

### Patch Changes

- 7a3fc43: Centralized formatting helpers (format_number, format_tokens, format_cost, format_size, format_percent) in flemma.utilities.string. Sub-cent costs now display with 4 decimal places everywhere, not just in the statusline.
- 15d15a3: Comprehensive documentation update: fixed stale config defaults, added missing options (max_concurrent, auto_close, progress, diagnostics, experimental LSP), created docs/extending.md covering hooks/events and credential resolution, and added new feature mentions (gf navigation, tool concurrency, file drift detection, progress bar) to README.
- 9c23aaf: Fixed emission list position overlap where trailing text after file references (e.g., the dot in `@./math.png.`) shared the expression's position range instead of getting its own correct offset
- d7f760b: Exposed executor.count_running() for per-buffer tool concurrency tracking
- a8cbcd1: Fixed binary file includes (e.g., `@./image.png`) crashing with `Vim:E976: Using a Blob as a String`
- 518d0fb: Fixed race conditions where nvim_get_current_buf() could resolve to the wrong buffer during async operations
- f06318d: Fixed cross-buffer personality environment leak where a background buffer's system prompt could pick up the focused buffer's cached date/time during tool-calling loops
- 2c49af3: Fixed role marker colon handler inserting a duplicate blank line when one already exists (e.g. after using `S` to retype a role header)
- 6bbf347: Fixed file-references rewriter incorrectly processing @./file references in Assistant messages
- 18b05ec: Fixed parser treating inline fenced code (e.g., ` ```markdown Hello!``` `) as fence openers, which caused subsequent @Role: markers to be missed
- 6a0e27e: Fixed input token count in notifications showing only non-cached tokens for Anthropic (e.g. 10 instead of ~6,500) and added missing debug logging for cache token flow
- c6ba3b4: Fixed parser incorrectly splitting messages when role markers (`@You:`, `@Assistant:`, etc.) appear inside fenced code blocks
- 3b89ba3: Fixed parser producing per-line text segments for assistant and user messages, fixed text segments missing column positions causing wrong segment lookup, and fixed find_segment_at_position failing on multi-line segments where end_col belongs to a different line
- 0e31ec7: Fixed preprocessor runner producing structurally different ASTs for untouched text segments by adding a pre-scan early return and accumulating non-matching lines into single segments instead of splitting per-line
- 5872ed2: Fixed trailing newlines from inter-message whitespace leaking into API content blocks, causing cache-breaking prefix drift in multi-turn conversations
- 7e47167: Added `format_elapsed()` duration formatting utility to string module
- 589855d: Fixed frontmatter `auto_approve = {}` (and other table assignments) not blocking sandbox auto-approval of bash. Table policies in frontmatter are now authoritative — tools not explicitly listed require approval, preventing lower-priority resolvers from granting additional approvals.
- b70d052: Moved all inline require() calls to the top of each file for explicit dependency visibility. No behavioral changes.
- 0e8ca7e: Fixed include() with absolute paths doubling the directory prefix, and improved error diagnostics for include failures to show the full include chain instead of `table: 0x...`
- d127523: Optimized AST parsing during streaming: the parser now snapshots the document before a request and only re-parses newly appended content during streaming, reducing per-chunk parse cost from O(total_lines) to O(new_content_lines) for long conversations.
- 499d3a9: Fixed progress character counter freezing during tool use for OpenAI and Vertex providers by emitting `on_tool_input` callback for function call argument deltas
- d0a44e4: Refactored provider layer to eliminate ~370 lines of duplicated code across Anthropic, OpenAI, and Vertex providers. Base now owns the SSE parsing preamble, content emission (tool use blocks, thinking blocks, truncation warnings), and automatic sink lifecycle management. New providers need roughly one-third of the previous boilerplate.
- df1ec98: Removed viewport centering (zz) on send that caused flickering with scrolloff=999
- 6c7664c: Renamed `:Flemma diagnostics:open` command to `:Flemma diagnostics:diff` for clarity
- 2f44b20: Fixed `:Flemma status` showing sandbox-auto-approved tools (e.g. bash) as "require approval" even when sandbox was active. The approval section now uses the actual resolver chain, so all approval sources (config, frontmatter, sandbox, community resolvers) are reflected accurately.
- e917ea3: Fixed :Flemma status not reflecting parameter overrides from :Flemma switch commands
- b43377d: Fixed thinking level mapping for OpenAI, Anthropic, and Vertex providers. Flemma's canonical thinking levels (minimal/low/medium/high/max) are now silently mapped to valid provider API values via per-model metadata instead of being passed through raw. This fixes the "Unsupported value: 'minimal'" error when using `thinking = "minimal"` with OpenAI models.

## 0.6.0

### Minor Changes

- 6546355: Aligned all registry modules to a consistent API contract: every registry now exposes register(), unregister(), get(), get_all(), has(), clear(), and count(). Extracted shared name validation into a new flemma.registry utility module. Renamed tools registry define() to register() (define() kept as deprecated alias).
- dea4561: Notification bar background is now a blend of Normal bg (base), StatusLine bg (30%), and DiffChange fg (20%), producing a subtly tinted bar that's easier to read against the editor background
- 568fb63: Compact notification bar format: token arrows now follow numbers (129↑ 117↓), session request count is merged into the Σ label (Σ3), and the bar automatically uses relaxed double-spacing when width allows
- bb15c08: Restore CursorLine visibility on line-highlighted chat buffer lines. Blended overlay highlights preserve role-specific backgrounds while showing the cursor line, with smart toggling via OptionSet and a fg-only thinking fold preview group.
- 9459e97: Add deterministic key-ordered JSON encoder for prompt caching. API request bodies now serialize with sorted keys and provider-specific trailing keys (messages, tools) placed last, maximizing prefix-based cache hits across all providers.
- 9c0f873: Added diagnostics mode for debugging prompt caching issues. When enabled via `diagnostics = { enabled = true }`, Flemma compares consecutive API requests per buffer and warns when the prefix diverges (breaking caching). Includes byte-level analysis, structural change detection, and a side-by-side diff view (`:Flemma diagnostics:open`).
- a6618bd: Notification bar now derives all colors from DiffChange with three foreground tiers (primary, secondary, muted) and WCAG contrast enforcement on semantic cache colors. Added `^` contrast operator to highlight expressions and extracted color utilities into `flemma.utilities.color` for reuse.
- bae5026: Extracted folding logic into dedicated `ui/folding` module with registry-based fold rules, O(1) cached fold map, and configurable `auto_close` per fold type (thinking, tool_use, tool_result, frontmatter)
- c56f356: Added independent folding for Tool Use and Tool Result blocks at fold level 2. Completed and terminal tool blocks auto-fold after execution, reducing visual noise. In-flight tools (pending, approved, executing) remain visible. Fold summaries reuse the same preview format as pending tool extmarks.
- 77cb82b: Added per-segment syntax highlighting to fold text lines. Fold lines now return `{text, hl_group}` tuples so each part (icon, title, tool name, preview, line count) uses its own highlight group. New config keys: `tool_icon`, `tool_name`, `fold_preview`, `fold_meta`. Renamed `tool_use` to `tool_use_title` and `tool_result` to `tool_result_title` for 1:1 correspondence with highlight groups. Added shared `roles.lua` utility for centralised role name mapping.
- 0fc8bea: Merged ruler into role marker lines: `@Role:` now renders as `─ Role ─────...` with the ruler extending to the window edge, replacing the separate virtual line above each message
- 078a3a2: Enriched model metadata matrix with per-model thinking budgets, cache pricing, and cache minimum thresholds. Thinking parameters are now silently clamped to model-specific bounds instead of hitting runtime API errors. Cache percentage indicator is suppressed when input tokens are below the model's minimum cacheable threshold. Session pricing now uses per-model absolute cache costs where available, with provider-level multipliers as fallback.
- b46f3ea: Rewrite notification bar with a priority-based layout engine and gutter icon. The 💬 prefix now renders in the gutter when space allows, freeing 3 columns for content. Renamed all FlemmaNotify* highlight groups to FlemmaNotifications* for consistency.
- 5d646e1: Added configurable `notifications.highlight` and `notifications.border` options, and fixed notification misalignment when async plugins (git-signs, LSP) change gutter width after positioning
- fe71464: Line highlights now use per-message range extmarks instead of per-line extmarks, reducing API calls from ~500 to ~20 per update. New lines created by pressing Return in insert mode are highlighted immediately via Neovim's gravity system instead of waiting for CursorHoldI.
- 652e9f6: Reprioritized notification bar segments: session cost and request input tokens now survive truncation at narrow widths. Replaced word labels with compact Unicode symbols (Σ for session totals, #N for request count, bare percentage for cache).
- 0c6e898: Role markers (`@System:`, `@You:`, `@Assistant:`) now occupy their own line in `.chat` buffers. Old-format files are automatically migrated on load, and a new `:Flemma format` command is available for manual migration. Insert-mode colon auto-newline moves the cursor to a new content line after completing a role marker.
- 29ba841: `:Flemma status` now shows model metadata (context window, pricing, thinking budget range) in the Provider section for known models. Verbose mode includes a full Model Info dump. Syntax highlighting updated with model version suffixes, dollar amounts, and token count suffixes.
- 46e6b25: Move shared utility modules to `flemma.utilities.*` namespace and introduce `flemma.utilities.buffer` for common buffer manipulation patterns

### Patch Changes

- b109b62: Cancel both Space and Enter after role marker auto-newline to prevent unwanted blank lines from muscle memory
- acc51d0: Fixed spurious "A request is already in progress" warning during autopilot tool execution loops with sync tools
- a870175: Fixed CursorLine overlay flashing on every keystroke when blink-cmp completion menu is open
- 5de6e77: Fixed spurious "Cache break detected" diagnostics warning when switching between providers
- b60a533: Fix diagnostics false positive when messages grow between turns. Cache-break warnings now only fire for actual prefix-breaking changes (tools, config, system prompt), not for normal message appends at the document tail.
- 9cc706d: Fixed fold auto-close race condition where thinking blocks and tool blocks would remain unfolded ~10% of the time due to silent foldclose failures being permanently marked as successful. Also fixed folds not being applied when returning to a chat buffer after switching tabs during streaming.
- 5c87b26: Fixed fold_completed_blocks firing redundantly on every cursor movement, spamming the debug log
- 6bf2ed9: Fixed tool fold previews falling back to generic key=value format for tools registered via `config.tools.modules` (e.g. extras) by ensuring lazy modules are loaded before registry lookup
- a57a6dc: Fixed preview truncation (fold text, tool indicators) using byte length instead of display width, which caused incorrect truncation and potential UTF-8 splitting with multibyte content (CJK, accented characters, Unicode symbols)
- e098341: Fixed notification bar icon flickering during scrolling by replacing the 💬 emoji prefix with ℹ (U+2139), which renders reliably across terminal emulators
- 720ddab: Fixed extra space in notification bar caused by stale item width alignment from dismissed notifications
- 8686997: Fixed role_style attributes (e.g., underline) bleeding into ruler characters on role marker lines
- 84442f0: Fixed self-closing thinking tags (`<thinking .../>`) creating unclosed folds that swallowed subsequent buffer content
- 300525a: Fixed missing warning when pressing `<C-]>` while a request is already in progress — the keypress was silently ignored instead of showing the "Use `<C-c>` to cancel" message
- f59d94f: Fixed silent failure when API returns non-SSE error responses (plain JSON, HTML error pages, or plain text). Errors are now properly surfaced via vim.notify instead of being silently swallowed.
- 46da4a0: Fixed thinking blocks not auto-folding after the first response in a session
- 932dc68: Tool block folds now absorb trailing blank lines when the next adjacent tool block is also foldable, producing a cleaner collapsed view without vertical gaps between folded blocks
- 9386d8f: Notification recall now derives segments from session data on demand instead of caching them locally, enabling `:Flemma notification:recall` to work after importing a session via `session:load()`
- ea006dd: Removed `ruler.adopt_line_highlight` config option — rulers now inherit line highlight backgrounds automatically since they share the role marker line
- 6478dc3: Sink buffer writes now go through writequeue for E565 textlock protection. Sink scratch buffers are set to nomodifiable, preventing users from accidentally editing them when viewed via sink_viewer.
- 5caff34: Updated OpenAI model catalog and corrected cache pricing across all models. Added gpt-5.4, gpt-5.4-pro, gpt-5.3-chat-latest, gpt-5.3-codex, gpt-5.3-codex-spark, and gemini-3.1-flash-lite-preview. Fixed cache_read values to match actual per-model pricing tiers instead of assuming a uniform 50% discount.
- 2b0bc93: Invalid role_style values (e.g., "italics") now show a helpful warning with a "Did you mean 'italic'?" suggestion instead of crashing

## 0.5.0

### Minor Changes

- 2350bd7: Added automatic handling of aborted responses: when a user cancels (`<C-c>`) mid-stream after tool_use blocks, orphaned tool calls are now automatically resolved with error results instead of triggering the approval flow. The abort marker (`<!-- flemma:aborted: message -->`) is preserved for the LLM on the last text-only assistant message so it can continue contextually.
- 5c3aee7: Added max_input_tokens and max_output_tokens to all model definitions, enabling future context window awareness and cost prediction features
- 681ebbf: Added `flemma.sink` module — a buffer-backed data accumulator that replaces in-memory string/table accumulators across the codebase. Sinks handle line framing, write batching, and lifecycle management behind an opaque API. Migrated cURL streaming, bash tool output, provider response buffering, thinking accumulation, and tool input accumulation to use sinks.
- 2d24104: Use Anthropic's auto-caching API for the conversation tail breakpoint, replacing manual last-user-message walking with a more robust top-level cache_control field
- 9aff386: Redesigned usage notifications with compact dotted-leader layout, cache hit percentage with conditional color highlighting, and arrow-based token display
- c574d43: Show rate limit details (retry-after, remaining quota headers) in error notifications when API returns HTTP 429, with a fallback "Try again in a moment" hint when headers are unavailable
- ee19164: Auto-approve bash tool when sandbox is enabled and a backend is available. A new resolver at priority 25 approves bash calls when sandboxing is active, so sandboxed sessions run without manual approval prompts by default. Users can opt out via `tools.auto_approve_sandboxed = false` in config, or by excluding bash from auto-approval in frontmatter (`auto_approve:remove("bash")`).
- 8758bdd: Smart max_tokens: default is now "50%" (half the model's max output), percentage strings are resolved automatically, and integers exceeding the model limit are clamped with a warning. `:Flemma status` shows the resolved value alongside the percentage.

### Patch Changes

- 1991273: Fixed auto_write not consistently writing the buffer after tool execution, denied/rejected tool processing, and `:Flemma import`
- 8058909: Fixed bwrap sandbox breaking nix commands on NixOS by using `--symlink` instead of `--ro-bind` for `/run/current-system` and `/run/booted-system`, preserving their symlink nature so nix can detect store paths correctly
- e4afad6: Fixed role marker highlights losing foreground color when the base highlight group only defines background, and fixed spinner background not inheriting line highlight colors
- b767a0d: Fixed pending tool blocks with user-provided content being silently discarded. When a user pastes output into a `flemma:tool status=pending` block and presses `<C-]>`, the content is now accepted as the tool result and sent to the provider instead of being replaced by a synthetic error.
- 80eb9fc: Fixed E565 textlock errors when visual-mode plugins (e.g., targets.vim) hold textlock while streaming responses complete. All async buffer modifications now go through a per-buffer FIFO write queue that retries on textlock.
- 0c333ef: Added FlemmaSinkCreated and FlemmaSinkDestroyed user autocmd events for observing sink lifecycle
- 2d24104: Fixed non-deterministic tool ordering in Vertex provider that was causing implicit cache misses on every request

## 0.4.0

### Minor Changes

- ffe72b3: `tools.auto_approve` now accepts a `string[]` of module paths (and mixed module paths + tool names). Internal approval resolver names use `urn:flemma:approval:*` convention; module-sourced resolvers are addressable by their module path directly.
- fae1e16: Added dynamic module resolution for third-party extensions. Lua module paths (dot-notation strings like "3rd.tools.todos") can now be used in config.provider, config.tools.modules, config.tools.auto_approve, config.sandbox.backend, and flemma.opt.tools to reference third-party modules without explicit require() calls. Modules are validated at setup time and lazily loaded on first use.
- 3cf9fe3: Refactor tool definitions to use ExecutionContext SDK — tools now code against `ctx.path`, `ctx.sandbox`, `ctx.truncate`, and `ctx:get_config()` instead of requiring internal Flemma modules directly
- 75e34c8: Moved calculator and calculator_async tools from built-in definitions to lua/extras (dev-only); production builds no longer ship calculator tools
- 974eac1: Auto-approve policy now expands $-prefixed preset references, allowing `auto_approve = { "$default", "$readonly" }` to union approve/deny lists from the preset registry. Config-level resolvers defer to frontmatter when it sets auto_approve, enabling per-buffer override of global presets.
- ef6a932: Removed all backwards-compatibility layers from the Claudius-to-Flemma migration. This is a breaking change for users who still rely on any of the following:

  **Removed: `require("claudius")` module fallback.** The `lua/claudius/` shim that forwarded to `require("flemma")` has been deleted. Update your config to `require("flemma")`.

  **Removed: legacy `:Flemma*` commands.** The individual commands `:FlemmaSend`, `:FlemmaCancel`, `:FlemmaImport`, `:FlemmaSendAndInsert`, `:FlemmaSwitch`, `:FlemmaNextMessage`, `:FlemmaPrevMessage`, `:FlemmaEnableLogging`, `:FlemmaDisableLogging`, `:FlemmaOpenLog`, and `:FlemmaRecallNotification` have been removed. Use the unified `:Flemma <subcommand>` tree instead (e.g., `:Flemma send`, `:Flemma cancel`, `:Flemma message:next`).

  **Removed: `"claude"` provider alias.** Configs specifying `provider = "claude"` will no longer resolve to `"anthropic"`. Update your configuration to use `"anthropic"` directly.

  **Removed: `reasoning_format` config field.** The deprecated `reasoning_format` type annotation (alias for `thinking_format`) has been removed from `flemma.config.Statusline`.

  **Removed: `resolve_all_awaiting_execution()` internal API.** This backwards-compatibility wrapper in `flemma.tools.context` has been removed. Use `resolve_all_tool_blocks()` and filter for the `"pending"` status group instead.

- 50eea2b: Rich fold text previews for message blocks. Folded `@Assistant` messages now show tool use previews (e.g. `bash: $ free -h | bash: $ cat /proc/meminfo (+1 tool)`), and folded `@You` messages show tool result previews with resolved tool names (e.g. `calculator_async: 4 | calculator_async: 8`). Expression segments are included in fold previews, consecutive text segments are merged, and runs of whitespace are collapsed to keep previews compact.
- 5b637d2: Added an Approval section to `:Flemma status` showing auto-approve, deny, and require-approval classification per tool with preset expansion. Frontmatter overrides are marked with ✲ on individual items across Tools, Approval, Parameters, and Autopilot sections, with a conditional legend at the bottom.
- cd97ff5: Added tool approval presets for zero-config agent loops. Flemma now ships with `$readonly` and `$default` presets. The default `auto_approve` is `{ "$default" }`, which auto-approves `read`, `write`, and `edit` while keeping `bash` gated behind manual approval. Users can define custom presets in `tools.presets` and reference them in `auto_approve`. Frontmatter supports `flemma.opt.tools.auto_approve:remove("$default")` and `:remove("read")` for per-buffer overrides.
- 0617d2c: Changed tool execute function signature from `(input, callback, ctx)` to `(input, ctx, callback?)` — sync tools no longer need a placeholder `_` argument, and callback-last ordering matches Node.js conventions
- 5de4f32: Tools now resolve relative paths against the .chat buffer's directory (`__dirname`) instead of Neovim's working directory, matching the behavior of `@./file` references and `{{ include() }}` expressions. The `tools.bash.cwd` config defaults to `"$FLEMMA_BUFFER_PATH"` (set to `nil` to restore the previous cwd behavior).
- ff794c4: Added tool approval presets configuration field and wired preset registry into plugin initialization with `{ "$default" }` as the default auto_approve policy

### Patch Changes

- 5035b41: Fixed `flemma.opt.tools.auto_approve:append()` failing when auto_approve was not explicitly assigned first in frontmatter
- 4062653: Fixed bwrap sandbox hiding NixOS system packages by re-binding `/run/current-system` read-only after the `/run` tmpfs mount
- 93b79e8: Frontmatter is now evaluated exactly once per dispatch cycle instead of 2N+2 times (where N = number of tool calls), reducing redundant sandbox executions and preventing potential side-effects from repeated evaluation.
- ec0072b: Updated model definitions with latest pricing and availability data from all three providers.

  **Anthropic:** Removed retired Claude Sonnet 3.7 and Claude Haiku 3.5 models (retired Feb 19, 2026). Updated Claude Haiku 3 deprecation comment to reflect April 2026 retirement date.

  **Vertex AI:** Added Gemini 3.1 Pro Preview (`gemini-3.1-pro-preview`). Removed superseded preview-dated aliases `gemini-2.5-flash-preview-09-2025` and `gemini-2.5-flash-lite-preview-09-2025`.

  **OpenAI:** No changes — all existing models and pricing confirmed current against official documentation.

## 0.3.0

### Minor Changes

- e5a9b6f: Added `:Flemma status` command that displays comprehensive runtime status (provider, model, merged parameters, autopilot state, sandbox state, enabled tools) in a read-only scratch buffer. Use `:Flemma status verbose` for full config dump. `:Flemma autopilot:status` and `:Flemma sandbox:status` now open the same status view with cursor positioned at the relevant section.
- 9fc147c: Tool definitions can now provide an optional `format_preview` function for custom preview text in tool status blocks. All built-in tools (calculator, bash, read, edit, write) include tailored previews showing the most relevant input at a glance.
- 6f8b455: Added support for `model = "$preset-name"` in config to use a preset as the startup default, avoiding duplication of provider/model/parameters at the top level
- f20492f: Added virtual line previews inside tool status blocks showing a compact summary of the tool call, so users can see what they are approving or rejecting
- 9bd2785: Unified tool execution into a three-phase advance algorithm with explicit status semantics (`flemma:tool status=pending|approved|rejected|denied`), replacing the old `flemma:pending` marker and separate autopilot/manual flows
- 299702f: Added Claude Sonnet 4.6 as the new default Anthropic model, removed retired chatgpt-4o-latest, added o3-pro snapshot, and updated Gemini 2.0 retirement dates

### Patch Changes

- 6a5cb12: Fixed Sonnet 4.6 to use adaptive thinking instead of deprecated budget_tokens, clamped `max` effort to `high` on non-Opus models, and added budget_tokens < max_tokens guard for budget-based models
- e4933aa: Preview text for tool blocks and folded messages now sizes dynamically to the editor width instead of using a fixed 72-character limit
- 41c130b: Fixed bash tool failing with heredoc commands by replacing `{ cmd; } 2>&1` group wrapping with `exec 2>&1` prefix
- 1ca55b2: Fixed cross-provider parameter merge bug where provider-specific config keys (e.g., `project_id`) were silently dropped when switching providers via presets
- e4ddd0b: Fixed JSON null values decoding as vim.NIL (truthy userdata) instead of Lua nil, causing crashes in tool definitions when LLMs send null for optional parameters like offset, limit, timeout, and delay
- f88449f: Fixed thinking preview counter disappearing when models emit whitespace-only text before thinking blocks (e.g. Opus 4.6 with adaptive thinking)
- 0af66ea: Moved session reset API from `require("flemma.state").reset_session()` to `require("flemma.session").get():reset()`

## 0.2.0

### Minor Changes

- 7cccfc6: Adopted semantic versioning (semver) and changesets for automated version management and changelog generation. The project transitions from the previous CalVer (`vYY.MM-N`) scheme to standard semver, starting at `0.1.0`.
- c22dd05: Added Anthropic stop reason handling (max_tokens warns, refusal/sensitive surface as errors) and adaptive thinking for Opus 4.6+ models (auto-detected, sends effort level instead of deprecated budget_tokens)
- 4471a07: Added autopilot: an autonomous tool execution loop that transforms Flemma into a fully autonomous agent. After each LLM response containing tool calls, autopilot executes approved tools, collects results, and re-sends the conversation automatically – repeating until the model stops calling tools or a tool requires manual approval. Includes per-buffer frontmatter override (`flemma.opt.tools.autopilot`), runtime toggle commands (`:Flemma autopilot:enable/disable/status`), configurable turn limits, conflict detection for user-edited pending blocks, and full cancellation safety via Ctrl-C.
- 05809d5: Added `minimal` and `max` thinking levels, expanding from 3 to 5 gradations (`minimal | low | medium | high | max`). Budget values for `low` (1024 → 2048) and `high` (32768 → 16384) were adjusted to align with upstream defaults and make room for the new levels. Each provider maps the canonical levels to its API: Anthropic maps `minimal` → `low` and passes `max` on Opus 4.6; OpenAI maps `max` → `xhigh` for GPT-5.2+; Vertex maps `minimal` → `MINIMAL` (Flash) or `LOW` (Pro) and clamps `max` to `HIGH`.
- 907b787: Added filesystem sandboxing for tool execution. Shell commands now run inside a read-only rootfs with write access limited to configurable paths (project directory, .chat file directory, /tmp by default). Enabled by default with auto-detection of available backends; silently degrades on platforms without one. Includes Bubblewrap backend (Linux), pluggable backend registry for custom/future backends, per-buffer overrides via frontmatter, runtime toggle via :Flemma sandbox:enable/disable/status, and comprehensive documentation.
- 76c635e: Added Gemini 3 model support: uses `thinkingLevel` enum (LOW/MEDIUM/HIGH) instead of numeric `thinkingBudget` for gemini-3-pro and gemini-3-flash models
- e6b53e2: Added approval resolver registry and per-buffer approval via frontmatter. Tool approval is now driven by a priority-based chain of named resolvers – global config, per-buffer frontmatter (`flemma.opt.tools.auto_approve`), and custom plugin resolvers are all evaluated in order. Consolidated tool documentation into `docs/tools.md`.
- 629dfda: Sandbox enforcement for write and edit tools – both now check `sandbox.is_path_writable()` before modifying files and refuse operations outside `rw_paths`
- dcaa5be: Add unified `thinking` parameter that works across all providers – set `thinking = "high"` once instead of provider-specific `thinking_budget` or `reasoning`. The default is `"high"` so all providers use maximum thinking out of the box. Provider-specific parameters still take priority when set. Also promotes `cache_retention` to a general parameter, consolidates `output_has_thoughts` into the capabilities registry, clamps sub-minimum thinking budgets instead of disabling, and supports `flemma.opt.thinking` in frontmatter for provider-agnostic overrides.
- 93f4b68: Added proactive token refresh and reactive auth-error recovery for Vertex AI provider, eliminating the need to manually run `:Flemma switch` when OAuth2 tokens expire

### Patch Changes

- c22dd05: Fixed OpenAI top-level stream error events being silently discarded; they now properly surface as errors
- a59da49: Fixed tool completion indicators being prematurely dismissed during concurrent execution and autopilot
- 784fe5a: Fixed Vertex AI safety-filtered responses silently appearing as successful completions; SAFETY, RECITATION, and other error finish reasons now properly surface as errors
- 5b6b5af: Fixed Vertex AI thinking signature retention during streaming; empty or non-string `thoughtSignature` chunks no longer overwrite a valid cached signature
- 784fe5a: Fixed Vertex AI tool response format to use `output` key instead of `result`, matching the Google SDK convention
- 7bf8d64: Fixed Vertex AI tool declarations rejecting nullable types by switching to `parametersJsonSchema` on v1beta1 API
- 9995605: Flash a brief "● Pending" indicator on tool result headers awaiting user approval

<!-- Entries above this line are managed by @changesets/cli -->

---

## Historical Releases (CalVer)

_The releases below used the `vYY.MM-N` CalVer scheme and were manually curated.
Starting with 0.1.0, versioning follows semver and changelogs are generated by
[changesets](https://github.com/changesets/changesets)._

## v25.10-1 – 2025-10-14

### Added

- Introduce a single `:Flemma` command tree with sub-commands for sending, cancelling, navigation, logging, notification recall, and importing Claude Workbench snippets.
- Add provider presets so aliases declared via `setup({ presets = { … } })` surface in `:Flemma switch` and completion menus before built-in providers.
- Implement a reusable modeline/parser utility so positional arguments and `key=value` overrides behave consistently across commands and configuration files.
- Add multi-language frontmatter parsers (Lua and JSON) with automatic detection and richer error messaging.
- Expand the templating sandbox with an `include(path)` helper plus access to `vim.fn` and `vim.fs`, enabling modular prompt composition with circular-include detection.
- Add highlight hooks for `{{ expressions }}` and `@./file` references, configurable `thinking_tag` and `thinking_block` extmark highlights, and table-based highlight attribute support.
- Introduce a floating notification system with recall support (`:Flemma notification:recall`) and stacked window positioning to avoid overlap.
- Add a lualine component at `require("lualine.components.flemma")` that reports the active model and OpenAI reasoning effort while refreshing automatically when providers change.
- Bundle tooling helpers in the Nix shell, including `flemma-fmt`, `flemma-amp`, and the new `flemma-codex` OpenAI CLI wrapper.
- Add MIME type override support for attachments via `@./file;type=mime/type` to satisfy provider-specific requirements.

### Changed

- Rename the project and runtime modules from `claudius.*` to `flemma.*`, refresh syntax files, and update all highlight group prefixes.
- Raise the minimum supported Neovim version to 0.11+ to leverage the new Tree-sitter folding APIs and `vim.fs` helpers.
- Update provider metadata with the latest model lists and pricing (Claude Sonnet/Opus 4.x, GPT‑5 family, Gemini 2.5 series) while surfacing capability flags such as reasoning, thinking budgets, and thought outputs.
- Rework usage reporting so request notifications include the provider/model, aggregate reasoning/thinking tokens (`⊂ thoughts`), and automatically cost thought tokens.
- Improve buffer UX by temporarily locking buffers during requests, excluding spinners from spell checking, skipping `<thinking>` sections in message text objects, and guarding fold updates.
- Overhaul the README with end-to-end setup guidance, provider-specific walkthroughs, and detailed templating/file attachment docs aligned with the refactored plugin.
- Move Claude Workbench import support into the Claude provider so other providers opt in via `try_import_from_buffer`.
- Warn on invalid provider or model configuration and fall back to safe defaults instead of silently reverting to Claude.
- Update Vertex AI binary attachments to include the filename in the `displayName` field for inline data.

### Deprecated

- Deprecate legacy `:Claudius*` and `:Flemma*` shim commands in favor of the consolidated `:Flemma` command tree.

### Removed

- Remove the previously deprecated parser, logging, notify, and provider shims that were kept for compatibility.

### Breaking

- Change `frontmatter.parse` to return `(language, code, content)` and require passing the language into `frontmatter.execute`, reflecting the new multi-language parser registry.
- Change `buffers.parse_buffer` to return `(messages, frontmatter_code, context)` after introducing immutable context objects for template evaluation.
- Refactor provider integrations to use the `Prompt` class, shared response accumulator, and provider-specific `try_import_from_buffer`; custom providers must call `base.reset(self)` and adopt the new API.
- Restructure public modules by moving UI helpers to `flemma.ui`, buffer helpers to `flemma.core.buffers`, and exporting `flemma.config` directly as a table, so external integrations must update their `require` paths.
- Switch HTTP fixture registration to domain-based patterns via the extracted client module, requiring custom fixtures to target hostnames instead of models.

### Fixed

- Surface diagnostics when attachments reference missing or unsupported files, strip trailing punctuation from MIME overrides, and fall back to extension-based detection when the `file` binary is unavailable.
- Correct Vertex AI defaults by defaulting `location` to `global`, fixing the global endpoint hostname, and clearing cached credentials on provider switches.
- Resolve Vertex AI authentication edge cases when service-account JSON comes from environment variables or Secret Service.
- Ensure OpenAI requests honor `reasoning` settings by sending `reasoning_effort` and `max_completion_tokens`.
- Prevent spinner cleanup from leaving blank lines, schedule spinner updates to avoid E565 errors, and guard fold operations to eliminate E490 fold-close failures.
- Fix `:Flemma switch` completion to list user presets before built-in providers for predictable alias selection.
- Prevent frontmatter from executing during UI refresh events by parsing messages without evaluation.
- Restore `{{ }}` template expressions in chat messages, clone contexts immutably, and report accurate filenames in template errors.
- Handle cancellation of completed requests gracefully by ignoring invalid channel errors and issuing friendly warnings.
- Harden Claude Workbench import by logging failed snippets and prepared JSON to `flemma_import_debug.log`.

## v25.06-1 – 2025-06-02

### Added

- **`@file` References:**
  - Implemented robust support for `@./path/to/file` references in user messages across all providers (Claude, OpenAI, Vertex AI).
  - Files are read, their MIME types detected (requires the `file` command-line utility), and content is base64 encoded for inclusion in API requests.
  - **Claude Provider:** Supports images (JPEG, PNG, GIF, WebP) and PDFs as `image` and `document` source types respectively. Text files (`text/*`) are embedded as text blocks.
  - **OpenAI Provider:** Supports images (JPEG, PNG, WebP, GIF) as `image_url` parts. Text files (`text/*`) are embedded as text parts. PDF files are also included as base64 encoded data (note: direct PDF support in chat completion API might vary by model).
  - **Vertex AI Provider:** Supports generic binary files as `inlineData` parts. Text files (`text/*`) are now sent as distinct text parts rather than `inlineData`.
  - File paths can be URL-encoded (e.g., spaces as `%20`) and will be automatically decoded.
  - Trailing punctuation in file paths (e.g., from ending a sentence with `@./file.txt.`) is ignored for robustness.
  - Notifications are shown if a file is not found, not readable, or its MIME type is unsupported by the provider for direct inclusion; in such cases, the raw `@./path/to/file` reference is sent as text.
  - Extracted MIME type detection to a new utility module `lua/claudius/mime.lua`.
- **Vertex AI "Thinking":**
  - Added support for Vertex AI's "thinking" feature (experimental model capability).
  - New `thinking_budget` parameter under `parameters.vertex` in `setup()` allows specifying a token budget for model thinking.
    - `nil` or `0` disables thinking by not sending the `thinkingConfig` to the API.
    - Values `>= 1` enable thinking with the specified budget (integer part taken).
  - When enabled, "thinking" from the model are streamed and displayed in the chat buffer, wrapped in `<thinking>...</thinking>` tags.
  - These `<thinking>` blocks are automatically stripped from assistant messages when they are part of the history sent in subsequent requests.
  - Thinking token usage is tracked and included in request/session cost calculations and notifications.
- **Lualine Integration:**
  - Added a Lualine component to display the currently active Claudius AI model.
  - The component is available as `require('lualine.components.claudius')` or simply `"claudius"`.
  - The model display is active only for `*.chat` buffers.
  - The display automatically refreshes when switching models/providers via `:ClaudiusSwitch`.
- **Configurable Timeouts:**
  - Made cURL `connect_timeout` (default: 10s) and `timeout` (response timeout, default: 120s) configurable.
  - These can be set globally in `setup()` under `parameters` or overridden per call with `:ClaudiusSwitch ... connect_timeout=X timeout=Y`.
- **New Models Supported:**
  - **Vertex AI:**
    - Added support for `gemini-2.5-pro-preview-05-06` (now the default Vertex AI model).
    - Added support for `gemini-2.5-flash-preview-04-17`.
  - Pricing information for these new models has been added.
- **Logging:**
  - Added `M.warn()` function to the logging module.

### Changed

- **README Overhaul:**
  - Significantly restructured and updated the README for clarity and completeness.
  - Added a new screenshot.
  - Reorganized sections: Installation, Requirements, Configuration, Usage.
  - Clarified API key storage with a `<details>` block for Linux `secret-tool`.
  - Moved plugin defaults into a `<details>` block.
  - Reordered and improved Usage sub-sections (Starting a New Chat, Commands and Keybindings, Switching Providers, Lualine Integration, Templating, File References, Importing).
  - Updated Lualine example to show icon usage: `{{ "claudius", icon = "🧠" }}`.
  - Documented new configuration options (`timeout`, `connect_timeout`, `thinking_budget`) and updated `:ClaudiusSwitch` examples.
- **Default Model:**
  - **Vertex AI:** Default model changed to `gemini-2.5-pro-preview-05-06`.
- **Visuals & Styling:**
  - Default ruler character (`ruler.char`) changed from `─` to `━` (Box Drawings Heavy Horizontal).
  - Default user sign character (`signs.user.char`) changed from `nil` (which defaulted to `▌`) to `▏` (Box Drawings Light Vertical).
  - Token usage and cost display in notifications is now better aligned for readability.
  - "Thoughts" token count in usage notifications is prefixed with the subset symbol `⊂` (e.g., "Output: X tokens (⊂ Y thoughts)").
- **Token Usage Display:**
  - Output token count in usage notifications now correctly includes any "thoughts" tokens.
  - Cost calculation for output tokens now correctly includes the cost of "thoughts" tokens.

### Fixed

- **Error Handling:**
  - Prevented a new `@You:` prompt from being added if an API error occurred during a request, even if the cURL command itself exited successfully.
  - Improved handling of cURL errors:
    - Spinner (`Thinking...` message) is now reliably cleaned up on cURL errors.
    - User is notified of cURL errors with more specific messages for common issues:
      - Code 6 (`CURLE_COULDNT_RESOLVE_HOST`): "cURL could not resolve host..."
      - Code 7 (`CURLE_COULDNT_CONNECT`): "cURL could not connect to host..."
      - Code 28 (Timeout): Message now includes the configured timeout value.
    - New `@You:` prompt is not added if the cURL request itself failed.
  - Updated error message for when the `file` command-line utility (for `@file` MIME type detection) is not found.
- **Internal:**
  - Corrected debug log messages in the `:ClaudiusSwitch` function.
  - Standardized API key parameter access within provider modules.
  - Unified OpenAI `data: [DONE]` message handling.
  - Switched from `vim.fn.base64encode` to `vim.base64.encode`.
  - Quoted filenames in various log messages for clarity.

## v25.04-1 – 2025-04-16

This release marks a major transition for Claudius, evolving from a Claude-specific plugin to a multi-provider AI chat interface within Neovim.

### Breaking Changes 💥

This version introduces significant internal refactoring and configuration changes. Please review the following and update your configuration if necessary:

1.  **Configuration Option Renames:**
    - The `prefix_style` option within `setup({})` has been renamed to `role_style`.
      - **Migration:** Rename `prefix_style` to `role_style` in your `require("claudius").setup({...})` call.
    - The `ruler.style` option within `setup({})` has been renamed to `ruler.hl`.
      - **Migration:** Rename `ruler.style` to `ruler.hl` in your `setup({})` call.

2.  **Highlight Group Renames (Affects Manual Linking Only):**
    - Internal syntax highlight groups used by `syntax/chat.vim` have been renamed from `Chat*` to `Claudius*` (e.g., `ChatSystem` ⇒ `ClaudiusSystem`, `ChatSystemPrefix` ⇒ `ClaudiusRoleSystem`).
    - **Migration:** This **only** affects users who were manually linking these highlight groups in their Neovim configuration (e.g., using `vim.cmd("highlight link ChatSystem MyCustomGroup")`). If you were doing this, update the source group name (e.g., `vim.cmd("highlight link ClaudiusSystem MyCustomGroup")`).
    - **Users configuring highlights _only_ via the `highlights` table in `setup()` are _not_ affected by this change.**

3.  **Configuration Structure (`model`, `provider`, `parameters`):**
    - A new top-level `provider` option specifies the AI provider (`"claude"`, `"openai"`, `"vertex"`). It defaults to `"claude"` for backward compatibility.
    - The `model` option now defaults based on the selected `provider` if set to `nil`. If you specify a `model`, ensure it's valid for the selected provider.
    - Provider-specific parameters (currently only for Vertex AI) are now nested (e.g., `parameters = { vertex = { project_id = "..." } }`).
    - **Migration:**
      - If you want to continue using Claude (the previous default), no action is strictly needed, but explicitly setting `provider = "claude"` is recommended for clarity.
      - If you had a specific `model` configured, ensure it's compatible with the default `claude` provider or explicitly set the correct `provider`.
      - If switching to Vertex AI, configure necessary parameters under `parameters.vertex = { ... }`.

4.  **Internal Function Relocation (Advanced Users Only):**
    - The Lua functions `get_fold_level` and `get_fold_text` were moved from the main `claudius` module to `claudius.buffers`.
    - **Migration:** If you were calling these functions directly in your Neovim config (e.g., `require("claudius").get_fold_level(...)`), update the call to use `require("claudius.buffers")` instead. Most users will not be affected.

### Added

- **Multi-Provider Support:** Claudius now supports multiple AI providers:
  - **Anthropic Claude:** Original provider.
  - **OpenAI:** Added support for various GPT models (e.g., `gpt-4o`, `gpt-3.5-turbo`).
  - **Google Vertex AI:** Added support for Gemini models (e.g., `gemini-2.5-pro`, `gemini-1.5-pro`).
- **Provider Switching (`:ClaudiusSwitch`):**
  - New command `:ClaudiusSwitch` allows switching the active AI provider and model on the fly.
  - Supports interactive selection via `vim.ui.select` when called with no arguments.
  - Allows specifying provider, model, and provider-specific parameters (e.g., `project_id` for Vertex) via arguments.
  - Includes command-line completion for providers and models.
- **Provider Configuration:**
  - New top-level `provider` option in `setup()` to set the default provider (`claude`, `openai`, `vertex`). Defaults to `claude`.
  - New `parameters.vertex` section in `setup()` for Vertex AI specific settings (`project_id`, `location`).
  - Configuration defaults are now centralized and provider-aware (e.g., default `model` depends on the selected `provider`).
- **Authentication:**
  - Generalized API key handling across providers.
  - Added support for retrieving OpenAI API keys via `OPENAI_API_KEY` environment variable or Linux `secret-tool` (`service openai key api`).
  - Added support for Vertex AI authentication:
    - Via `VERTEX_AI_ACCESS_TOKEN` environment variable.
    - Via service account JSON stored in `VERTEX_SERVICE_ACCOUNT` environment variable.
    - Via service account JSON stored using Linux `secret-tool` (`service vertex key api project_id <your_project_id>`). Requires `gcloud` CLI for token generation.
  - Improved authentication error messages using new modal alerts (`claudius.notify.alert`).
- **Highlighting & Styling:**
  - Highlight groups (`highlights.*`, `ruler.hl`) now accept hex color codes (e.g., `"#80a0ff"`) in addition to highlight group names.
  - Sign configuration (`signs.*.hl`) also accepts hex codes or specific highlight group names.
- **Notifications:**
  - Added `claudius.notify.alert()` function for displaying modal error/information windows with Markdown support.
  - Usage notifications now display the model name and provider.
  - Added syntax highlighting for model names in usage notifications (`syntax/claudius_notify.vim`).
- **Pricing Data:** Added pricing information for numerous OpenAI and Vertex AI models in `lua/claudius/pricing.lua`.
- **Logging:** Introduced a dedicated logging module (`lua/claudius/logging.lua`) with improved `inspect` formatting and configuration options.
- **Developer Environment:**
  - Added Nix configuration (`python-packages.nix`, updated `shell.nix`) for Python dependencies required for Vertex AI development (via Aider).
  - Added Aider configuration file (`.aider.conf.yml`).
  - Added `.env.example` and `.envrc` for easier setup.

### Changed

- **Core Architecture:** Major internal refactoring to introduce a provider abstraction layer (`lua/claudius/provider/`). API interaction logic is now handled by specific provider modules (`claude.lua`, `openai.lua`, `vertex.lua`) inheriting from a base class (`base.lua`).
- **Configuration:**
  - Centralized default configuration values in `lua/claudius/config.lua`.
  - Renamed `prefix_style` configuration option to `role_style` (See Breaking Changes).
  - Renamed `ruler.style` configuration option to `ruler.hl` (See Breaking Changes).
  - Clarified that setting `model`, `max_tokens`, or `temperature` to `nil` in `setup()` uses the provider's default value.
- **README:** Significantly updated to reflect multi-provider support, new configuration options, authentication methods, the `:ClaudiusSwitch` command, and developer setup.
- **Highlight Groups:** Renamed internal syntax highlight groups from `Chat*` to `Claudius*` (See Breaking Changes).
- **UI Updates:** Rulers and signs are now updated on `CursorHold` and `CursorHoldI` events, debouncing updates and improving performance, especially in large chat files.
- **Folding Logic:** Moved folding functions (`get_fold_level`, `get_fold_text`) from `init.lua` to `buffers.lua` (See Breaking Changes).
- **Command Descriptions:** Updated descriptions for `ClaudiusSend`, `ClaudiusCancel` to reflect multi-provider support.
- **Internal Naming:** Renamed internal variables like `prefix` to `role_type` for clarity.
- **Dependencies:** Updated Nix flake inputs (`flake.lock`).
- **Developer Scripts:** Updated `claudius-dev` (Aider wrapper) and `claudius-fmt` scripts in `shell.nix`.

### Fixed

- **UI Performance:** Debounced ruler and sign updates should reduce potential flickering and improve performance when editing chat files.
  - **Note:** Users may still experience syntax highlighting flicker, particularly when a `.chat` buffer is open in multiple windows scrolled to different positions. This is related to an upstream Neovim issue ([neovim/neovim#32660](https://github.com/neovim/neovim/issues/32660)) affecting Treesitter's handling of injections in recent nightly builds (as of 2025-04-16). A temporary workaround is to force synchronous parsing by setting `vim.g._ts_force_sync_parsing = true`. While the debouncing in Claudius might mitigate some visual artifacts, the root cause lies within Neovim core.
- **Error Handling:** More specific error reporting for authentication failures using modal alerts. Vertex AI provider includes handling for specific non-SSE error formats.
- **Cancellation:** Cancellation logic is now delegated to the provider implementation for potentially cleaner termination.
