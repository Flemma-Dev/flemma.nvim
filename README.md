# Flemma 🪶

> [!CAUTION]
> **Actively Refactoring**
>
> Flemma (formerly Claudius) is in the middle of a large-scale rename and architecture refresh. Expect new functionality, renamed modules, and occasional breaking changes while the project settles. Pin a commit if you need a steady target.

Flemma turns Neovim into a first-class AI workspace. It gives `.chat` buffers streaming conversations, reusable prompt templates, attachment support, cost tracking, and ergonomic commands for the three major providers: Anthropic, OpenAI, and Google Vertex AI.

<a href="assets/frame_linux_slate.webp" target="_blank"><img align="center" width="730" height="882" src="assets/frame_linux_slate.webp" alt="Flemma chat buffer example" /></a>

---

<details>
<summary>
<strong>Q: What is this and who is it for?</strong><br>
<strong>A:</strong> Flemma is <strong><em>not</em></strong> a coding assistant. I [<a href="https://github.com/StanAngeloff"><img src="https://images.weserv.nl/?url=gravatar.com%2Favatar%2Fea3f8f366bb2aa0855db031884e3a8e8%3Fs%3D400%26d%3Drobohash%26r%3Dg&mask=circle" valign="middle" width="18" height="18" alt="Photo of @StanAngeloff">&thinsp;@StanAngeloff</a>] created Flemma as my AI workspace for everything else. <em>[continued]</em>
</summary>

Flemma is for the technical writers, researchers, creators, and tinkerers, for those who occasionally get in hot water and need advice. It's for everyone who wants to experiment with AI.

</details>

<details>
<summary>
<strong>Q: Why Flemma and not X or Y? <em>(where X = Claude Workbench, Y = ChatGPT, etc.)</em></strong><br>
<strong>A:</strong> The terminal and Neovim are where I spend most of my time. I needed a plug-in that would maximize my productivity and let me experiment with multiple models. I needn't worry about <em>[continued]</em>
</summary>

…accidentally pressing <kbd>&lt;C-R></kbd> and refreshing the page midway through a prompt (or <kbd>&lt;C-W></kbd> trying to delete a word)… or Chrome sending a tab to sleep whilst I had an unsaved session… or having to worry about whether files I shared with Claude Workbench were stored on some Anthropic server indefinitely. I can be fast! I can be reckless! I can tinker! I can use my Vim keybindings and years of muscle memory!

If I have an idea, it's a buffer away. Should I want to branch off and experiment, I'd duplicate the `.chat` file and go in a different direction. Is the conversation getting too long? I'd summarize a set of instructions and start with them in a new `.chat` file, then share them each time I need a fresh start. Need backups or history? I have Git for that.

</details>

<details>
<summary>
<strong>Q: What can I use Flemma for?</strong><br>
<strong>A:</strong> Flemma is versatile - I'm personally using it mostly professionally and occasionally for personal tasks. Over the last 6+ months since Flemma was created, I've used it to <em>[continued]</em>
</summary>

- Write countless technical documents, from <abbr title="Product Requirements Document">PRDs (Product Requirements Document)</abbr>, <abbr title="Architecture Knowledge Management">AKM (Architecture Knowledge Management)</abbr>, infrastructure and architecture diagrams with Mermaid, detailed storyboards for <abbr title="Learning Management System">LMS</abbr> content, release notes, <abbr title="Functional Requirements">FR (Functional Requirements)</abbr>, etc.
- Write detailed software design documents using Figma designs as input and the cheap OCR capabilities of Gemini Flash to annotate them, then the excellent reasoning capabilities of Gemini Pro to generate storyboards and interaction flows.
- Record video sessions which I later transcribed using Whisper and then turned into training materials using Flemma.
- Generate client-facing documentation from very technical input, stripping it of technical jargon and making it accessible to a wider audience.
- Create multiple <abbr title="Statement of Work">SOW (Statement of Work)</abbr> documents for clients.
- Keep track of evolving requirements and decisions by maintaining a long history of meeting minutes.
- Collect large swaths of emails, meeting minutes, Slack conversations, Trello cards, and distill them into actionable tasks and project plans.
- As a tool for other AI agents - generate prompts for Midjourney, Reve, etc. and even prompts that I'd feed to different `.chat` buffers in Flemma.

There really is no limit to what you can do with Flemma - if you can write it down and reason about it, you can use Flemma to help you with it.

On a personal level, I've used Flemma to generate bedtime stories with recurring characters for my kids, made small financial decisions based on collected evidence, asked for advice on how to respond to difficult situations, consulted _(usual disclaimer, blah blah)_ it for legal advice and much more.

Flemma can also be a playground for coding experiments - it can help with the occasional small task. I've personally used it to generate Awk scripts, small Node.js jobs, etc. **Flemma is not a coding assistant or agent.** It's not pretending to be one and it'll never be one. You should keep your Codex, Claude Code, etc. for that purpose - and they'll do a great job at it.

</details>

## What Flemma Delivers

- **Multi-provider chat** – work with Anthropic, OpenAI, and Vertex models through one command tree while keeping prompts in plain `.chat` buffers.
- **`.chat` editing tools** – get markdown folding, visual rulers, `<thinking>` highlighting, and message text objects tuned for chat transcripts.
- **Structured templates** – combine Lua or JSON frontmatter, inline `{{ expressions }}`, and `include()` helpers to assemble prompts without leaving Neovim.
- **Context attachments** – reference local files with `@./path`; Flemma handles MIME detection and surfaces warnings when a provider can’t ingest the asset.
- **Reasoning visibility** – stream Vertex thinking blocks into the buffer, expose OpenAI reasoning effort in lualine, and strip thought traces from the history sent back to models.
- **Usage reporting** – per-request and session notifications show token totals and costs using the bundled pricing tables.
- **Presets and hooks** – store favourite provider configurations, run `on_request_*` callbacks, auto-write finished chats, and recall the latest usage notification when auditing work.
- **Contributor tooling** – toggle structured logs, drop into the project’s Nix dev shell, and run the bundled headless tests without extra setup.

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
| Markdown Tree-sitter grammar                                             | Flemma registers `.chat` buffers to reuse the markdown parser for syntax highlighting and folding.              |
| [`file`](https://www.darwinsys.com/file/) CLI (optional but recommended) | Provides reliable MIME detection for `@./path` attachments. When missing, extensions are used as a best effort. |

### Provider credentials

| Provider         | Environment variable                                        | Notes                                                       |
| ---------------- | ----------------------------------------------------------- | ----------------------------------------------------------- |
| Anthropic        | `ANTHROPIC_API_KEY`                                         |                                                             |
| OpenAI           | `OPENAI_API_KEY`                                            | Supports GPT‑5 family, including reasoning effort settings. |
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

> [!NOTE]
> If you only supply `VERTEX_AI_ACCESS_TOKEN`, Flemma uses that token until it expires and skips `gcloud`.

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

4. Press <kbd>Ctrl-]</kbd> (normal or insert mode) or run `:Flemma send`. Flemma freezes the buffer while the request is streaming and shows `@Assistant: Thinking...`.
5. When the reply finishes, a floating notification lists token counts and cost for the request and the session.

Cancel an in-flight response with <kbd>Ctrl-c</kbd> or `:Flemma cancel`.

> [!TIP]
> Legacy commands (`:FlemmaSend`, `:FlemmaCancel`, …) still work but forward to the new command tree with a deprecation notice.

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

- **Frontmatter** sits on the first line and must be fenced with triple backticks. Lua and JSON parsers ship with Flemma; you can register more via `flemma.frontmatter.parsers.register("yaml", parser_fn)`.
- **Messages** begin with `@System:`, `@You:`, or `@Assistant:`. The parser is whitespace-tolerant and handles blank lines between messages.
- **Thinking blocks** appear only in assistant messages. Vertex AI models stream `<thinking>` sections; Flemma folds them automatically and keeps dedicated highlights for the tags and body.

### Folding and layout

| Fold level | What folds                 | Why                                                             |
| ---------- | -------------------------- | --------------------------------------------------------------- |
| Level 3    | The frontmatter block      | Keep templates out of the way while you focus on chat history.  |
| Level 2    | `<thinking>...</thinking>` | Reasoning traces are useful, but often secondary to the answer. |
| Level 1    | Each message               | Collapse long exchanges without losing context.                 |

Toggle folds with your usual mappings (`za`, `zc`, etc.). The fold text shows a snippet of the hidden content so you know whether to expand it.

Between messages, Flemma draws a ruler using the configured `ruler.char` and highlight. This keeps multi-step chats legible even with folds open.

### Navigation and text objects

Inside `.chat` buffers Flemma defines:

- `]m` / `[m` – jump to the next/previous message header.
- `im` / `am` (configurable) – select the inside or entire message as a text object. Thinking blocks are skipped so yanking `im` never includes `<thinking>` sections unintentionally.
- Buffer-local mappings for send/cancel default to `<C-]>` and `<C-c>` in normal mode. Insert-mode `<C-]>` stops insert, sends, and re-enters insert when the response finishes.

Disable or remap these through the `keymaps` section (see [Configuration reference](#configuration-reference)).

---

## Commands and Provider Management

Use the single entry point `:Flemma {command}`. Autocompletion lists every available sub-command.

| Command                                             | Purpose                                                                   | Example                                                                     |
| --------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `:Flemma send [key=value …]`                        | Send the current buffer. Optional callbacks run before/after the request. | `:Flemma send on_request_start=stopinsert on_request_complete=startinsert!` |
| `:Flemma cancel`                                    | Abort the active request and clean up the spinner.                        |                                                                             |
| `:Flemma switch …`                                  | Choose or override provider/model parameters.                             | See below.                                                                  |
| `:Flemma message:next` / `:Flemma message:previous` | Jump through message headers.                                             |                                                                             |
| `:Flemma logging:enable` / `:…:disable` / `:…:open` | Toggle structured logging and open the log file.                          |                                                                             |
| `:Flemma notification:recall`                       | Reopen the last usage/cost notification.                                  |                                                                             |
| `:Flemma import`                                    | Convert Claude Workbench code snippets into `.chat` format.               |                                                                             |

### Switching providers and models

- `:Flemma switch` (no arguments) opens two `vim.ui.select` pickers: first provider, then model.
- `:Flemma switch openai gpt-5 temperature=0.3` changes provider, model, and overrides parameters in one go.
- `:Flemma switch vertex project_id=my-project location=us-central1 thinking_budget=4096` demonstrates long-form overrides. Anything that looks like `key=value` is accepted; unknown keys are passed to the provider for validation.

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

### Provider-specific capabilities

| Provider  | Defaults            | Extra parameters                                                                                                                                                                                             | Notes                                                                                                  |
| --------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| Anthropic | `claude-sonnet-4-5` | Standard `max_tokens`, `temperature`, `timeout`, `connect_timeout`.                                                                                                                                          | Supports text, image, and PDF attachments.                                                             |
| OpenAI    | `gpt-5`             | `reasoning=<low\|medium\|high>` toggles reasoning effort. When set, lualine includes the reasoning level and Flemma keeps your configured `max_tokens` aligned with OpenAI’s completion limit automatically. | Cost notifications include reasoning tokens.                                                           |
| Vertex AI | `gemini-2.5-pro`    | `project_id` (required), `location` (default `global`), `thinking_budget` enables streamed `<thinking>` traces.                                                                                              | `thinking_budget` ≥ 1 activates Google’s experimental thinking output; set to `0` or `nil` to disable. |

The full model cataloguel (including pricing) is in `lua/flemma/models.lua`. You can access it from Neovim with:

```lua
:lua print(vim.inspect(require("flemma.provider.config").models))
```

---

## Template System and Automation

Flemma’s prompt pipeline runs through three stages: parse, evaluate, and send. Errors at any stage surface via diagnostics before the request leaves your editor.

### Frontmatter

- Place a fenced block on the first line (` ```lua ` or ` ```json `).
- Return a table of variables to inject into the template environment.
- Errors (syntax problems, missing parser) block the request and show in a detailed notification with filename and line number.

``````lua
```lua
recipient = "QA team"
notes = [[
- Verify presets list before providers.
- Check spinner no longer triggers spell checking.
- Confirm logging commands live under :Flemma logging:*.
]]
```
``````

### Inline expressions

Use `{{ expression }}` inside any non-assistant message. Expressions run in a sandbox that exposes:

- Standard Lua libs (`string`, `table`, `math`, `utf8`).
- `vim.fn` (`fnamemodify`, `getcwd`) and `vim.fs` (`normalize`, `abspath`).
- Variables returned from frontmatter.

Outputs are converted to strings. Tables are JSON-encoded automatically.

```markdown
@You: Draft a short update for {{recipient}} covering:
{{notes}}
```

Errors in expressions are downgraded to warnings. The request still sends, and the literal `{{ expression }}` remains in the prompt so you can see what failed.

### `include()` helper

Call `include("relative/or/absolute/path")` inside frontmatter or an expression to inline another template fragment. Includes are evaluated in isolation (they do not inherit your variables) and support their own `{{ }}` and `@./` references.

Guards in place:

- Relative paths resolve against the file that called `include()`.
- Circular includes raise a descriptive error with the include stack.
- Missing files or read errors raise warnings that block the request.

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

| Provider  | Text files                   | Images                                     | PDFs                   | Behaviour when unsupported                             |
| --------- | ---------------------------- | ------------------------------------------ | ---------------------- | ------------------------------------------------------ |
| Anthropic | Embedded as plain text parts | Uploaded as base64 image parts             | Sent as document parts | The literal `@./path` is kept and a warning is shown.  |
| OpenAI    | Embedded as text parts       | Sent as `image_url` entries with data URLs | Sent as `file` objects | Unsupported types become plain text with a diagnostic. |
| Vertex AI | Embedded as text parts       | Sent as `inlineData`                       | Sent as `inlineData`   | Falls back to text with a warning.                     |

If a file cannot be read or the provider refuses its MIME type, Flemma warns you (including line number) and continues with the raw reference so you can adjust your prompt.

---

## Usage, Pricing, and Notifications

Each completed request emits a floating report that names the provider/model, lists input/output tokens (reasoning tokens are counted under `⊂ thoughts`), and – when pricing is enabled – shows the per-request and cumulative session cost derived from `lua/flemma/models.lua`. Token accounting persists for the lifetime of the Neovim instance; call `require("flemma.state").reset_session()` if you need to zero the counters without restarting. `pricing.enabled = false` suppresses the dollar amounts while keeping token totals for comparison.

Flemma keeps the most recent notification available via `:Flemma notification:recall`, which helps when you close the floating window before capturing the numbers. Logging lives in the same subsystem: toggle it with `:Flemma logging:enable` / `:Flemma logging:disable` and open the log file (`~/.local/state/nvim/flemma.log` or your `stdpath("cache")`) through `:Flemma logging:open` whenever you need the redacted curl command and streaming trace.

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

### Line highlights

Full-line background colours distinguish message roles. Disable with `line_highlights.enabled = false` (default: `true`):

```lua
line_highlights = {
  enabled = true,
  user = { dark = "Normal+bg:#101010", light = "Normal-bg:#101010" },
  assistant = { dark = "Normal+bg:#102020", light = "Normal-bg:#102020" },
  -- ...
}
```

</details>

Role markers inherit `role_style` (comma-separated GUI attributes) so marker styling tracks your message colours.

### Sign column indicators

Set `signs.enabled = true` to place signs for each message line. Each role (`system`, `user`, `assistant`) can override the character and highlight. Signs default to using the message highlight colour.

### Spinner behaviour

While a request runs Flemma appends `@Assistant: Thinking...` with an animated braille spinner. The line is flagged as non-spellable so spell check integrations stay quiet. Once streaming starts, the spinner is removed and replaced with the streamed content.

---

## Lualine Integration

Add the bundled component to show the active model (and reasoning effort when set):

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

The component only renders in `chat` buffers. Switching providers or toggling OpenAI reasoning effort causes Flemma to refresh lualine automatically.

---

## Configuration Reference

Flemma works without arguments, but every option can be overridden:

```lua
require("flemma").setup({
  provider = "anthropic",
  model = nil, -- provider default
  parameters = {
    max_tokens = 4000,
    temperature = 0.7,
    timeout = 120,
    connect_timeout = 10,
    vertex = {
      project_id = nil,
      location = "global",
      thinking_budget = nil,
    },
    openai = {
      reasoning = nil, -- "low" | "medium" | "high"
    },
  },
  presets = {},
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
    thinking_block = "Comment",
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
  line_highlights = {
    enabled = true,
    frontmatter = { dark = "Normal+bg:#201020", light = "Normal-bg:#201020" },
    system = { dark = "Normal+bg:#201000", light = "Normal-bg:#201000" },
    user = { dark = "Normal", light = "Normal" },
    assistant = { dark = "Normal+bg:#102020", light = "Normal-bg:#102020" },
  },
  notify = require("flemma.notify").default_opts,
  pricing = { enabled = true },
  text_object = "m",
  editing = {
    disable_textwidth = true,
    auto_write = false,
  },
  logging = {
    enabled = false,
    path = vim.fn.stdpath("cache") .. "/flemma.log",
  },
  keymaps = {
    enabled = true,
    normal = {
      send = "<C-]>",
      cancel = "<C-c>",
      next_message = "]m",
      prev_message = "[m",
    },
    insert = {
      send = "<C-]>",
    },
  },
})
```

Additional notes:

- `editing.auto_write = true` writes the buffer after each successful request or cancellation.
- Set `text_object = false` to disable the message text object entirely.
- `notify.default_opts` exposes floating-window appearance (timeout, width, border, title).
- `logging.enabled = true` starts the session with logging already active.

---

## Importing from Claude Workbench

<details>
<summary><strong>Quick steps</strong> – Export the TypeScript snippet in Claude Workbench, paste it into Neovim, then run <code>:Flemma import</code>.</summary>

Flemma can turn Claude Workbench exports into ready-to-send `.chat` buffers. Follow the short checklist above when you only need a reminder; the full walkthrough below explains each step and the safeguards in place.

**Before you start**

- `:Flemma import` delegates to the current provider. Keep Anthropic active (`:Flemma switch anthropic`) so the importer knows how to interpret the snippet.
- Use an empty scratch buffer – `Flemma import` overwrites the entire buffer with the converted chat.

**Export from Claude Workbench**

1. Navigate to <https://console.anthropic.com/workbench> and open the saved prompt you want to migrate.
2. Click **Get code** in the top-right corner, then switch the language dropdown to **TypeScript**. The importer expects the `anthropic.messages.create({ ... })` call produced by that export.
3. Press **Copy code**; Claude Workbench copies the whole TypeScript example (including the `import Anthropic from "@anthropic-ai/sdk"` header).

**Convert inside Neovim**

1. In Neovim, paste the snippet into a new buffer (or delete any existing text first).
2. Run `:Flemma import`. The command:
   - Scans the buffer for `anthropic.messages.create(...)`.
   - Normalises the JavaScript object syntax and decodes it as JSON.
   - Emits a system message (if present) and rewrites every Workbench message as `@You:` / `@Assistant:` lines.
   - Switches the buffer's filetype to `chat` so folds, highlights, and keymaps activate immediately.

**Troubleshooting**

- If the snippet does not contain an `anthropic.messages.create` call, the importer aborts with "No Anthropic API call found".
- JSON decoding errors write both the original snippet and the cleaned JSON to `flemma_import_debug.log` in your temporary directory (e.g. `/tmp/flemma_import_debug.log`). Open that file to spot mismatched brackets or truncated copies.
- Nothing happens? Confirm Anthropic is the active provider – other providers currently do not ship an importer.

</details>

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

Run the automated tests with:

```bash
make test
```

The suite boots headless Neovim via `tests/minimal_init.lua` and executes Plenary+Busted specs in `tests/flemma/`, printing detailed results for each spec so you can follow along.

To exercise the plugin without installing it globally:

```bash
nvim --cmd "set runtimepath+=`pwd`" \
  -c 'lua require("flemma").setup({})' \
  -c ':edit scratch.chat'
```

> [!NOTE]
> **Almost every line of code** in Flemma has been authored through AI pair-programming tools (Aider, Amp, and Codex). Traditional contributions are welcome – just keep changes focused, documented, and tested.

---

## Troubleshooting Checklist

- **Nothing happens when I send:** confirm the buffer name ends with `.chat` and the first message starts with `@You:` or `@System:`.
- **Frontmatter errors:** notifications list the exact line and file. Fix the error and resend; Flemma will not contact the provider until the frontmatter parses cleanly.
- **Attachments ignored:** ensure the file exists relative to the `.chat` file and that the provider supports its MIME type. Use `;type=` to override when necessary.
- **Vertex refuses requests:** double-check `parameters.vertex.project_id` and authentication. Run `gcloud auth application-default print-access-token` manually to ensure credentials are valid.
- **Keymaps clash:** disable built-in mappings via `keymaps.enabled = false` and register your own `:Flemma` commands.

Happy prompting!
