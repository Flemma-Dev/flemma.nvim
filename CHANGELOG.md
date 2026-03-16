# Changelog

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
