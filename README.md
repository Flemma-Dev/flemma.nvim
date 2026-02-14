# Flemma 🪶

> [!CAUTION]
> **Actively Evolving**
>
> Flemma is growing fast – new tools, providers, and UI features land regularly. Expect occasional breaking changes while the project matures. Pin a commit if you need a steady target.

Flemma turns Neovim into a first-class AI workspace. It gives `.chat` buffers streaming conversations, tool calling, reusable prompt templates, attachment support, cost tracking, and ergonomic commands for the three major providers: Anthropic, OpenAI, and Google Vertex AI.

https://github.com/user-attachments/assets/2c688830-baef-4d1d-98ef-ae560faacf61

- **Multi-provider chat** – Anthropic, OpenAI, and Vertex AI through one command tree.
- **Tool calling** – calculator, bash, file read/edit/write, with approval flow and parallel execution.
- **Extended thinking** – unified `thinking` parameter across all providers, with automatic mapping to Anthropic budgets, OpenAI reasoning effort, and Vertex thinking budgets.
- **Template system** – Lua/JSON frontmatter, inline `{{ expressions }}`, `include()` helpers.
- **Context attachments** – reference local files with `@./path`; MIME detection and provider-aware formatting.
- **Usage reporting** – per-request and session token totals, costs, and cache metrics.
- **Theme-aware UI** – line highlights, rulers, signs, and folding that adapt to your colour scheme.

## Table of Contents

- [Installation](#installation)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [The Buffer Is the State](#the-buffer-is-the-state)
- [Understanding `.chat` Buffers](#understanding-chat-buffers)
- [Commands and Provider Management](#commands-and-provider-management)
- [Providers](#providers)
- [Tool Calling](#tool-calling)
- [Template System and Automation](#template-system-and-automation)
- [Referencing Local Files](#referencing-local-files)
- [Usage, Pricing, and Notifications](#usage-pricing-and-notifications)
- [UI Customisation](#ui-customisation)
- [Configuration Reference](#configuration-reference)
- [Developing and Testing](#developing-and-testing)
- [FAQ](#faq)
- [Troubleshooting Checklist](#troubleshooting-checklist)
- [License](#license)

---

## Installation

Flemma works with any plugin manager. With [lazy.nvim](https://github.com/folke/lazy.nvim) you only need to declare the plugin – `opts = {}` triggers `require("flemma").setup({})` automatically:

```lua
{
  "Flemma-Dev/flemma.nvim",
  opts = {},
}
```

For managers that do not wire `opts`, call `require("flemma").setup({})` yourself after the plugin is on the runtime path.

---

## Requirements

| Requirement                                                              | Why it matters                                                                                                  |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| Neovim **0.11** or newer                                                 | Uses Tree-sitter folding APIs introduced in 0.11 and relies on `vim.fs` helpers.                                |
| [`curl`](https://curl.se/)                                               | Streaming is handled by spawning `curl` with Server-Sent Events enabled.                                        |
| Markdown Tree-sitter grammar                                             | Flemma registers `.chat` buffers to reuse the Markdown parser for syntax highlighting and folding.              |
| [`file`](https://www.darwinsys.com/file/) CLI (optional but recommended) | Provides reliable MIME detection for `@./path` attachments. When missing, extensions are used as a best effort. |

### Provider credentials

| Provider         | Environment variable                                        | Notes                                                       |
| ---------------- | ----------------------------------------------------------- | ----------------------------------------------------------- |
| Anthropic        | `ANTHROPIC_API_KEY`                                         |                                                             |
| OpenAI           | `OPENAI_API_KEY`                                            | Supports GPT-5 family, including reasoning effort settings. |
| Google Vertex AI | `VERTEX_AI_ACCESS_TOKEN` **or** service-account credentials | Requires additional configuration (see below).              |

<details>
<summary><strong>Linux keyring setup (Secret Service)</strong></summary>

When environment variables are absent Flemma looks for secrets in the Secret Service keyring. Store them once and every Neovim instance can reuse them:

```bash
secret-tool store --label="Anthropic API Key" service anthropic key api
secret-tool store --label="OpenAI API Key" service openai key api
secret-tool store --label="Vertex AI Service Account" service vertex key api project_id your-gcp-project
```

</details>

<details>
<summary><strong>Vertex AI service-account flow</strong></summary>

1. Create a service account in Google Cloud and grant it the _Vertex AI user_ role.
2. Download its JSON credentials and either:
   - export them via `VERTEX_SERVICE_ACCOUNT='{"type": "..."}'`, **or**
   - store them in the Secret Service entry above (the JSON is stored verbatim).
3. Ensure the Google Cloud CLI is on your `$PATH`; Flemma shells out to `gcloud auth application-default print-access-token` whenever it needs to refresh the token.
4. Set the project/location in configuration or via `:Flemma switch vertex gemini-2.5-pro project_id=my-project location=us-central1`.

**Note:** If you only supply `VERTEX_AI_ACCESS_TOKEN`, Flemma uses that token until it expires and skips `gcloud`.

</details>

---

## Quick Start

1. Configure the plugin:

   ```lua
   require("flemma").setup({})
   ```

2. Create a new file that ends with `.chat`. Flemma only activates on that extension.
3. Type a message, for example:

   ```markdown
   @You: Turn the notes below into a short project update.
   - Added Vertex thinking budget support.
   - Refactored :Flemma command routing.
   - Documented presets in the README.
   ```

4. Press <kbd>Ctrl-]</kbd> (normal or insert mode) or run `:Flemma send`. Flemma freezes the buffer while the request is streaming and shows `@Assistant: Thinking...`. <kbd>Ctrl-]</kbd> is a hybrid key with a three-phase cycle: when the model responds with tool calls, the first press injects empty placeholders for review (see [Tool approval](#tool-approval)); the second press executes approved tools; the third press sends the conversation back to the provider.
5. When the reply finishes, a floating notification lists token counts and cost for the request and the session.

Cancel an in-flight response with <kbd>Ctrl-c</kbd> or `:Flemma cancel`.

---

## The Buffer Is the State

Most AI tools keep the real conversation hidden – in a SQLite file or a JSON log you can't touch. **Flemma doesn't.** The `.chat` buffer **is** the conversation, and nothing exists outside it. What you see is exactly what the model receives. Edit an assistant response to correct a hallucination, delete a tangent, rewrite your own message, paste in a tool result by hand – it all just works because there is no shadow state to fall out of sync. Want to fork a conversation? Duplicate the file. Want version history? You have Git. Switch from GPT to Claude mid-conversation, or turn thinking on for one turn and off for the next – every choice lives in the buffer where you can see and control it.

---

## Understanding `.chat` Buffers

### Structure

````markdown
```lua
release = {
  version = "v25.10-1",
  focus = "command presets and UI polish",
}
notes = [[
- Presets appear first in :Flemma switch completion.
- Thinking tags have dedicated highlights.
- Logging toggles now live under :Flemma logging:*.
]]
```

@System: You turn engineering notes into concise changelog entries.

@You: Summarise {{release.version}} with emphasis on {{release.focus}} using the points below:
{{notes}}

@Assistant:
- Changelog bullets...
- Follow-up actions...

<thinking>
Model thoughts stream here and auto-fold.
</thinking>
````

- **Frontmatter** sits on the first line and must be fenced with triple backticks. Lua and JSON parsers ship with Flemma; you can register more via `flemma.frontmatter.parsers.register("yaml", parser_fn)`. Lua frontmatter also exposes `flemma.opt` for [per-buffer tool selection, approval, and provider parameter overrides](docs/tools.md#per-buffer-tool-selection).
- **Messages** begin with `@System:`, `@You:`, or `@Assistant:`. The parser is whitespace-tolerant and handles blank lines between messages.
- **Thinking blocks** appear only in assistant messages. When thinking is enabled (default `"high"`), Anthropic and Vertex AI models stream `<thinking>` sections; Flemma folds them automatically and keeps dedicated highlights for the tags and body.

> [!NOTE]
> **Cross-provider thinking.** When you switch providers mid-conversation, thinking blocks from the previous provider are visible in the buffer but are **not forwarded** to the new provider's API. The visible text inside `<thinking>` tags is a summary for your reference; the actual reasoning data lives in provider-specific signature attributes on the tag. Only matching-provider signatures are replayed.

### Folding and layout

| Fold level | What folds                 | Why                                                             |
| ---------- | -------------------------- | --------------------------------------------------------------- |
| Level 2    | The frontmatter block      | Keep templates out of the way while you focus on chat history.  |
| Level 2    | `<thinking>...</thinking>` | Reasoning traces are useful, but often secondary to the answer. |
| Level 1    | Each message               | Collapse long exchanges without losing context.                 |

Toggle folds with your usual mappings (`za`, `zc`, etc.). The fold text shows a snippet of the hidden content so you know whether to expand it. The initial fold level is configurable via `editing.foldlevel` (default `1`, which collapses thinking blocks).

Between messages, Flemma draws a ruler using the configured `ruler.char` and highlight. This keeps multi-step chats legible even with folds open.

### Navigation and text objects

Inside `.chat` buffers Flemma defines:

- `]m` / `[m` – jump to the next/previous message header.
- `im` / `am` (configurable) – select the inside or entire message as a text object. `am` selects linewise and includes thinking blocks and trailing blank lines, making `dam` delete entire conversation turns. `im` skips `<thinking>` sections so yanking `im` never includes reasoning traces.
- Buffer-local mappings for send/cancel default to `<C-]>` and `<C-c>` in normal mode. `<C-]>` is a hybrid key with three phases: inject approval placeholders, execute approved tools, send the conversation. Insert-mode `<C-]>` behaves identically but re-enters insert when the operation finishes.

Disable or remap these through the `keymaps` section (see [Configuration Reference](#configuration-reference)).

---

## Commands and Provider Management

Use the single entry point `:Flemma {command}`. Autocompletion lists every available sub-command.

| Command                                                 | Purpose                                                                                  | Example                                                                     |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `:Flemma send [key=value ...]`                          | Send the current buffer. Optional callbacks run before/after the request.                | `:Flemma send on_request_start=stopinsert on_request_complete=startinsert!` |
| `:Flemma cancel`                                        | Abort the active request and clean up the spinner.                                       |                                                                             |
| `:Flemma switch ...`                                    | Choose or override provider/model parameters.                                            | See below.                                                                  |
| `:Flemma import`                                        | Convert Claude Workbench code snippets into `.chat` format ([guide](docs/importing.md)). |                                                                             |
| `:Flemma message:next` / `:Flemma message:previous`     | Jump through message headers.                                                            |                                                                             |
| `:Flemma tool:execute`                                  | Execute the tool at the cursor position.                                                 |                                                                             |
| `:Flemma tool:cancel`                                   | Cancel the tool execution at the cursor.                                                 |                                                                             |
| `:Flemma tool:cancel-all`                               | Cancel all pending tool executions in the buffer.                                        |                                                                             |
| `:Flemma tool:list`                                     | List pending tool executions with IDs and elapsed time.                                  |                                                                             |
| `:Flemma logging:enable` / `:...:disable` / `:...:open` | Toggle structured logging and open the log file.                                         |                                                                             |
| `:Flemma notification:recall`                           | Reopen the last usage/cost notification.                                                 |                                                                             |

> [!TIP]
> Legacy commands (`:FlemmaSend`, `:FlemmaCancel`, ...) still work but forward to the new command tree with a deprecation notice.

### Switching providers and models

- `:Flemma switch` (no arguments) opens two `vim.ui.select` pickers: first provider, then model.
- `:Flemma switch openai gpt-5 temperature=0.3` changes provider, model, and overrides parameters in one go.
- `:Flemma switch vertex project_id=my-project location=us-central1 thinking=medium` demonstrates long-form overrides. Anything that looks like `key=value` is accepted; unknown keys are passed to the provider for validation.

### Named presets

Define reusable setups under the `presets` key. Preset names must begin with `$`; completions prioritise them above built-in providers.

```lua
require("flemma").setup({
  presets = {
    ["$fast"] = "vertex gemini-2.5-flash temperature=0.2",
    ["$review"] = {
      provider = "anthropic",
      model = "claude-sonnet-4-5",
      max_tokens = 6000,
    },
  },
})
```

Switch using `:Flemma switch $fast` or `:Flemma switch $review temperature=0.1` to override individual values.

---

## Providers

### Unified thinking

All three providers support extended thinking/reasoning. Flemma provides a single `thinking` parameter that maps automatically to each provider's native format:

| `thinking` value       | Anthropic (budget) | OpenAI (effort)      | Vertex AI (budget) |
| ---------------------- | ------------------ | -------------------- | ------------------ |
| `"high"` **(default)** | 32,768 tokens      | `"high"` effort      | 32,768 tokens      |
| `"medium"`             | 8,192 tokens       | `"medium"` effort    | 8,192 tokens       |
| `"low"`                | 1,024 tokens       | `"low"` effort       | 1,024 tokens       |
| number (e.g. `4096`)   | 4,096 tokens       | closest effort level | 4,096 tokens       |
| `false` or `0`         | disabled           | disabled             | disabled           |

Set it once in your config and it works everywhere:

```lua
require("flemma").setup({
  parameters = {
    thinking = "high",     -- default: all providers think at maximum
  },
})
```

Or override per-request with `:Flemma switch anthropic claude-sonnet-4-5 thinking=medium`.

**Priority order:** Provider-specific parameters (`thinking_budget` for Anthropic/Vertex, `reasoning` for OpenAI) take priority over the unified `thinking` parameter when both are set. This lets you use `thinking` as the default and override with provider-native syntax when needed.

When thinking is active, the Lualine component shows the resolved level — e.g., `claude-sonnet-4-5 (high)` or `o3 (medium)`.

### Provider-specific capabilities

| Provider  | Defaults            | Extra parameters                                                                                                        | Notes                                                                              |
| --------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Anthropic | `claude-sonnet-4-5` | `thinking_budget` overrides the unified `thinking` parameter with an exact token budget (clamped to min 1,024).         | Supports text, image, and PDF attachments. Thinking blocks stream into the buffer. |
| OpenAI    | `gpt-5`             | `reasoning` overrides the unified `thinking` parameter with an explicit effort level (`"low"`, `"medium"`, `"high"`).   | Cost notifications include reasoning tokens. Lualine shows the reasoning level.    |
| Vertex AI | `gemini-2.5-pro`    | `project_id` (required), `location` (default `global`), `thinking_budget` overrides with an exact token budget (min 1). | `thinking_budget` overrides the unified `thinking` parameter for Vertex.           |

The full model catalogue (including pricing) is in `lua/flemma/models.lua`. You can access it from Neovim with:

```lua
:lua print(vim.inspect(require("flemma.provider.config").models))
```

### Prompt caching

All three providers support prompt caching. Flemma handles breakpoint placement (Anthropic), cache keys (OpenAI), and implicit caching (Vertex) automatically. The `cache_retention` parameter controls the strategy where applicable:

|               | Anthropic         | OpenAI                | Vertex AI   |
| ------------- | ----------------- | --------------------- | ----------- |
| Default       | `"short"` (5 min) | `"short"` (in-memory) | Automatic   |
| Min. tokens   | 1,024–4,096       | 1,024                 | 1,024–2,048 |
| Read discount | 90%               | 50%                   | 90%         |

When a cache hit occurs, the usage notification shows a `Cache:` line with read/write token counts. See [docs/prompt-caching.md](docs/prompt-caching.md) for provider-specific details, caveats, and pricing tables.

---

## Tool Calling

Flemma includes a tool system that lets models request actions – run a calculation, execute a shell command, read or modify files – and receive structured results, all within the `.chat` buffer.

### How it works

1. When you send a message, Flemma includes definitions for available tools in the API request.
2. If the model decides to use a tool, it emits a `**Tool Use:**` block in its response.
3. Press <kbd>Ctrl-]</kbd> to review tool calls. Flemma injects empty `**Tool Result:**` placeholders so you can inspect each call before execution. Press <kbd>Ctrl-]</kbd> again to execute all remaining pending tools, or press <kbd>Alt-Enter</kbd> to execute a single tool at the cursor.
4. Send the buffer again (<kbd>Ctrl-]</kbd> or `:Flemma send`) to continue the conversation.

### Built-in tools

| Tool         | Type  | Description                                                                                                         |
| ------------ | ----- | ------------------------------------------------------------------------------------------------------------------- |
| `calculator` | sync  | Evaluates mathematical expressions using Lua's `math` library. Sandboxed – only `math.*` functions are available.   |
| `bash`       | async | Executes shell commands. Configurable shell, working directory, and environment. Supports timeout and cancellation. |
| `read`       | sync  | Reads file contents with optional offset and line limit. Relative paths resolve against the `.chat` file.           |
| `write`      | sync  | Writes or creates files. Creates parent directories automatically.                                                  |
| `edit`       | sync  | Find-and-replace with exact text matching. The old text must appear exactly once in the target file.                |

By default, every tool call requires your approval before execution — <kbd>Ctrl-]</kbd> injects review placeholders first, then executes on a second press. Whitelist safe tools globally with `tools.auto_approve = { "calculator", "read" }`, or per-buffer via `flemma.opt.tools.auto_approve` in frontmatter. Set `tools.require_approval = false` to skip approval entirely. You can also register your own tools with `require("flemma.tools").register()` and extend the approval chain with custom resolvers for plugin-level security policies. See [docs/tools.md](docs/tools.md) for the full reference on approval, per-buffer configuration, custom tool registration, and the resolver API.

---

## Template System and Automation

Flemma's prompt pipeline runs through three stages: parse, evaluate, and send. Errors at any stage surface via diagnostics before the request leaves your editor.

### Frontmatter

- Place a fenced block on the first line (` ```lua ` or ` ```json `).
- Return a table of variables to inject into the template environment.
- Errors (syntax problems, missing parser) block the request and show in a detailed notification with filename and line number.

````lua
```lua
recipient = "QA team"
notes = [[
- Verify presets list before providers.
- Check spinner no longer triggers spell checking.
- Confirm logging commands live under :Flemma logging:*.
]]
```
````

### Inline expressions

Use `{{ expression }}` inside any non-assistant message. Expressions run in a sandbox that exposes:

- Standard Lua libs (`string`, `table`, `math`, `utf8`).
- `vim.fn` (`fnamemodify`, `getcwd`) and `vim.fs` (`normalize`, `abspath`).
- Variables returned from frontmatter.
- `__filename` – the absolute path to the current `.chat` file.
- `__dirname` – the directory containing the current file.

Outputs are converted to strings. Tables are JSON-encoded automatically.

```markdown
@You: Draft a short update for {{recipient}} covering:
{{notes}}
```

Errors in expressions are downgraded to warnings. The request still sends, and the literal `{{ expression }}` remains in the prompt so you can see what failed.

### `include()` helper

Call `include("relative/or/absolute/path")` inside frontmatter or an expression to inline another template fragment. Includes support two modes:

**Text mode** (default) – the included file is parsed for `{{ }}` expressions and `@./` file references, which are evaluated recursively. The result is inlined as text:

```markdown
@System: {{ include("system-prompt.md") }}
```

**Binary mode** – the file is read as raw bytes and attached as a structured content part (image, PDF, etc.), just like `@./path`:

```lua
-- In frontmatter:
screenshot = include('./latest.png', { binary = true })
```

```markdown
@You: What do you see? {{ screenshot }}
```

The `binary` flag and an optional `mime` override are passed as a second argument:

```lua
include('./data.bin', { binary = true, mime = 'text/csv' })
```

Guards in place:

- Relative paths resolve against the file that called `include()`.
- Circular includes raise a descriptive error with the include stack.
- Missing files or read errors raise warnings that block the request.
- Included files get their own `__filename` and `__dirname`, isolated from the parent's variables.

### Diagnostics at a glance

Flemma groups diagnostics by type in the notification shown before sending:

- **Frontmatter errors** (blocking) – malformed code, unknown parser, include issues.
- **Expression warnings** (non-blocking) – runtime errors during `{{ }}` evaluation.
- **File reference warnings** (non-blocking) – missing files, unsupported MIME types.

If any blocking error occurs the buffer becomes modifiable again and the request is cancelled before hitting the network.

---

## Referencing Local Files

Embed local context with `@./relative/path` (or `@../up-one/path`). Flemma handles:

1. Resolving the path against the `.chat` file (after decoding URL-escaped characters like `%20`).
2. Detecting the MIME type via `file` or the extension fallback.
3. Streaming the file in the provider-specific format.

Examples:

```markdown
@You: Critique @./patches/fix.lua;type=text/x-lua.
@You: OCR this screenshot @./artifacts/failure.png.
@You: Compare these specs: @./specs/v1.pdf and @./specs/v2.pdf.
```

Trailing punctuation such as `.` or `)` is ignored so you can keep natural prose. To coerce a MIME type, append `;type=<mime>` as in the Lua example above.

> [!TIP]
> Under the hood, `@./path` desugars to an `include()` call in binary mode. This means `@./file.png` and `{{ include('./file.png', { binary = true }) }}` are equivalent – you can use whichever reads better in context.

| Provider  | Text files                   | Images                                     | PDFs                   | Behaviour when unsupported                             |
| --------- | ---------------------------- | ------------------------------------------ | ---------------------- | ------------------------------------------------------ |
| Anthropic | Embedded as plain text parts | Uploaded as base64 image parts             | Sent as document parts | The literal `@./path` is kept and a warning is shown.  |
| OpenAI    | Embedded as text parts       | Sent as `image_url` entries with data URLs | Sent as `file` objects | Unsupported types become plain text with a diagnostic. |
| Vertex AI | Embedded as text parts       | Sent as `inlineData`                       | Sent as `inlineData`   | Falls back to text with a warning.                     |

If a file cannot be read or the provider refuses its MIME type, Flemma warns you (including line number) and continues with the raw reference so you can adjust your prompt.

---

## Usage, Pricing, and Notifications

Each completed request emits a floating report that names the provider/model, lists input/output tokens (reasoning tokens are counted under `thoughts`), and – when pricing is enabled – shows the per-request and cumulative session cost derived from `lua/flemma/models.lua`. When prompt caching is active, a `Cache:` line shows read and write token counts. Token accounting persists for the lifetime of the Neovim instance; call `require("flemma.state").reset_session()` to zero the counters without restarting. `pricing.enabled = false` suppresses the dollar amounts while keeping token totals.

Notifications are buffer-local – each `.chat` buffer gets its own notification stack, positioned relative to its window. Notifications for hidden buffers are queued and shown when the buffer becomes visible. Recall the most recent notification with `:Flemma notification:recall`.

For programmatic access to token usage and cost data, see [docs/session-api.md](docs/session-api.md).

---

## UI Customisation

### Highlights and styles

Configuration keys map to dedicated highlight groups:

| Key                              | Applies to                             |
| -------------------------------- | -------------------------------------- |
| `highlights.system`              | System messages (`FlemmaSystem`)       |
| `highlights.user`                | User messages (`FlemmaUser`)           |
| `highlights.assistant`           | Assistant messages (`FlemmaAssistant`) |
| `highlights.user_lua_expression` | `{{ expression }}` fragments           |
| `highlights.user_file_reference` | `@./path` fragments                    |
| `highlights.thinking_tag`        | `<thinking>` / `</thinking>` tags      |
| `highlights.thinking_block`      | Content inside thinking blocks         |
| `highlights.tool_use`            | `**Tool Use:**` title line             |
| `highlights.tool_result`         | `**Tool Result:**` title line          |
| `highlights.tool_result_error`   | `(error)` marker in tool results       |

Each value accepts a highlight name, a hex colour string, or a table of highlight attributes (`{ fg = "#ffcc00", bold = true }`).

<details><summary><h3>Theme-aware values</h3></summary>

Any highlight value can be theme-aware using `{ dark = ..., light = ... }`:

```lua
ruler = { hl = { dark = "Comment-fg:#303030", light = "Comment+fg:#303030" } }
```

### Highlight expressions

Derive colours from existing highlight groups with blend operations:

```lua
-- Lighten Normal's bg by #101010
line_highlights = { user = { dark = "Normal+bg:#101010" } }

-- Darken with -
ruler = { hl = { light = "Normal-fg:#303030" } }

-- Multiple operations on same group
"Normal+bg:#101010-fg:#202020"

-- Fallback chain: try FooBar first, then Normal (only last uses defaults)
"FooBar+bg:#201020,Normal+bg:#101010"
```

When the last highlight group lacks the requested attribute, Flemma falls back to `defaults`:

```lua
defaults = {
  dark = { bg = "#000000", fg = "#ffffff" },
  light = { bg = "#ffffff", fg = "#000000" },
}
```

</details>

### Line highlights

Full-line background colours distinguish message roles. Disable with `line_highlights.enabled = false` (default: `true`):

```lua
line_highlights = {
  enabled = true,
  frontmatter = { dark = "Normal+bg:#201020", light = "Normal-bg:#201020" },
  system = { dark = "Normal+bg:#201000", light = "Normal-bg:#201000" },
  user = { dark = "Normal", light = "Normal" },
  assistant = { dark = "Normal+bg:#102020", light = "Normal-bg:#102020" },
}
```

Role markers inherit `role_style` (comma-separated GUI attributes) so marker styling tracks your message colours.

### Sign column indicators

Set `signs.enabled = true` to place signs for each message line. Each role (`system`, `user`, `assistant`) can override the character and highlight. Signs default to using the message highlight colour.

### Spinner behaviour

While a request runs Flemma appends `@Assistant: Thinking...` with an animated braille spinner using virtual text extmarks. Once streaming starts, the spinner is removed and replaced with the streamed content.

When the model is in a thinking/reasoning phase, the spinner animation is replaced with a live character count – e.g., `❖ (3.2k characters)` – so you can gauge progress. The symbol is configurable via `spinner.thinking_char`. Tool execution also shows a spinner next to the tool result block while the tool is running.

### Lualine integration

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

The component only renders in `chat` buffers. When thinking is active it shows `model (level)` — e.g., `claude-sonnet-4-5 (high)` or `o3 (medium)`. The format string is configurable via `statusline.thinking_format` in the [Configuration Reference](#configuration-reference).

---

## Configuration Reference

Flemma works without arguments, but every option can be overridden:

```lua
require("flemma").setup({
  provider = "anthropic",                    -- "anthropic" | "openai" | "vertex"
  model = nil,                               -- nil = provider default
  parameters = {
    max_tokens = 4000,
    temperature = 0.7,
    timeout = 120,                           -- Response timeout (seconds)
    connect_timeout = 10,                    -- Connection timeout (seconds)
    thinking = "high",                       -- "low" | "medium" | "high" | number | false
    cache_retention = "short",               -- "none" | "short" | "long"
    anthropic = {
      thinking_budget = nil,                 -- Override thinking with exact budget (>= 1024)
    },
    vertex = {
      project_id = nil,                      -- Google Cloud project ID (required for Vertex)
      location = "global",                   -- Google Cloud region
      thinking_budget = nil,                 -- Override thinking with exact budget (>= 1)
    },
    openai = {
      reasoning = nil,                       -- Override thinking with explicit effort level
    },
  },
  presets = {},                              -- Named presets: ["$name"] = "provider model key=val"
  tools = {
    require_approval = true,                 -- Review tool calls before execution
    auto_approve = nil,                      -- string[] | function | nil
    default_timeout = 30,                    -- Async tool timeout (seconds)
    show_spinner = true,                     -- Animated spinner during execution
    cursor_after_result = "result",          -- "result" | "stay" | "next"
    bash = {
      shell = nil,                           -- Shell binary (default: bash)
      cwd = nil,                             -- Working directory (nil = buffer dir)
      env = nil,                             -- Extra environment variables
    },
  },
  defaults = {
    dark = { bg = "#000000", fg = "#ffffff" },
    light = { bg = "#ffffff", fg = "#000000" },
  },
  highlights = {
    system = "Special",
    user = "Normal",
    assistant = "Normal",
    user_lua_expression = "PreProc",
    user_file_reference = "Include",
    thinking_tag = "Comment",
    thinking_block = { dark = "Comment+bg:#102020-fg:#111111",
                       light = "Comment-bg:#102020+fg:#111111" },
    tool_use = "Function",
    tool_result = "Function",
    tool_result_error = "DiagnosticError",
  },
  role_style = "bold,underline",
  ruler = {
    enabled = true,
    char = "─",
    hl = { dark = "Comment-fg:#303030", light = "Comment+fg:#303030" },
  },
  signs = {
    enabled = false,
    char = "▌",
    system = { char = nil, hl = true },
    user = { char = "▏", hl = true },
    assistant = { char = nil, hl = true },
  },
  spinner = {
    thinking_char = "❖",
  },
  line_highlights = {
    enabled = true,
    frontmatter = { dark = "Normal+bg:#201020", light = "Normal-bg:#201020" },
    system = { dark = "Normal+bg:#201000", light = "Normal-bg:#201000" },
    user = { dark = "Normal", light = "Normal" },
    assistant = { dark = "Normal+bg:#102020", light = "Normal-bg:#102020" },
  },
  notify = require("flemma.notify").default_opts,
  pricing = { enabled = true },
  statusline = {
    thinking_format = "{model} ({level})",   -- Format when thinking is active
  },
  text_object = "m",                         -- "m" or false to disable
  editing = {
    disable_textwidth = true,
    auto_write = false,                      -- Write buffer after each request
    manage_updatetime = true,                -- Lower updatetime in chat buffers
    foldlevel = 1,                           -- 0=all closed, 1=thinking collapsed, 99=all open
  },
  logging = {
    enabled = false,
    path = vim.fn.stdpath("cache") .. "/flemma.log",
  },
  keymaps = {
    enabled = true,
    normal = {
      send = "<C-]>",                        -- Hybrid: execute pending tools or send
      cancel = "<C-c>",
      tool_execute = "<M-CR>",               -- Execute tool at cursor
      next_message = "]m",
      prev_message = "[m",
    },
    insert = {
      send = "<C-]>",                        -- Same hybrid behaviour, re-enters insert after
    },
  },
})
```

Set `keymaps.enabled = false` to disable all built-in mappings. The `send` key is a hybrid dispatch with three phases: inject approval placeholders, execute pending tools, then send. For send-only behaviour, bind directly to `require("flemma.core").send_to_provider()`.

---

## Developing and Testing

The repository provides a Nix shell so everyone shares the same toolchain:

```bash
nix develop
```

Inside the shell you gain convenience wrappers:

- `flemma-fmt` – run `nixfmt`, `stylua`, and `prettier` across the repo.
- `flemma-amp` – open the Amp CLI, preconfigured for this project.
- `flemma-codex` – launch the OpenAI Codex helper.
- `flemma-claude` – launch Claude Code for this project.

Run the automated tests with:

```bash
make test
```

The suite boots headless Neovim via `tests/minimal_init.lua` and executes Plenary+Busted specs in `tests/flemma/`, printing detailed results for each spec so you can follow along.

Other useful Makefile targets:

```bash
make lint          # Run luacheck on all Lua files
make check         # Run lua-language-server type checking
make develop       # Launch Neovim with Flemma loaded for local testing
make screenshot    # Generate screenshots
```

To exercise the plugin without installing it globally, run `make develop` – it launches Neovim with Flemma on the runtime path and opens a scratch `.chat` buffer.

> [!NOTE]
> **Almost every line of code** in Flemma has been authored through AI pair-programming tools (Claude Code as of late, Amp and Aider in the past). Traditional contributions are welcome – just keep changes focused, documented, and tested.

---

## FAQ

<details>
<summary>
<strong>Q: What is this and who is it for?</strong><br>
<strong>A:</strong> Flemma is a Neovim-native AI workspace. I [<a href="https://github.com/StanAngeloff"><img src="https://images.weserv.nl/?url=gravatar.com%2Favatar%2Fea3f8f366bb2aa0855db031884e3a8e8%3Fs%3D400%26d%3Drobohash%26r%3Dg&mask=circle" valign="middle" width="18" height="18" alt="Photo of @StanAngeloff">&thinsp;@StanAngeloff</a>] created Flemma as the place where I think, write, and experiment with AI. <em>[continued]</em>
</summary>

Flemma is for the technical writers, researchers, creators, and tinkerers, for those who occasionally get in hot water and need advice. It's for everyone who wants to experiment with AI.

With built-in tool calling, Flemma is also becoming a capable environment for coding experiments – it can run shell commands, read and edit files, and evaluate expressions, all from within a chat buffer. Flemma is not trying to replace dedicated coding agents like Claude Code or Codex, but it gives you a conversational workspace where code tasks sit naturally alongside everything else.

</details>

<details>
<summary>
<strong>Q: Why Flemma and not X or Y? <em>(where X = Claude Workbench, Y = ChatGPT, etc.)</em></strong><br>
<strong>A:</strong> The terminal and Neovim are where I spend most of my time. I needed a plug-in that would maximize my productivity and let me experiment with multiple models. I needn't worry about <em>[continued]</em>
</summary>

...accidentally pressing <kbd>&lt;C-R></kbd> and refreshing the page midway through a prompt (or <kbd>&lt;C-W></kbd> trying to delete a word)... or Chrome sending a tab to sleep whilst I had an unsaved session... or having to worry about whether files I shared with Claude Workbench were stored on some Anthropic server indefinitely. I can be fast! I can be reckless! I can tinker! I can use my Vim keybindings and years of muscle memory!

If I have an idea, it's a buffer away. Should I want to branch off and experiment, I'd duplicate the `.chat` file and go in a different direction. Is the conversation getting too long? I'd summarize a set of instructions and start with them in a new `.chat` file, then share them each time I need a fresh start. Need backups or history? I have Git for that.

</details>

<details>
<summary>
<strong>Q: What can I use Flemma for?</strong><br>
<strong>A:</strong> Flemma is versatile - I'm personally using it mostly professionally and occasionally for personal tasks. Over the last 6+ months since Flemma was created, I've used it to <em>[continued]</em>
</summary>

- Write countless technical documents, from <abbr title="Product Requirements Document">PRDs (Product Requirements Document)</abbr>, <abbr title="Architecture Knowledge Management">AKM (Architecture Knowledge Management)</abbr>, infrastructure and architecture diagrams with Mermaid, detailed storyboards for <abbr title="Learning Management System">LMS (Learning Management System)</abbr> content, release notes, <abbr title="Functional Requirements">FR (Functional Requirements)</abbr>, etc.
- Write detailed software design documents using Figma designs as input and the cheap OCR capabilities of Gemini Flash to annotate them, then the excellent reasoning capabilities of Gemini Pro to generate storyboards and interaction flows.
- Record video sessions which I later transcribed using Whisper and then turned into training materials using Flemma.
- Generate client-facing documentation from very technical input, stripping it of technical jargon and making it accessible to a wider audience.
- Create multiple <abbr title="Statement of Work">SOW (Statement of Work)</abbr> documents for clients.
- Keep track of evolving requirements and decisions by maintaining a long history of meeting minutes.
- Collect large swaths of emails, meeting minutes, Slack conversations, Trello cards, and distill them into actionable tasks and project plans.
- As a tool for other AI agents – generate prompts for Midjourney, Reve, etc. and even prompts that I'd feed to different `.chat` buffers in Flemma.

There really is no limit to what you can do with Flemma – if you can write it down and reason about it, you can use Flemma to help you with it.

On a personal level, I've used Flemma to generate bedtime stories with recurring characters for my kids, made small financial decisions based on collected evidence, asked for advice on how to respond to difficult situations, consulted _(usual disclaimer, blah blah)_ it for legal advice and much more.

</details>

---

## Troubleshooting Checklist

- **Nothing happens when I send:** confirm the buffer name ends with `.chat` and the first message starts with `@You:` or `@System:`.
- **Frontmatter errors:** notifications list the exact line and file. Fix the error and resend; Flemma will not contact the provider until the frontmatter parses cleanly.
- **Attachments ignored:** ensure the file exists relative to the `.chat` file and that the provider supports its MIME type. Use `;type=` to override when necessary.
- **Temperature ignored:** when thinking is enabled (default `"high"`), Anthropic and OpenAI disable temperature. Set `thinking = false` if you need temperature control.
- **Vertex refuses requests:** double-check `parameters.vertex.project_id` and authentication. Run `gcloud auth application-default print-access-token` manually to ensure credentials are valid.
- **Tool execution doesn't respond:** make sure the cursor is on or near the `**Tool Use:**` block. Only tools with registered executors can be run – check `:lua print(vim.inspect(require("flemma.tools").get_all()))`.
- **Keymaps clash:** disable built-in mappings via `keymaps.enabled = false` and register your own `:Flemma` commands.
- **Cross-buffer issues:** Flemma manages state per-buffer. If something feels off after switching between multiple `.chat` buffers, ensure each buffer has been saved (unsaved buffers lack `__dirname` for path resolution).

## License

Flemma is licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0).

Happy prompting!
