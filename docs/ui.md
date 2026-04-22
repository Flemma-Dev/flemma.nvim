# UI Customisation

Flemma adapts to your colour scheme with theme-aware highlights, line backgrounds, rulers, turn indicators, and folding. Every visual element is configurable.

> For the full configuration block including all UI-related keys, see [docs/configuration.md](configuration.md).

## Highlights and styles

Configuration keys map to dedicated highlight groups:

| Key                              | Applies to                                                               |
| -------------------------------- | ------------------------------------------------------------------------ |
| `highlights.system`              | System messages (`FlemmaSystem`)                                         |
| `highlights.user`                | User messages (`FlemmaUser`)                                             |
| `highlights.assistant`           | Assistant messages (`FlemmaAssistant`)                                   |
| `highlights.lua_expression`      | `{{ expression }}` fragments (in `@You` and `@System` messages)          |
| `highlights.lua_code_block`      | `{% code %}` block content (in `@You` and `@System` messages)            |
| `highlights.lua_delimiter`       | `{{ }}` and `{% %}` delimiters including trim markers                    |
| `highlights.user_file_reference` | `@./path` fragments                                                      |
| `highlights.thinking_tag`        | `<thinking>` / `</thinking>` tags                                        |
| `highlights.thinking_block`      | Content inside thinking blocks                                           |
| `highlights.tool_icon`           | `⬡` / `⬢` icons in tool fold text (`FlemmaToolIcon`)                     |
| `highlights.tool_name`           | Tool name in tool fold text (`FlemmaToolName`)                           |
| `highlights.tool_use_title`      | `**Tool Use:**` title line (`FlemmaToolUseTitle`)                        |
| `highlights.tool_result_title`   | `**Tool Result:**` title line (`FlemmaToolResultTitle`)                  |
| `highlights.tool_result_error`   | `(error)` marker in tool results                                         |
| `highlights.tool_preview`        | Tool preview virtual lines in pending placeholders (`FlemmaToolPreview`) |
| `highlights.tool_detail`         | Raw technical detail in structured tool previews (`FlemmaToolDetail`)    |
| `highlights.fold_preview`        | Content preview text in fold lines (`FlemmaFoldPreview`)                 |
| `highlights.fold_meta`           | Line count and padding in fold lines (`FlemmaFoldMeta`)                  |
| `highlights.busy`                | Busy indicator icon in integrations like bufferline (`FlemmaBusy`)       |

Each value accepts a highlight name, a hex colour string, or a table of highlight attributes (`{ fg = "#ffcc00", bold = true }`).

## Theme-aware values

Any highlight value can be theme-aware using `{ dark = ..., light = ... }`. Flemma detects `vim.o.background` and picks the matching branch:

```lua
ruler = { hl = { dark = "Comment-fg:#303030", light = "Comment+fg:#303030" } }
```

### Highlight expressions

Derive colours from existing highlight groups with blend operations. The syntax is:

```
"HighlightGroup±attr:#hexvalue"
```

Where `+` adds (brightens) and `-` subtracts (darkens) the hex value from the group's attribute. Valid attributes are `fg`, `bg`, and `sp`. Each RGB channel is clamped to 0–255 after the operation.

```lua
-- Lighten Normal's bg by #101010
line_highlights = { user = { dark = "Normal+bg:#101010" } }

-- Darken with -
ruler = { hl = { light = "Normal-fg:#303030" } }

-- Multiple operations on the same group
"Normal+bg:#101010-fg:#202020"
```

### Contrast enforcement

The `^` operator ensures a minimum WCAG 2.1 contrast ratio between a colour attribute and a background context:

```
"HighlightGroup^attr:ratio"
```

Where `ratio` is a decimal contrast target (e.g., `4.5` for WCAG AA). The operator auto-detects direction: against a dark background it lightens toward white, against a light background it darkens toward black.

Composes with blend operations – blends are applied first, then contrast is enforced:

```lua
-- Dim DiffChange fg, then ensure result meets 4.5:1 against the bar bg
"DiffChange-fg:#222222^fg:4.5"
```

> **Scope:** The `^` operator requires a background context provided by the caller. Currently only the usage bar highlight setup provides this context. Using `^` in user-facing config values (e.g., `ruler.hl`) has no effect – the operator is silently ignored when no background context is available.

**Fallback chains** try groups in order, separated by commas. Only the last group in the chain uses the configured `defaults` when the attribute is missing:

```lua
-- Try FooBar first; if it lacks `bg`, fall back to Normal
"FooBar+bg:#201020,Normal+bg:#101010"
```

The `defaults` table provides the ultimate fallback values:

```lua
defaults = {
  dark = { bg = "#000000", fg = "#ffffff" },
  light = { bg = "#ffffff", fg = "#000000" },
}
```

## Line highlights

Full-line background colours distinguish message roles. Applied via line-level extmarks on every line of each message block. Disable with `line_highlights.enabled = false` (default: `true`):

```lua
line_highlights = {
  enabled = true,
  frontmatter = { dark = "Normal+bg:#201020", light = "Normal-bg:#201020" },
  system = { dark = "Normal+bg:#201000", light = "Normal-bg:#201000" },
  user = { dark = "Normal", light = "Normal" },
  assistant = { dark = "Normal+bg:#102020", light = "Normal-bg:#102020" },
}
```

Role markers (`@You:`, `@System:`, `@Assistant:`) must appear on their own line – content starts on the next line. The `role_style` option (comma-separated GUI attributes such as `"bold,underline"`, default `"bold"`) applies styling to the role name text only (not the ruler), and Flemma validates the attributes on startup, warning on invalid values with typo suggestions.

## Rulers

Rulers are drawn directly on each role marker line (`@System:`, `@You:`, `@Assistant:`) using overlay extmarks. The ruler character replaces the `@` symbol and extends across the remaining window width, producing a visual separator that doesn't consume extra vertical space. Rulers resize automatically when the window is resized.

```lua
ruler = {
  enabled = true,       -- default: true
  char = "─",           -- drawn over the role marker and repeated to fill the line
  hl = { dark = "Comment-fg:#303030", light = "Comment+fg:#303030" },
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

When async tool sources (registered via `tools.modules` or `tools.register()` with a resolve function) are still loading, Flemma shows a booting state. The `#{booting}` statusline variable (default: `⏳`) is non-empty during this phase and clears once all sources resolve. A `FlemmaBootComplete` User autocmd fires when booting finishes. If you send a request while booting, the buffer shows "Waiting for tool definitions to load…" and auto-sends once everything resolves.

### Tool execution indicators

During tool execution, an animated braille spinner appears next to the `**Tool Result:**` block using the tool phase frames (a falling sand animation at 200ms intervals). When execution completes, the indicator changes to `✓ Complete` or `✗ Failed`. Indicators reposition automatically if the buffer is modified during execution and clear on the next buffer edit.

### Tool previews

When tool calls are pending approval, Flemma renders a virtual line inside each empty tool_result placeholder fence showing a compact summary of what the tool will do. This lets you review and approve tools without scrolling back to the `**Tool Use:**` block.

Previews dynamically size to the editor's text area width (window width minus sign, number, and fold columns) and truncate with `…` when the content exceeds available space. Built-in tools return structured previews with a **label** (the LLM's stated intent, shown italic) and **detail** (the raw command or path, shown dimmer), separated by an em-dash: `bash: running tests — $ make test`. When width is limited, detail truncates first to preserve the label. Custom tools can provide their own via `format_preview` on the tool definition. Tools without a custom formatter get a generic key-value summary.

Preview lines use the `FlemmaToolPreview` highlight group (default: linked to `Comment`). See [docs/tools.md](tools.md#tool-previews) for the full reference on built-in formatters, the generic fallback, and writing custom preview functions.

## Folding

Flemma uses a two-level fold hierarchy:

| Fold level | What folds                   | Why                                                 |
| ---------- | ---------------------------- | --------------------------------------------------- |
| Level 1    | Each message                 | Collapse long exchanges without losing context.     |
| Level 2    | Thinking blocks, frontmatter | Keep reasoning traces and templates out of the way. |

The initial fold level is controlled by `editing.foldlevel` (default: `1`, which collapses thinking blocks and frontmatter but keeps messages open). Set to `0` to collapse everything, or `99` to open everything.

### Fold text

Collapsed folds show a preview of their content with per-segment syntax highlighting. Neovim's `foldtext` returns `{text, hl_group}` tuples so each part of the fold line uses its own highlight group. The format varies by content type:

- **Messages:** `─ Role preview... (N lines)` when rulers are enabled (default), or `@Role: preview... (N lines)` otherwise – role name uses `FlemmaRole{Role}Name`, preview uses `FlemmaFoldPreview`, line count uses `FlemmaFoldMeta`, ruler char uses `FlemmaRuler`.
- **Tool Use:** `⬡ Tool Use: name: label — detail (N lines)` – icon (hollow hexagon) uses `FlemmaToolIcon`, title uses `FlemmaToolUseTitle`, name uses `FlemmaToolName`, label uses `FlemmaToolLabel` (italic), detail uses `FlemmaToolDetail`, meta uses `FlemmaFoldMeta`. When the tool's `format_preview` returns a structured `{ label, detail }`, the label shows the LLM's stated intent and detail shows the raw technical summary. When only detail is available, it falls back to the previous format.
- **Tool Result:** `⬢ Tool Result: name: label — detail (N lines)` – same structure as tool use but with a filled hexagon icon and `FlemmaToolResultTitle`. Errors show `(error)` with `FlemmaToolResultError`.
- **Thinking blocks:** `<thinking preview...> (N lines)` – shows `<thinking redacted>` for redacted blocks, or `<thinking provider>` for blocks with a provider signature. Uses `FlemmaThinkingTag` for delimiters and `FlemmaThinkingFoldPreview` for content (fg-only, so the background comes from the line highlight extmark and correctly blends with CursorLine).
- **Frontmatter:** ` ```language preview... ``` (N lines) ` – uses `FlemmaFoldMeta` for fences and `FlemmaFoldPreview` for content.

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

Before sending, preview the cost of the next request with `:Flemma usage:estimate`. The command delegates to the active provider — Anthropic (`POST /v1/messages/count_tokens`), Google Vertex AI (`{model}:countTokens`), and Moonshot (`POST /v1/tokenizers/estimate-token-count`) implement it today. Each sends the exact body a real request would produce and reports input tokens, estimated cost, and the model's per-MTok rates as a single `notify.info` line. Output cost is intentionally not projected: we have no way to know how long the model will talk before it starts.

All three provider endpoints are free and apply a separate rate limit from the generation endpoints, so estimating as often as you like does not eat into your Messages quota.

See `lua/flemma/usage.lua` for the driver and `lua/flemma/ui/bar/` for the shared Bar rendering class.

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

## AST inspection

### Hover

When `experimental.lsp` is enabled, hovering over any element in a `.chat` buffer shows a compact AST node dump in a fenced `flemma-ast` code block. The dump shows the node's kind, position, and key fields at depth 1 — container nodes (messages, documents) show a child summary instead of recursing.

### AST diff

`:Flemma ast:diff` opens a side-by-side diff comparing the raw AST (before preprocessor rewriters) with the rewritten AST (after rewriters). Both buffers use the `flemma-ast` filetype with syntax highlighting and fold support. The diff view scrolls to the node under the cursor in the source buffer.

Use this to debug rewriter transformations — for example, to see how `@./file` references get rewritten to `{{ include() }}` expressions, or to verify that a custom rewriter is producing the expected AST changes. Fold regions let you collapse nodes to focus on the parts you care about.

## Plugin integrations

Flemma ships optional integrations for lualine (statusline component) and bufferline (busy tab indicator). See [docs/integrations.md](integrations.md) for setup instructions and configuration.
