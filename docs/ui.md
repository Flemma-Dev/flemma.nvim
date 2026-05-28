# UI Customisation

Flemma adapts to your colour scheme with theme-aware highlights, line backgrounds, rulers, turn indicators, and folding. Every visual element is configurable.

> [!TIP]
> Switching colorschemes mid-session (`:colorscheme gruvbox`, etc.) automatically refreshes all Flemma highlight groups — no buffer switch or restart required.

> For the full configuration block including all UI-related keys, see [docs/configuration.md](configuration.md).

## Highlights and styles

Configuration keys map to dedicated highlight groups:

| Key                               | Applies to                                                                |
| --------------------------------- | ------------------------------------------------------------------------- |
| `highlights.system`               | System messages (`FlemmaSystem`)                                          |
| `highlights.user`                 | User messages (`FlemmaUser`)                                              |
| `highlights.assistant`            | Assistant messages (`FlemmaAssistant`)                                    |
| `highlights.lua_expression`       | `{{ expression }}` fragments (in `@You` and `@System` messages)           |
| `highlights.lua_code_block`       | `{% code %}` block content (in `@You` and `@System` messages)             |
| `highlights.lua_delimiter`        | `{{ }}` and `{% %}` delimiters including trim markers                     |
| `highlights.user_file_reference`  | `@./path` fragments                                                       |
| `highlights.thinking_tag`         | `<thinking>` / `</thinking>` tags                                         |
| `highlights.thinking_block`       | Content inside thinking blocks                                            |
| `highlights.tool_icon`            | `⬡` / `⬢` icons in tool fold text (`FlemmaToolIcon`)                      |
| `highlights.tool_name`            | Tool name in tool fold text (`FlemmaToolName`)                            |
| `highlights.tool_use_title`       | `**Tool Use:**` title line (`FlemmaToolUseTitle`)                         |
| `highlights.tool_result_title`    | `**Tool Result:**` title line (`FlemmaToolResultTitle`)                   |
| `highlights.tool_result_error`    | `(error)` suffix on tool result headers (`FlemmaToolResultError`)         |
| `highlights.tool_result_pending`  | `(pending)` suffix on tool result headers (`FlemmaToolResultPending`)     |
| `highlights.tool_result_approved` | `(approved)` suffix on tool result headers (`FlemmaToolResultApproved`)   |
| `highlights.tool_result_rejected` | `(rejected)` suffix on tool result headers (`FlemmaToolResultRejected`)   |
| `highlights.tool_result_denied`   | `(denied)` suffix on tool result headers (`FlemmaToolResultDenied`)       |
| `highlights.tool_result_aborted`  | `(aborted)` suffix on tool result headers (`FlemmaToolResultAborted`)     |
| `highlights.tool_preview`         | Tool preview virtual lines in pending placeholders (`FlemmaToolPreview`)  |
| `highlights.tool_label`           | Tool intent label in fold previews, italic by default (`FlemmaToolLabel`) |
| `highlights.tool_detail`          | Raw technical detail in structured tool previews (`FlemmaToolDetail`)     |
| `highlights.fold_preview`         | Content preview text in fold lines (`FlemmaFoldPreview`)                  |
| `highlights.fold_meta`            | Line count and padding in fold lines (`FlemmaFoldMeta`)                   |
| `highlights.fence_label`          | Language label on fenced code block overlays (`FlemmaFenceLabel`)         |
| `highlights.fence_bar`            | Delimiter bar on fenced code block overlays (`FlemmaFenceBar`)            |
| `highlights.approval_line`        | Full-line background for tool approval prompts (`FlemmaApprovalLine`)     |
| `highlights.approval_indicator`   | Status indicator on approval prompts (`FlemmaApprovalIndicator`)          |
| `highlights.approval_label`       | Tool name label on approval prompts (`FlemmaApprovalLabel`)               |
| `highlights.approval_key`         | Keybinding hints on approval prompts (`FlemmaApprovalKey`)                |
| `highlights.approval_action`      | Action text on approval prompts (`FlemmaApprovalAction`)                  |
| `highlights.busy`                 | Busy indicator icon in integrations like bufferline (`FlemmaBusy`)        |
| `highlights.progress_accent`      | Bold accent for tool name in the progress bar (`FlemmaProgressBarAccent`) |
| `highlights.role_name`            | GUI attributes for role name text, e.g., bold (`FlemmaRole*Name`)         |

Each value is a highlight builder from `require("flemma.hl")`. Simple cases use `h.link("Group")` for a direct link or `h.attrs({ bold = true })` for literal attributes. More complex cases chain operations like `:blend()`, `:omit()`, and `:pick()` to derive colours from existing groups.

### Job result highlights

`**Job Result:**` headers use their own syntax groups, each linked to the corresponding tool result group by default:

| Group                     | Links to                   |
| ------------------------- | -------------------------- |
| `FlemmaJobResultTitle`    | `FlemmaToolResultTitle`    |
| `FlemmaJobResultError`    | `FlemmaToolResultError`    |
| `FlemmaJobResultPending`  | `FlemmaToolResultPending`  |
| `FlemmaJobResultApproved` | `FlemmaToolResultApproved` |
| `FlemmaJobResultRejected` | `FlemmaToolResultRejected` |
| `FlemmaJobResultDenied`   | `FlemmaToolResultDenied`   |
| `FlemmaJobResultAborted`  | `FlemmaToolResultAborted`  |

Override any group to style job results independently from tool results.

> [!NOTE]
> Fold text uses `FlemmaJobResultTitle` for the title, but indicators currently use the `FlemmaTool*` groups directly for both tool and job results.

## Theme-aware values

Most theme-aware highlights use `:tint()` or `:mute()` — theme-aware blends that automatically flip direction based on `vim.o.background`:

- **`:tint(attr, hex)`** — offset away from the theme's background. Adds in dark mode (toward white), subtracts in light mode (toward black). Use for backgrounds that need to stand out from the base.
- **`:mute(attr, hex)`** — offset toward the theme's background. Subtracts in dark mode (toward black), adds in light mode (toward white). Use for foregrounds that need to be more subdued.

```lua
local h = require("flemma.hl")

-- Mute Comment's fg (darker in dark mode, lighter in light mode)
ruler = { hl = h.from("Comment"):mute("fg", "#303030") }

-- Tint Normal's bg (lighter in dark mode, darker in light mode)
line_highlights = { user = h.from("Normal"):tint("bg", "#202122") }
```

For cases requiring truly different ops per theme (not just flipped blend direction), `h.themed()` is available:

```lua
highlights = { example = h.themed({
  dark = h.link("Special"),
  light = h.from("Comment"):pick("fg"),
}) }
```

### Highlight builder operations

Colours are derived from existing highlight groups using chainable operations. Operations can be combined freely — each returns a new builder, so chains never mutate the original.

**Constructors** — starting points for a highlight chain:

| Constructor                             | What it does                                                                 |
| --------------------------------------- | ---------------------------------------------------------------------------- |
| `h.link("Group")`                       | Link to an existing group (no copy, follows changes)                         |
| `h.from("Group")`                       | Resolve a group's concrete attributes as a starting point                    |
| `h.attrs({ ... })`                      | Literal attributes (`{ bold = true }`, `{ fg = "#ff0000" }`)                 |
| `h.hex("#aabbcc")`                      | Literal colour, defaults to `fg`; pass `"bg"` as second arg for background   |
| `h.themed({ dark = ..., light = ... })` | Branch on `vim.o.background` (see [Theme-aware values](#theme-aware-values)) |
| `h.coalesce(a, b, c)`                   | Try each operation in order, use the first that resolves                     |

**Chain operations** — transform the result of the constructor or a previous chain step:

**`:tint(attr, hex)` / `:mute(attr, hex)`** — theme-aware blends described in [Theme-aware values](#theme-aware-values) above.

**`:blend(attr, offset)`** — add or subtract a hex value with an explicit direction. `+` brightens, `-` darkens. Each RGB channel is clamped to 0-255. Prefer `:tint()` / `:mute()` when the only difference between dark and light mode is the blend direction:

```lua
h.from("Normal"):blend("bg", "+#101010")
h.from("Normal"):blend("bg", "+#101010"):blend("fg", "-#202020")
```

**`:omit(attr, ...)`** — strip attributes from the result. Valid targets are colour attributes (`fg`, `bg`, `sp`) and style attributes (`bold`, `italic`, `underline`, `undercurl`, `strikethrough`, `reverse`, `standout`, etc.):

```lua
-- Keep fg and styles from Folded, but drop its bg
h.from("Folded"):omit("bg")

-- Drop both bg and italic
h.from("Folded"):omit("bg", "italic")
```

**`:pick(attr, ...)`** — the inverse of `:omit()` — keep only the named attributes, discarding everything else:

```lua
-- Extract just the fg colour from Comment
h.from("Comment"):pick("fg")
```

**`:style({ ... })`** — merge in style attributes without changing colours:

```lua
h.from("Comment"):style({ italic = true, bold = true })
```

**Coalesce** — `h.coalesce()` is particularly useful for fallback chains:

```lua
-- Try FlemmaLineUser first; if it has no bg, fall back to Normal
h.coalesce(
  h.from("FlemmaLineUser"):tint("bg", "#101112"),
  h.from("Normal"):tint("bg", "#101112")
)
```

When an operation resolves to nothing (e.g., a group doesn't exist, or `:pick("sp")` on a group with no `sp`), it returns `nil` and the coalesce moves to the next candidate. Missing colours fall back to your `Normal` group, or to black/white based on `vim.o.background`.

## Line highlights

Full-line background colours distinguish message roles. Applied via line-level extmarks on every line of each message block. Disable with `line_highlights.enabled = false` (default: `true`):

```lua
local h = require("flemma.hl")

line_highlights = {
  enabled = true,
  frontmatter = h.from("Normal"):tint("bg", "#201020"),
  system = h.from("Normal"):tint("bg", "#201000"),
  user = h.link("Normal"),
  assistant = h.from("Normal"):tint("bg", "#102020"),
}
```

Role markers (`@You:`, `@System:`, `@Assistant:`) must appear on their own line -- content starts on the next line. The `highlights.role_name` option (default: `h.attrs({ bold = true })`) applies styling to the role name text only (not the ruler).

## Rulers

Rulers are drawn directly on each role marker line (`@System:`, `@You:`, `@Assistant:`) using overlay extmarks. The ruler character replaces the `@` symbol and extends across the remaining window width, producing a visual separator that doesn't consume extra vertical space. Rulers resize automatically when the window is resized.

```lua
local h = require("flemma.hl")

ruler = {
  enabled = true,       -- default: true
  char = "─",           -- drawn over the role marker and repeated to fill the line
  hl = h.from("Comment"):mute("fg", "#303030"),
}
```

With rulers enabled, a role marker line like `@You:` renders as `─ You ────────...` spanning the full window width. The first message also gets a ruler when frontmatter is present.

## Turn indicators

Turn indicators use the statuscolumn to visually group contiguous request/response cycles — an `@You` message through its terminal `@Assistant` response, including any intermediate tool use. Box drawing characters run continuously down the left edge, covering wrapped lines and virtual lines.

```lua
turns = {
  enabled = true,
  padding = { left = 0, right = 1 },   -- also accepts a number (left only) or tuple {L, R}
  hl = "FlemmaTurn",                   -- links to FlemmaRuler by default
}
```

Three visual states indicate turn progress:

- **Complete** (`╭│╰`) — the assistant responded with no pending tool calls.
- **Incomplete** (`╭┊└`) — mid-tool-use; tool results are pending before the turn can finish.
- **Streaming** (`╭┊└` moving) — the assistant is actively generating a response.

When `padding.right > 0`, the top arc (`╭`) connects to the ruler for a seamless visual join.

## Spinner behaviour

While a request is in flight, Flemma writes an `@Assistant:` marker on its own line and renders "Thinking…" as end-of-line virtual text with an animated braille spinner. The animation uses phase-specific frame sequences so the visual rhythm reflects what is happening.

The spinner transitions between phases automatically and is removed once streaming starts.

When the model enters a thinking/reasoning phase, the spinner animation is replaced with a live character count – e.g., `Thinking… (3.2k characters)` – so you can gauge progress at a glance.

### Booting indicator

When async tool sources (registered via `tools.modules` or `tools.register()` with a resolve function) are still loading, Flemma shows a booting state. The `booting` statusline variable is `true` during this phase and becomes `false` once all sources resolve. A `FlemmaBootComplete` User autocmd fires when booting finishes. If you send a request while booting, the buffer shows "Waiting for tool definitions to load…" and auto-sends once everything resolves.

### Tool execution indicators

During tool execution, an animated braille spinner appears next to the `**Tool Result:**` block using the tool phase frames (a falling sand animation at 200ms intervals). When execution completes, the indicator changes to `✓ Complete` or `✗ Failed`. Indicators reposition automatically if the buffer is modified during execution and clear on the next buffer edit.

Eight highlight groups control indicator colours — four for the inline `⬢` icon and four for the EOL status text:

| Group                     | Default link            | When it's used                           |
| ------------------------- | ----------------------- | ---------------------------------------- |
| `FlemmaToolIconPending`   | `FlemmaToolResultTitle` | Inline `⬢` on pending tools              |
| `FlemmaToolIconExecuting` | `FlemmaToolResultTitle` | _(not shown — no prefix when executing)_ |
| `FlemmaToolIconSuccess`   | `FlemmaToolResultTitle` | Inline `⬢` + fold icon on success        |
| `FlemmaToolIconError`     | `DiagnosticError`       | Inline `⬢` + fold icon on error          |
| `FlemmaToolPending`       | `DiagnosticHint`        | EOL `⏸ Pending` text                    |
| `FlemmaToolExecuting`     | `DiagnosticInfo`        | EOL spinner + `Executing…` text          |
| `FlemmaToolSuccess`       | `DiagnosticOk`          | EOL `✔ Complete` text                   |
| `FlemmaToolError`         | `DiagnosticError`       | EOL `⚠ Failed` text                     |

By default, icon colours match the `Tool Result:` header while status text uses semantic Diagnostic colours. Override any group to customise:

```lua
-- Make icons match status colours instead of the header
vim.api.nvim_set_hl(0, "FlemmaToolIconSuccess", { link = "DiagnosticOk" })
vim.api.nvim_set_hl(0, "FlemmaToolIconError",   { link = "DiagnosticError" })
```

### Tool previews

When tool calls are pending approval, Flemma renders a virtual line inside each empty tool_result placeholder fence showing a compact summary of what the tool will do. This lets you review and approve tools without scrolling back to the `**Tool Use:**` block.

Previews dynamically size to the editor's text area width (window width minus sign, number, and fold columns) and truncate with `…` when the content exceeds available space. Built-in tools return structured previews with a **detail** (the raw command or path) and a **label** (the LLM's stated intent), separated by an em-dash and rendered detail-first: `bash: $ make test — running tests`. When width is limited, detail truncates first to preserve the label. The italic-label/dim-detail split is only visible in folded message previews, where each chunk gets its own highlight; the virt-line preview shown over pending placeholders uses a single combined `FlemmaToolPreview` highlight. Custom tools can provide their own previews via `format_preview` on the tool definition. Tools without a custom formatter get a generic key-value summary.

Preview lines use the `FlemmaToolPreview` highlight group (default: linked to `Comment`). See [docs/tools.md](tools.md#tool-previews) for the full reference on built-in formatters, the generic fallback, and writing custom preview functions.

## Folding

Flemma uses a two-level fold hierarchy:

| Fold level | What folds                   | Why                                                 |
| ---------- | ---------------------------- | --------------------------------------------------- |
| Level 1    | Each message                 | Collapse long exchanges without losing context.     |
| Level 2    | Thinking blocks, frontmatter | Keep reasoning traces and templates out of the way. |

The initial fold level is controlled by `editing.fold.level` (default: `1`, which collapses thinking blocks and frontmatter but keeps messages open). Set to `0` to collapse everything, or `99` to open everything.

When `editing.fold.gap` is `true`, folded messages leave one trailing blank line visible between them for visual separation. This only applies to message-level folds — tool block folds always collapse fully. Disabled by default.

### Folding a turn

A **turn** is one round-trip in the conversation: an `@You` message and every `@Assistant` reply and tool exchange that answers it, up to the next `@You`. Two keybindings collapse turns to their endpoints so you can scan a long conversation as a clean question/answer dialogue:

| Key  | Action                                                                    | Config                      |
| ---- | ------------------------------------------------------------------------- | --------------------------- |
| `zy` | Fold every message in the turn under the cursor except the first and last | `keymaps.normal.fold_turn`  |
| `zY` | Apply the same fold to every turn in the buffer                           | `keymaps.normal.fold_turns` |

The first and last messages stay open so the question and final answer remain visible — intermediate assistant responses, tool calls, and tool results collapse. A turn with only a question and a single response folds nothing (there's nothing intermediate to hide).

### Fold text

Collapsed folds show a preview of their content with per-segment syntax highlighting. Neovim's `foldtext` returns `{text, hl_group}` tuples so each part of the fold line uses its own highlight group. The format varies by content type:

- **Messages:** `─ Role preview... (N lines)` when rulers are enabled (default), or `@Role: preview... (N lines)` otherwise – role name uses `FlemmaRole{Role}Name`, preview uses `FlemmaFoldPreview`, line count uses `FlemmaFoldMeta`, ruler char uses `FlemmaRuler`.
- **Tool Use:** `⬡ Tool Use: name: detail — label (N lines)` – icon (hollow hexagon) uses `FlemmaToolIcon`, title uses `FlemmaToolUseTitle`, name uses `FlemmaToolName`, detail uses `FlemmaToolDetail`, label uses `FlemmaToolLabel` (italic), meta uses `FlemmaFoldMeta`. When the tool's `format_preview` returns a structured `{ label, detail }`, detail shows the raw technical summary and label shows the LLM's stated intent. When only detail is available, it falls back to the previous format.
- **Tool Result:** `⬢ Tool Result: name: detail — label (N lines)` – same structure as tool use but with a filled hexagon icon and `FlemmaToolResultTitle`. Errors show `(error)` with `FlemmaToolResultError`.
- **Thinking blocks:** `<thinking preview...> (N lines)` – shows `<thinking redacted>` for redacted blocks, or `<thinking provider>` for blocks with a provider signature. Uses `FlemmaThinkingTag` for delimiters and `FlemmaThinkingFoldPreview` for content (fg-only, so the background comes from the line highlight extmark and correctly blends with CursorLine).
- **Frontmatter:** ` ```language preview... ``` (N lines) ` – uses `FlemmaFoldMeta` for fences and `FlemmaFoldPreview` for content.

## Fence overlays

When `experimental.patch_markdown_conceal` is enabled (the default), fenced code block delimiters are replaced with styled overlay extmarks instead of being hidden via treesitter `conceal_lines`. This eliminates significant per-keystroke overhead on large buffers while keeping the visual appearance clean.

Two highlight groups control the overlay appearance:

| Group              | Default                     | Applies to                                          |
| ------------------ | --------------------------- | --------------------------------------------------- |
| `FlemmaFenceLabel` | theme-aware `Comment`       | Language tag on the opening delimiter (e.g., `lua`) |
| `FlemmaFenceBar`   | links to `FlemmaFenceLabel` | Delimiter bar character                             |

When the cursor line overlaps with a fence overlay, the highlights are automatically contrast-adjusted against `CursorLine` to ensure readability. This uses pre-computed highlight variants that blend the fence colours with the `CursorLine` background.

Fence overlays are only shown when `conceallevel >= 2`. Toggling conceal off (`[oe` or `yoe`) reveals the raw ` ``` ` delimiters. See [docs/conceal.md](conceal.md) for the full interaction between conceallevel and fence rendering.

## Usage bar

Completed requests show a single-line usage bar anchored to one of the chat window's edges. The bar displays model, provider, token counts, cost, and cache statistics – all rendered using priority-based truncation so content degrades gracefully in narrow terminals. Higher-priority items (model name, cost) survive; lower-priority items (individual token breakdowns) are dropped first.

```lua
ui = {
  usage = {
    enabled = true,                        -- set to false to suppress the usage bar
    timeout = 10000,                       -- milliseconds before auto-dismiss (0 = persistent)
    position = "top",                      -- one of: top, bottom, top left, top right,
                                           --          bottom left, bottom right
    highlight = "@text.note,PmenuSel",     -- highlight group(s) for bar colours; first with both fg+bg wins
  },
}
```

The `highlight` option accepts a comma-separated list of highlight group names. Flemma tries each in order and uses the first one that provides both `fg` and `bg` attributes. This lets you specify preferred groups with fallbacks for colorschemes that may not define them all.

The usage bar derives all colours from the resolved highlight group using three foreground tiers against a shared background:

| Tier      | Group                     | Used by                                  |
| --------- | ------------------------- | ---------------------------------------- |
| Primary   | `FlemmaUsageBar`          | Model name, cost                         |
| Secondary | `FlemmaUsageBarSecondary` | Token counts, cache label, request count |
| Muted     | `FlemmaUsageBarMuted`     | Provider, separators, session label      |

Cache hit percentage uses semantic colours through `FlemmaUsageBarCacheGood` (links to `DiagnosticOk`) and `FlemmaUsageBarCacheBad` (links to `DiagnosticWarn`) with automatic WCAG contrast enforcement against the bar background.

Each `.chat` buffer owns at most one active usage bar — a new request dismisses the previous bar before rendering the next. Bars re-render automatically on window resize to reflow content for the new width. Recall the most recent usage bar with `:Flemma usage:recall`.

Before sending, preview the cost of the next request with `:Flemma usage:estimate`. The command delegates to the active provider — Anthropic (`POST /v1/messages/count_tokens`), OpenAI (`POST /v1/responses/input_tokens`), Google Vertex AI (`{model}:countTokens`), and Moonshot (`POST /v1/tokenizers/estimate-token-count`) implement it today. Each sends the exact body a real request would produce, with provider-specific counting-only fields removed, and reports input tokens, estimated cost, and the model's per-MTok rates as a single `notify.info` line. Output cost is intentionally not projected: we have no way to know how long the model will talk before it starts.

For OpenAI, neither the public token-counting/API docs nor live curl probes of successful responses exposed billing, quota, or rate-limit metadata for the token-count endpoint. Flemma therefore treats estimates conservatively as real API requests that may count against account limits. The default statusline includes these debounced estimates; custom statusline formats only get them if they reference `buffer.tokens.input`. Estimates are deduped and suppressed while a chat request is already in flight.

## Extmark priority

Flemma uses a priority hierarchy to layer visual elements correctly when they overlap. Higher-priority extmarks take precedence:

| Priority | Element         | Notes                                         |
| -------- | --------------- | --------------------------------------------- |
| 50       | Line highlights | Base backgrounds for messages and frontmatter |
| 100      | Thinking blocks | Overrides message line highlights             |
| 125      | CursorLine      | Blended overlay so CursorLine shows through   |
| 200      | Thinking tags   | `<thinking>` / `</thinking>` styling          |
| 250      | Tool indicators | Execution spinners and status                 |
| 300      | Spinner         | Highest priority; suppresses spell checking   |

This hierarchy is defined in `lua/flemma/ui/init.lua` and is not user-configurable, but understanding it explains why certain elements visually override others. Tool preview virtual lines use `virt_lines` extmarks (not line-level highlights), so they don't participate in this priority hierarchy.

## Progress bar

While a request is streaming, Flemma shows a persistent progress indicator as a floating bar anchored to one of the chat window's edges. The bar displays the current phase (thinking, streaming text, receiving tool input) and re-renders automatically on window resize.

```lua
ui = {
  progress = {
    position = "bottom left",  -- one of: top, bottom, top left, top right,
                               --          bottom left, bottom right
    highlight = "StatusLine",  -- highlight group(s); first with both fg+bg is used
  },
}
```

## Jobs bar

When background jobs are running, Flemma shows a floating bar anchored to one of the chat window's edges (default: bottom right). The bar displays the active job count with an animated spinner and disappears when all jobs complete.

```lua
ui = {
  jobs = {
    position = "bottom right",  -- one of: top, bottom, top left, top right,
                                --          bottom left, bottom right
  },
}
```

When autopilot schedules a debounced auto-continue after a background job completes, the bar shows a countdown animation alongside the job count. The countdown reflects the `tools.autopilot.resume_delay` timer. Press <kbd>Ctrl-C</kbd> during the countdown to cancel the auto-continue — the countdown disappears from the bar but the job count remains while jobs are still running.

## AST inspection

### Hover

When `lsp.enabled` is set (the default whenever `vim.lsp` is available), hovering over any element in a `.chat` buffer shows a compact AST node dump in a fenced `flemma-ast` code block. The dump shows the node's kind, position, and key fields at depth 1 — container nodes (messages, documents) show a child summary instead of recursing.

### Go-to-definition

Press `gd` (or use your LSP go-to-definition keymap) on:

- A `tool_result` carrying a `job=` modeline → jumps to the matching `**Job Result:**` block.
- A `**Job Result:**` header → jumps back to the originating `tool_result` placeholder.
- An `include("...")` expression → opens the included file.
- A `@./path` file reference → opens the referenced file.

### AST diff

`:Flemma ast:diff` opens a side-by-side diff comparing the raw AST (before preprocessor rewriters) with the rewritten AST (after rewriters). Both buffers use the `flemma-ast` filetype with syntax highlighting and fold support. The diff view scrolls to the node under the cursor in the source buffer.

Use this to debug rewriter transformations — for example, to see how `@./file` references get rewritten to `{{ include() }}` expressions, or to verify that a custom rewriter is producing the expected AST changes. Fold regions let you collapse nodes to focus on the parts you care about.

## Plugin integrations

Flemma ships optional integrations for lualine (statusline component) and bufferline (busy tab indicator). See [docs/integrations.md](integrations.md) for setup instructions and configuration.
