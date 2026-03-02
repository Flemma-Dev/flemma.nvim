# UI Customisation

Flemma adapts to your colour scheme with theme-aware highlights, line backgrounds, rulers, sign column indicators, and folding. Every visual element is configurable.

> For the full configuration block including all UI-related keys, see [docs/configuration.md](configuration.md).

## Highlights and styles

Configuration keys map to dedicated highlight groups:

| Key                              | Applies to                                                               |
| -------------------------------- | ------------------------------------------------------------------------ |
| `highlights.system`              | System messages (`FlemmaSystem`)                                         |
| `highlights.user`                | User messages (`FlemmaUser`)                                             |
| `highlights.assistant`           | Assistant messages (`FlemmaAssistant`)                                   |
| `highlights.user_lua_expression` | `{{ expression }}` fragments                                             |
| `highlights.user_file_reference` | `@./path` fragments                                                      |
| `highlights.thinking_tag`        | `<thinking>` / `</thinking>` tags                                        |
| `highlights.thinking_block`      | Content inside thinking blocks                                           |
| `highlights.tool_icon`           | `◆`/`◇` icon in tool fold text (`FlemmaToolIcon`)                        |
| `highlights.tool_name`           | Tool name in tool fold text (`FlemmaToolName`)                           |
| `highlights.tool_use_title`      | `**Tool Use:**` title line (`FlemmaToolUseTitle`)                        |
| `highlights.tool_result_title`   | `**Tool Result:**` title line (`FlemmaToolResultTitle`)                  |
| `highlights.tool_result_error`   | `(error)` marker in tool results                                         |
| `highlights.tool_preview`        | Tool preview virtual lines in pending placeholders (`FlemmaToolPreview`) |
| `highlights.fold_preview`        | Content preview text in fold lines (`FlemmaFoldPreview`)                 |
| `highlights.fold_meta`           | Line count and padding in fold lines (`FlemmaFoldMeta`)                  |

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

Role markers (`@You:`, `@System:`, `@Assistant:`) inherit `role_style` (comma-separated GUI attributes such as `"bold,underline"`) so marker styling tracks your message colours.

## Rulers

Rulers are horizontal separator lines drawn between messages using virtual-line extmarks. They span the full window width and resize automatically when the window is resized.

```lua
ruler = {
  enabled = true,       -- default: true
  char = "─",           -- repeated to fill the window width
  hl = { dark = "Comment-fg:#303030", light = "Comment+fg:#303030" },
}
```

Rulers appear above the first message when frontmatter exists, and above every subsequent message.

## Sign column indicators

Set `signs.enabled = true` to place a sign character on every line of each message. Each role can override the character and highlight independently:

```lua
signs = {
  enabled = false,       -- default: false
  char = "▌",            -- default character for all roles
  system = { char = nil, hl = true },     -- nil = inherit `char`; hl = true inherits from highlights.system
  user = { char = "▏", hl = true },
  assistant = { char = nil, hl = true },
}
```

When `hl = true`, the sign colour is derived from the corresponding `highlights.<role>` group. Set `hl` to a string or table to use an explicit highlight instead.

## Spinner behaviour

While a request is in flight, Flemma appends `@Assistant: Thinking...` with an animated braille spinner (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`) rendered as end-of-line virtual text. The spinner animates at 100ms intervals and is removed once streaming starts.

When the model enters a thinking/reasoning phase, the spinner animation is replaced with a live character count – e.g., `❖ (3.2k characters)` – so you can gauge progress. The symbol is configurable via `spinner.thinking_char` (default: `"❖"`).

### Tool execution indicators

During tool execution, a separate spinner appears next to the `**Tool Result:**` block using circular quarter characters (`◐◓◑◒`). When execution completes, the indicator changes to `✓ Complete` or `✗ Failed`. Indicators reposition automatically if the buffer is modified during execution and clear on the next buffer edit.

### Tool previews

When tool calls are pending approval, Flemma renders a virtual line inside each empty `flemma:tool` placeholder showing a compact summary of what the tool will do. This lets you review and approve tools without scrolling back to the `**Tool Use:**` block.

Previews dynamically size to the editor's text area width (window width minus sign, number, and fold columns) and truncate with `…` when the content exceeds available space. Built-in tools use tailored formatters (e.g., `bash: $ make test`); custom tools can provide their own via `format_preview` on the tool definition. Tools without a custom formatter get a generic key-value summary.

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

- **Messages:** `@Role: preview... (N lines)` — role prefix uses the role's highlight group (e.g., `FlemmaAssistant`), preview uses `FlemmaFoldPreview`, line count uses `FlemmaFoldMeta`.
- **Tool Use:** `◆ Tool Use: name: params... (N lines)` — icon uses `FlemmaToolIcon`, title uses `FlemmaToolUseTitle`, name uses `FlemmaToolName`, preview uses `FlemmaFoldPreview`, meta uses `FlemmaFoldMeta`.
- **Tool Result:** `◇ Tool Result: name: preview... (N lines)` — same structure as tool use but with `FlemmaToolResultTitle`. Errors show `(error)` with `FlemmaToolResultError`.
- **Thinking blocks:** `<thinking preview...> (N lines)` — shows `<thinking redacted>` for redacted blocks, or `<thinking provider>` for blocks with a provider signature. Uses `FlemmaThinkingTag` for delimiters and `FlemmaFoldPreview` for content.
- **Frontmatter:** ` ```language preview... ``` (N lines) ` — uses `FlemmaFoldMeta` for fences and `FlemmaFoldPreview` for content.

## Notifications

Completed requests show a single-line notification bar pinned to the top of the chat window. The bar displays model, provider, token counts, cost, and cache statistics — all rendered using priority-based truncation so content degrades gracefully in narrow terminals. Higher-priority items (model name, cost) survive; lower-priority items (individual token breakdowns) are dropped first.

```lua
notifications = {
  enabled = true,        -- set to false to suppress all notification bars
  timeout = 10000,       -- milliseconds before auto-dismiss (0 = persistent)
  limit = 3,             -- maximum stacked notifications per buffer
  position = "overlay",  -- "overlay" (pinned to window top)
  zindex = 30,           -- floating window z-index (above nvim-treesitter-context)
}
```

Notification bars use dedicated highlight groups (`FlemmaNotificationsBar`, `FlemmaNotificationsModel`, `FlemmaNotificationsCost`, etc.) for distinct styling of each segment. The bottom-most bar has an underline border (`FlemmaNotificationsBottom`) to visually separate notifications from buffer content.

Bars stack vertically when multiple are active — the most recent appears at the top, older ones shift down. Each `.chat` buffer has its own notification stack. Notifications for hidden buffers are queued and shown when the buffer becomes visible. Bars re-render automatically on window resize to reflow content for the new width. Recall the most recent notification with `:Flemma notification:recall`.

See `lua/flemma/notifications.lua` for the full implementation.

## Extmark priority

Flemma uses a priority hierarchy to layer visual elements correctly when they overlap. Higher-priority extmarks take precedence:

| Priority | Element         | Notes                                         |
| -------- | --------------- | --------------------------------------------- |
| 50       | Line highlights | Base backgrounds for messages and frontmatter |
| 100      | Thinking blocks | Overrides message line highlights             |
| 200      | Thinking tags   | `<thinking>` / `</thinking>` styling          |
| 250      | Tool indicators | Execution spinners and status                 |
| 300      | Spinner         | Highest priority; suppresses spell checking   |

This hierarchy is defined in `lua/flemma/ui/init.lua` and is not user-configurable, but understanding it explains why certain elements visually override others. Tool preview virtual lines use `virt_lines` extmarks (not line-level highlights), so they don't participate in this priority hierarchy.

## Lualine integration

Add the bundled component to show the active model and thinking level:

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      { "flemma", icon = "🧠" },
      "encoding",
      "filetype",
    },
  },
})
```

The component only renders in `chat` buffers and returns an empty string otherwise.

### Format string

The display format when thinking is active is configurable via `statusline.thinking_format` in the [configuration reference](configuration.md). The default is `"{model} ({level})"`. Available variables:

| Variable  | Example                 |
| --------- | ----------------------- |
| `{model}` | `claude-sonnet-4-6`     |
| `{level}` | `high`, `medium`, `low` |

When thinking is disabled or the model doesn't support it, only the model name is shown. The component respects per-buffer overrides from `flemma.opt` – if frontmatter changes the thinking level, the statusline reflects it.
