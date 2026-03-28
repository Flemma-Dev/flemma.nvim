<h1><img src="https://images.weserv.nl/?url=avatars.githubusercontent.com%2Fu%2F231013899%3Fs%3D400%26v%3D4&mask=circle" width="38" height="38" valign="bottom" alt="Flemma's logo"> Flemma</h1>

> [!IMPORTANT]
> **Actively Evolving.** [See the roadmap](ROADMAP.md) for what's coming next.
>
> Flemma is growing fast – new tools, providers, and UI features land regularly. Expect occasional breaking changes while the project matures. Pin a commit if you need a stable target.

Flemma turns Neovim into an AI agent. Give it a task, and it works – calling tools, reading and editing files, running shell commands, and re-sending results back to the model in a fully autonomous loop. You stay in control: every action is visible in the `.chat` buffer, every tool call can require your approval, and you can take the wheel at any point. But when you trust the model, Flemma gets out of the way and lets it drive.

Streaming conversations, reusable prompt templates, file attachments, cost tracking, and ergonomic commands for Anthropic, OpenAI, Google Vertex AI, and Moonshot AI.

https://github.com/user-attachments/assets/87b09499-e1f8-4f76-bc06-be73bb7ade63

- **Autonomous agent loop** – Flemma executes approved tool calls and re-sends results automatically, repeating until the task is done or your approval is needed. One keypress can kick off an entire multi-step workflow.
- **Tool calling** – bash, file read/edit/write, with approval policies, parallel execution, and inline previews that show what each tool will do before you approve it. Register your own tools, approval resolvers, and preview formatters.
- **User at the wheel** – every tool call is visible in the buffer with a preview of what it will do. Approve tools one at a time with <kbd>Alt-Enter</kbd>, bulk-approve with <kbd>Ctrl-]</kbd>, or let autopilot handle everything. Pause, inspect, edit, resume at any point.
- **Multi-provider** – Anthropic, OpenAI, Vertex AI, and Moonshot AI through one unified interface.
- **Extended thinking** – unified `thinking` parameter across all providers, with automatic mapping to Anthropic budgets, OpenAI reasoning effort, and Vertex thinking budgets.
- **Template system** – Lua/JSON frontmatter, inline `{{ expressions }}`, `{% code %}` blocks, `include()` helpers. JSON frontmatter supports MongoDB-style operators for declarative per-buffer config overrides. Frontmatter changes take effect immediately as you edit.
- **Context attachments** – reference local files with `@./path`; MIME detection and provider-aware formatting.
- **Usage reporting** – per-request and session token totals, costs, and cache metrics.
- **Filesystem sandboxing** – shell commands run inside a read-only rootfs with write access limited to your project directory. Limits the blast radius of common accidents. Auto-detects the best available backend; silently degrades on platforms without one.
- **Git-trackable conversations** – `.chat` files are plain text. Commit them, diff them, branch them, share them. No opaque database, no export step – your conversation history lives in version control the moment you save.
- **Theme-aware UI** – line highlights, rulers, turn indicators, tool previews, and folding that adapt to your colour scheme.
- **In-editor LSP** – an experimental in-process LSP provides hover information on buffer elements (messages, segments, tool blocks) and go-to-definition for file references. Enabled by default when `vim.lsp` is available.

## Table of Contents

- [Installation](#installation)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [The Buffer Is the State](#the-buffer-is-the-state)
- [Understanding `.chat` Buffers](#understanding-chat-buffers)
- [Commands and Provider Management](#commands-and-provider-management)
- [Providers](#providers)
- [Tool Calling](#tool-calling)
- [Autopilot](#autopilot)
- [Sandboxing](#sandboxing)
- [Template System](#template-system)
- [Usage, Pricing, and Notifications](#usage-pricing-and-notifications)
- [UI Customisation](#ui-customisation)
- [Extending Flemma](#extending-flemma)
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
| [`bwrap`](https://github.com/containers/bubblewrap) (optional, Linux)    | Enables filesystem sandboxing for tool execution. Without it, tools run unsandboxed.                            |

### Provider credentials

| Provider         | Environment variable                                        | Notes                                                       |
| ---------------- | ----------------------------------------------------------- | ----------------------------------------------------------- |
| Anthropic        | `ANTHROPIC_API_KEY`                                         |                                                             |
| OpenAI           | `OPENAI_API_KEY`                                            | Supports GPT-5 family, including reasoning effort settings. |
| Google Vertex AI | `VERTEX_AI_ACCESS_TOKEN` **or** service-account credentials | Requires additional configuration (see below).              |
| Moonshot AI      | `MOONSHOT_API_KEY`                                          | Kimi models with optional thinking support.                 |

Flemma resolves credentials through a priority-based chain: environment variables are checked first, then platform keyring (Linux Secret Service or macOS Keychain), then `gcloud` CLI for Vertex AI access tokens. The first resolver that finds a credential wins. Credentials are cached with TTL awareness to avoid repeated lookups. When resolution fails, each resolver reports why it couldn't help — the notification lists every resolver that was tried and what went wrong (e.g., "ANTHROPIC_API_KEY not set", "secret-tool not found"). The `gcloud` binary path is configurable via `secrets.gcloud.path` for non-standard installations. See [docs/extending.md](docs/extending.md#credential-resolution) for details on the resolution chain and registering custom resolvers.

<details>
<summary><strong>Linux keyring setup (Secret Service)</strong></summary>

When environment variables are absent Flemma looks for secrets in the Secret Service keyring. Store them once and every Neovim instance can reuse them:

```bash
secret-tool store --label="Anthropic API Key" service anthropic key api
secret-tool store --label="OpenAI API Key" service openai key api
secret-tool store --label="Vertex AI Service Account" service vertex key api project_id your-gcp-project
secret-tool store --label="Moonshot API Key" service moonshot key api
```

</details>

<details>
<summary><strong>Vertex AI service-account flow</strong></summary>

1. Create a service account in Google Cloud and grant it the _Vertex AI user_ role.
2. Download its JSON credentials and either:
   - export them via `VERTEX_SERVICE_ACCOUNT='{"type": "..."}'`, **or**
   - store them in the Secret Service entry above (the JSON is stored verbatim).
3. Ensure the Google Cloud CLI is on your `$PATH`; Flemma shells out to `gcloud auth print-access-token` whenever it needs to refresh the token.
4. Set the project/location in configuration or via `:Flemma switch vertex gemini-3.1-pro-preview project_id=my-project location=us-central1`.

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
   @You:
   Turn the notes below into a short project update.

   - Added Vertex thinking budget support.
   - Refactored :Flemma command routing.
   - Documented presets in the README.
   ```

4. Press <kbd>Ctrl-]</kbd> (normal or insert mode) or run `:Flemma send`. Flemma freezes the buffer while the request is streaming and shows a spinner on the `@Assistant:` line. With [autopilot](#autopilot) enabled (the default), tool calls are executed and re-sent automatically – you only need to intervene when a tool requires manual approval.
5. When the reply finishes, a floating notification lists token counts and cost for the request and the session.

Cancel an in-flight response with <kbd>Ctrl-C</kbd> or `:Flemma cancel`.

---

## The Buffer Is the State

Most AI tools keep the real conversation hidden – in a SQLite file or a JSON log you can't touch. **Flemma doesn't.** The `.chat` buffer **is** the conversation and nothing exists outside it. Everything the model receives is derived from what is written in the buffer – no hidden context, no server-side session, no state accumulating behind the scenes.

That difference matters more than it sounds. In most AI tools, interrupting an agent mid-task is a gamble – you might need to coax it to resume, or lose context entirely. Rewinding is a one-way street with no way back. In Flemma, the conversation is a buffer and you have Vim! Interrupt a response and re-send – the model picks up exactly where the buffer says. Edit an assistant message to fix a hallucination, delete a tangent, rewrite your prompt – there is no shadow state to fall out of sync. Undo, redo, walk the undo tree. Fork a conversation by duplicating the file. Track every version with Git. Switch from Claude to GPT mid-conversation, or turn thinking on for one turn and off for the next. It's all just text in a buffer you control.

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

@System:
You turn engineering notes into concise changelog entries.

@You:
Summarise {{release.version}} with emphasis on {{release.focus}} using the points below:
{{notes}}

@Assistant:

- Changelog bullets...
- Follow-up actions...

<thinking>
Model thoughts stream here and auto-fold.
</thinking>
````

- **Frontmatter** sits on the first line and must be fenced with triple backticks. Lua and JSON parsers ship with Flemma; you can register more via `flemma.codeblock.parsers.register("yaml", parser_fn)`. Lua frontmatter exposes `flemma.opt` for [per-buffer tool selection, approval, and provider parameter overrides](docs/tools.md#per-buffer-tool-selection). JSON frontmatter supports equivalent overrides through a `flemma` key with [MongoDB-style operators](docs/templates.md#json-frontmatter-with-config-operators) (`$set`, `$append`, `$remove`, `$prepend`). Frontmatter is re-evaluated automatically as you edit, so changes take effect in the statusline immediately without sending.
- **Messages** begin with `@System:`, `@You:`, or `@Assistant:` on their own line. Content starts on the next line. Typing `:` after a role name in insert mode auto-completes the marker and moves the cursor to the content line.
- **Thinking blocks** appear only in assistant messages. When thinking is enabled (default `"high"`), Anthropic and Vertex AI models stream `<thinking>` sections; Flemma folds them automatically and keeps dedicated highlights for the tags and body.

> [!NOTE]
> **Cross-provider thinking.** When you switch providers mid-conversation, thinking blocks from the previous provider are visible in the buffer but are **not forwarded** to the new provider's API. The visible text inside `<thinking>` tags is a summary for your reference; the actual reasoning data lives in provider-specific signature attributes on the tag. Only matching-provider signatures are replayed.

### Folding and layout

| Fold level | What folds                 | Why                                                             |
| ---------- | -------------------------- | --------------------------------------------------------------- |
| Level 2    | The frontmatter block      | Keep templates out of the way while you focus on chat history.  |
| Level 2    | `<thinking>...</thinking>` | Reasoning traces are useful, but often secondary to the answer. |
| Level 1    | Each message               | Collapse long exchanges without losing context.                 |

Press `<Space>` to toggle the current message fold — it always operates on the entire role, regardless of cursor position within the message. Nested folds (thinking blocks, tool calls) are closed along the way so the message reopens cleanly. Use `za` to toggle individual folds under the cursor (thinking blocks, tool results, etc.). The fold text shows a snippet of the hidden content so you know whether to expand it. The initial fold level is configurable via `editing.foldlevel` (default `1`, which collapses thinking blocks). The `<Space>` binding is automatically skipped when it conflicts with your `mapleader`.

Flemma draws a ruler on each role marker line using the configured `ruler.char` and highlight, visually separating messages without consuming extra vertical space.

### Navigation and text objects

Inside `.chat` buffers Flemma defines:

- `<Space>` – toggle the current message fold (automatically skipped when `<Space>` is your `mapleader`). Always targets the entire role, not the fold under the cursor — use `za` for that.
- `]m` / `[m` – jump to the next/previous message header.
- `im` / `am` (configurable) – select the inside or entire message as a text object. `am` selects linewise and includes thinking blocks and trailing blank lines, making `dam` delete entire conversation turns. `im` skips `<thinking>` sections so yanking `im` never includes reasoning traces.
- `gf` on `@./path` file references and `include()` expressions opens the referenced file. Flemma evaluates the expression to resolve the actual path, so `gf` works even on computed includes.
- Buffer-local mappings for send/cancel default to `<C-]>` and `<C-c>` in normal mode. `<C-]>` is a hybrid key with three phases: inject approval placeholders, execute approved tools, send the conversation. `<M-CR>` (Alt-Enter) executes the single tool under the cursor – useful for stepping through pending tools one at a time. Insert-mode `<C-]>` behaves identically to normal mode but re-enters insert when the operation finishes.

Disable or remap these through the `keymaps` section (see [Configuration Reference](#configuration-reference)).

---

## Commands and Provider Management

Use the single entry point `:Flemma {command}`. Autocompletion lists every available sub-command.

| Command                                                              | Purpose                                                                                                                                                                                                 | Example                                                                     |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `:Flemma status [verbose]`                                           | Show runtime status in a structured tree with config layer source indicators (D=defaults, S=setup, R=runtime, F=frontmatter). `verbose` appends per-layer operations and the full resolved config tree. | `:Flemma status verbose`                                                    |
| `:Flemma send [key=value ...]`                                       | Send the current buffer. Optional callbacks run before/after the request.                                                                                                                               | `:Flemma send on_request_start=stopinsert on_request_complete=startinsert!` |
| `:Flemma cancel`                                                     | Abort the active request and clean up the spinner.                                                                                                                                                      |                                                                             |
| `:Flemma switch ...`                                                 | Choose or override provider/model parameters.                                                                                                                                                           | See below.                                                                  |
| `:Flemma format`                                                     | Migrate old inline-format `.chat` buffers to the current own-line role marker format.                                                                                                                   |
| `:Flemma import`                                                     | Convert Claude Workbench code snippets into `.chat` format ([guide](docs/importing.md)).                                                                                                                |                                                                             |
| `:Flemma message:next` / `:Flemma message:previous` (or `:...:prev`) | Jump through message headers.                                                                                                                                                                           |                                                                             |
| `:Flemma tool:execute`                                               | Execute the tool at the cursor position.                                                                                                                                                                |                                                                             |
| `:Flemma tool:cancel`                                                | Cancel the tool execution at the cursor.                                                                                                                                                                |                                                                             |
| `:Flemma tool:cancel-all`                                            | Cancel all pending tool executions in the buffer.                                                                                                                                                       |                                                                             |
| `:Flemma tool:list`                                                  | List pending tool executions with IDs and elapsed time.                                                                                                                                                 |                                                                             |
| `:Flemma autopilot:enable` / `:...:disable` / `:...:status`          | Toggle autopilot or view its state (status opens the full status buffer).                                                                                                                               |                                                                             |
| `:Flemma sandbox:enable` / `:...:disable` / `:...:status`            | Toggle sandboxing or view its state (status opens the full status buffer).                                                                                                                              |                                                                             |
| `:Flemma logging:enable [level]` / `:...:disable` / `:...:open`      | Toggle structured logging and open the log file. Optional level: `TRACE`, `DEBUG` (default), `INFO`, `WARN`, `ERROR`.                                                                                   |                                                                             |
| `:Flemma diagnostics:enable` / `:...:disable` / `:...:diff`          | Toggle request diagnostics or view a diff of the last API request/response. Useful for debugging prompt caching.                                                                                        |                                                                             |
| `:Flemma ast:diff`                                                   | Open a side-by-side diff of the raw and rewritten ASTs, scrolled to the node under the cursor. Useful for debugging preprocessor rewriters.                                                             |                                                                             |
| `:Flemma notification:recall`                                        | Reopen the last usage/cost notification.                                                                                                                                                                |                                                                             |

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
      model = "claude-sonnet-4-6",
      max_tokens = 6000,
    },
  },
})
```

Switch using `:Flemma switch $fast` or `:Flemma switch $review temperature=0.1` to override individual values.

---

## Providers

### Unified thinking

All supported providers offer extended thinking/reasoning. Flemma provides a single `thinking` parameter that maps automatically to each provider's native format:

| `thinking` value       | Anthropic (budget) | OpenAI (effort)      | Vertex AI (budget) | Moonshot (toggle) |
| ---------------------- | ------------------ | -------------------- | ------------------ | ----------------- |
| `"max"`                | model-dependent\*  | `"max"` effort       | 32,768 tokens      | enabled†          |
| `"high"` **(default)** | 16,384 tokens      | `"high"` effort      | 32,768 tokens      | enabled†          |
| `"medium"`             | 8,192 tokens       | `"medium"` effort    | 8,192 tokens       | enabled†          |
| `"low"`                | 2,048 tokens       | `"low"` effort       | 2,048 tokens       | enabled†          |
| `"minimal"`            | 1,024 tokens       | `"minimal"` effort   | 128 tokens         | enabled†          |
| number (e.g. `4096`)   | 4,096 tokens       | closest effort level | 4,096 tokens       | enabled†          |
| `false` or `0`         | disabled           | disabled             | disabled           | disabled†         |

\*Anthropic models with adaptive thinking (Opus 4.6) use the provider's native `"max"` effort level. Other Anthropic models map `"max"` to the highest available budget. Exact values are model-dependent – see the per-provider files under `lua/flemma/models/` for the full per-model catalogue.

†Moonshot thinking is binary (on/off) with no budget control. kimi-k2-thinking models always think regardless of the `thinking` setting. moonshot-v1-\* models do not support thinking.

Set it once in your config and it works everywhere:

```lua
require("flemma").setup({
  parameters = {
    thinking = "high",     -- default: all providers think at maximum
  },
})
```

Or override per-request with `:Flemma switch anthropic claude-sonnet-4-6 thinking=medium`.

**Priority order:** Provider-specific parameters (`thinking_budget` for Anthropic/Vertex, `reasoning` for OpenAI) take priority over the unified `thinking` parameter when both are set. Moonshot does not have a provider-specific override – the unified `thinking` parameter controls the toggle directly. This lets you use `thinking` as the default and override with provider-native syntax when needed.

When thinking is active, the Lualine component shows the resolved level – e.g., `claude-sonnet-4-6 (high)` or `o3 (medium)`.

### Provider-specific capabilities

| Provider    | Defaults                 | Extra parameters                                                                                                        | Notes                                                                                         |
| ----------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Anthropic   | `claude-sonnet-4-6`      | `thinking_budget` overrides the unified `thinking` parameter with an exact token budget (clamped to min 1,024).         | Supports text, image, and PDF attachments. Thinking blocks stream into the buffer.            |
| OpenAI      | `gpt-5.4`                | `reasoning` overrides the unified `thinking` parameter with an explicit effort level (`"low"`, `"medium"`, `"high"`).   | Cost notifications include reasoning tokens. Lualine shows the reasoning level.               |
| Vertex AI   | `gemini-3.1-pro-preview` | `project_id` (required), `location` (default `global`), `thinking_budget` overrides with an exact token budget (min 1). | `thinking_budget` overrides the unified `thinking` parameter for Vertex.                      |
| Moonshot AI | `kimi-k2.5`              | `prompt_cache_key` for stable prompt caching keys.                                                                      | kimi-k2-thinking models force thinking on. Temperature locked per thinking mode on kimi-k2.5. |

> [!NOTE]
> Defaults favour capability at a reasonable price point, **not minimum cost**. Older or smaller models (e.g., `gpt-5.2`, `gemini-2.5-flash`) can be significantly cheaper and may perform just as well for your workload; choosing the right cost/capability trade-off is up to you.

The full model catalogue (including pricing) lives in per-provider files under `lua/flemma/models/` (e.g., `lua/flemma/models/anthropic.lua`). You can inspect a provider's models from Neovim with:

```lua
:lua print(vim.inspect(require("flemma.models.anthropic")))
```

### Prompt caching

All supported providers offer prompt caching. Flemma handles breakpoint placement (Anthropic), cache keys (OpenAI), implicit caching (Vertex), and optional cache keys (Moonshot) automatically. The `cache_retention` parameter controls the strategy where applicable:

|               | Anthropic         | OpenAI                | Vertex AI   | Moonshot  |
| ------------- | ----------------- | --------------------- | ----------- | --------- |
| Default       | `"short"` (5 min) | `"short"` (in-memory) | Automatic   | Automatic |
| Min. tokens   | 1,024–4,096       | 1,024                 | 1,024–2,048 | —         |
| Read discount | 90%               | 50%                   | 90%         | 80%       |

When a cache hit occurs, the usage notification shows a `Cache:` line with read/write token counts. See [docs/prompt-caching.md](docs/prompt-caching.md) for provider-specific details, caveats, and pricing tables.

---

## Tool Calling

Flemma's tool system is what makes it an agent. Models can execute shell commands, read files, write files, and apply edits – and with [autopilot](#autopilot), the entire cycle is autonomous: call a tool, get the result, decide what to do next, call another tool, repeat.

### How it works

1. When you send a message, Flemma includes definitions for available tools in the API request.
2. If the model decides to use tools, it emits `**Tool Use:**` blocks in its response.
3. Flemma categorises each tool call against your approval settings: auto-approved tools execute immediately, while tools requiring review get `flemma:tool status=pending` placeholders with an inline preview showing what the tool will do.
4. The cursor moves to the first pending tool. Press <kbd>Alt-Enter</kbd> to execute it – the cursor advances to the next pending tool automatically. Repeat until all tools are resolved.
5. Once every tool has a result, [autopilot](#autopilot) re-sends the conversation and the cycle continues until the model is done or needs your input again.

The result is a fluid back-and-forth: the model proposes actions, you see exactly what each one does, approve them at your own pace, and autopilot picks up where you left off. One prompt can trigger an entire multi-step workflow without losing you in a wall of pending approvals.

With autopilot disabled, the flow is manual: press <kbd>Ctrl-]</kbd> to inject review placeholders, again to execute, and again to re-send.

### Built-in tools

| Tool    | Type  | Description                                                                                                         |
| ------- | ----- | ------------------------------------------------------------------------------------------------------------------- |
| `bash`  | async | Executes shell commands. Configurable shell, working directory, and environment. Supports timeout and cancellation. |
| `read`  | sync  | Reads file contents with optional offset and line limit. Relative paths resolve against the `.chat` file.           |
| `write` | sync  | Writes or creates files. Creates parent directories automatically.                                                  |
| `edit`  | sync  | Find-and-replace with exact text matching. The old text must appear exactly once in the target file.                |

By default, file and exploration operations (`read`, `write`, `edit`, `find`, `grep`, `ls`) are auto-approved via the `$standard` preset, while `bash` requires manual approval unless sandboxed – when the sandbox is enabled and `tools.auto_approve_sandboxed` is `true` (the default), sandboxed tools execute without manual approval (see [Sandboxing](#sandboxing)). Additional exploration tools (`grep`, `find`, `ls`) are available behind the `experimental.tools` flag (experimental and untested) – see [docs/tools.md](docs/tools.md#experimental-exploration-tools) for details. While a tool is pending, Flemma renders a virtual-line preview inside the placeholder showing the tool name and a formatted summary of its arguments – so you can see at a glance that `read` wants to do `read: checking config — src/config.lua +0,50` or that `bash` intends `bash: running tests — $ make test` — each preview shows a human-readable **label** (the LLM's stated intent, italic) and a **detail** (the raw command or path, dimmer), separated by an em-dash. Built-in tools ship with tailored preview formatters; custom tools can provide their own via `format_preview`.

When the model returns multiple tool calls, Flemma executes up to `tools.max_concurrent` (default 2) simultaneously and queues the rest. Set to `0` for unlimited concurrency.

The built-in presets (`$readonly`, `$standard`) cover common policies; define your own in `presets` and compose them freely in `auto_approve`. Override per-buffer via `flemma.opt.tools.auto_approve` in frontmatter, or set `tools.require_approval = false` to skip approval entirely. Register your own tools with `require("flemma.tools").register()` and extend the approval chain with custom resolvers for plugin-level security policies. See [docs/tools.md](docs/tools.md) for the full reference on approval presets, per-buffer configuration, custom tool registration, tool previews, and the resolver API.

---

## Autopilot

Autopilot is what turns Flemma from a chat interface into an autonomous agent. It is enabled by default.

When the model responds with tool calls, autopilot takes over: it executes every approved tool, collects the results, and re-sends the conversation – automatically, in a loop, until the model is done or needs your input. One prompt can trigger an entire multi-step workflow: the model reads files to understand a codebase, plans its approach, writes code, runs tests, reads the failures, fixes them, and re-runs – all from a single <kbd>Ctrl-]</kbd>.

When the model returns multiple tool calls and some require approval, autopilot pauses and places your cursor on the first pending tool. Each pending placeholder shows an inline preview of what the tool will do. Press <kbd>Alt-Enter</kbd> to approve and execute the tool under the cursor – the cursor then advances to the next pending tool. Once every tool has a result, autopilot resumes the loop automatically. This sequential flow keeps you in control without breaking your momentum: you review one tool at a time, at your own pace, and the conversation picks back up the moment you're done.

You are always in control. The entire conversation – every tool call, every result, every decision the model makes – is visible in the buffer. You can:

- **Let it run.** Auto-approve trusted tools (e.g., `read`) and let the model work autonomously.
- **Supervise.** Keep `require_approval = true` (the default) so autopilot pauses when a tool needs approval. Review the preview, press <kbd>Alt-Enter</kbd> to execute, and the loop resumes.
- **Intervene.** Press <kbd>Ctrl-C</kbd> at any point to stop everything. Edit the buffer. Change the model's plan. Then press <kbd>Ctrl-]</kbd> to continue.

### Safety

- **Turn limit:** A configurable safety cap (`tools.autopilot.max_turns`, default 100) stops the loop with a warning if exceeded, preventing runaway cost from models that loop without converging.
- **Cancellation:** <kbd>Ctrl-C</kbd> cancels the active request or tool execution and fully disarms autopilot – no surprises when you next press <kbd>Ctrl-]</kbd>.
- **Conflict detection:** If you edit the content inside an `approved` `flemma:tool` block, Flemma detects your changes, skips execution to protect your edits, and warns so you can review. For `pending` blocks, pasting content is treated as a user-provided result.

### Runtime control

Toggle autopilot at runtime without changing your config:

- `:Flemma autopilot:enable` – activate for the current session.
- `:Flemma autopilot:disable` – deactivate for the current session.
- `:Flemma autopilot:status` – open the status buffer and jump to the Autopilot section (shows enabled state, buffer loop state, max turns, and any frontmatter overrides).

To disable autopilot globally, set `tools.autopilot.enabled = false`. See [docs/configuration.md](docs/configuration.md) for the full option reference.

---

## Sandboxing

When sandboxing is enabled (the default), shell commands run inside a read-only filesystem with write access limited to your project directory, the `.chat` file directory, and `/tmp`. This prevents a misbehaving model from overwriting dotfiles, deleting system files, or writing outside the project. The sandbox is damage control, not a security boundary – it limits the blast radius of common accidents, not deliberate attacks.

Flemma auto-detects the best available backend. The built-in [Bubblewrap](https://github.com/containers/bubblewrap) backend works on Linux with the `bwrap` package installed. On platforms without a compatible backend, Flemma silently degrades to unsandboxed execution – no configuration changes needed.

```lua
-- The defaults work out of the box on Linux with bwrap installed.
-- Customise the policy to tighten or loosen restrictions:
require("flemma").setup({
  sandbox = {
    policy = {
      rw_paths = { "urn:flemma:cwd" },  -- only the project directory is writable
      network = false,                  -- no network access
    },
  },
})
```

Override per-buffer via `flemma.opt.sandbox` in frontmatter, or toggle at runtime with `:Flemma sandbox:enable/disable`. See [docs/sandbox.md](docs/sandbox.md) for the full reference on policy options, path variables, custom backends, and security considerations.

---

## Template System

Flemma's prompt pipeline supports Lua/JSON frontmatter, inline `{{ expressions }}`, `{% code %}` blocks for control flow and variable assignment, and an `include()` helper for composable prompts. Expressions degrade gracefully on error; code blocks fail the message with precise diagnostics. Whitespace trimming (`{%- -%}`, `{{- -}}`) keeps output clean. Embed local files with `@./path` syntax -- Flemma detects MIME types and formats attachments per-provider. File references are tracked for content drift: if a referenced file changes between requests, Flemma warns you so the model works with up-to-date context. See [docs/templates.md](docs/templates.md) for the full reference.

---

## Usage, Pricing, and Notifications

Each completed request emits a floating report that names the provider/model, lists input/output tokens (reasoning tokens are counted under `thoughts`), and – when pricing is enabled – shows the per-request and cumulative session cost derived from the per-provider model data under `lua/flemma/models/`. When prompt caching is active, a `Cache:` line shows read and write token counts. Token accounting persists for the lifetime of the Neovim instance; call `require("flemma.session").get():reset()` to zero the counters without restarting. `pricing.enabled = false` suppresses the dollar amounts while keeping token totals.

Notifications are buffer-local – each `.chat` buffer gets its own notification stack, positioned relative to its window. Notifications for hidden buffers are queued and shown when the buffer becomes visible. Recall the most recent notification with `:Flemma notification:recall`.

For programmatic access to token usage and cost data, see [docs/session-api.md](docs/session-api.md).

---

## UI Customisation

Flemma adapts to your colour scheme with theme-aware highlights, line backgrounds, rulers, turn indicators, and folding. Every visual element is configurable – see [docs/ui.md](docs/ui.md) for the full reference.

A progress bar floats alongside the assistant's response while streaming, showing the current phase (thinking, text, tool input). Thinking blocks, tool use, and tool results auto-close (fold) when they finish, keeping the buffer tidy – configure per block type via `editing.auto_close`.

Flemma ships optional [plugin integrations](docs/integrations.md) for lualine (statusline component) and bufferline (busy tab indicator).

---

## Extending Flemma

Flemma is designed to be extended. Hooks, custom tools, approval resolvers, sandbox backends, credential resolvers, template populators, and personalities are all pluggable through registry patterns. See [docs/extending.md](docs/extending.md) for the full guide, including:

- **Hooks** – lifecycle events (`FlemmaRequestSending`, `FlemmaToolExecuting`, etc.) emitted as User autocmds. Listen with standard `vim.api.nvim_create_autocmd` to build integrations.
- **Credential resolution** – pluggable resolver chain for API keys and tokens (environment variables, Linux keyring, macOS Keychain, gcloud CLI). Register custom resolvers for vault integrations or team-specific credential stores. When resolution fails, every resolver reports why it couldn't help.
- **Template system** – Lua/JSON frontmatter, inline `{{ expressions }}`, `{% code %}` blocks, `include()` helpers, and [JSON frontmatter operators](docs/templates.md#json-frontmatter-with-config-operators) (`$set`, `$append`, `$remove`, `$prepend`) for declarative per-buffer config overrides. See [docs/templates.md](docs/templates.md).
- **Template extensibility** – register custom environment populators via `templating.modules` to add globals to `{{ }}` and `{% %}` expressions, or register custom frontmatter parsers (e.g., YAML). See [docs/templates.md](docs/templates.md#extending-the-environment).
- **Custom tools** – register your own tool definitions with `require("flemma.tools").register()`. See [docs/tools.md](docs/tools.md#registering-custom-tools).
- **Approval resolvers** – priority-based chain for tool approval policies. See [docs/tools.md](docs/tools.md#approval-resolvers).
- **Sandbox backends** – add platform-specific sandboxing beyond Bubblewrap. See [docs/sandbox.md](docs/sandbox.md#custom-backends).
- **Personalities** – dynamic system prompt generators. See [docs/personalities.md](docs/personalities.md).

---

## Configuration Reference

Flemma works without arguments – `require("flemma").setup({})` uses sensible defaults (Anthropic provider, `thinking = "high"`, prompt caching enabled). Every option is documented with inline comments in the [full configuration reference](docs/configuration.md).

Key defaults:

| Parameter         | Default       | Description                                                   |
| ----------------- | ------------- | ------------------------------------------------------------- |
| `provider`        | `"anthropic"` | `"anthropic"` / `"openai"` / `"vertex"` / `"moonshot"`        |
| `thinking`        | `"high"`      | Unified thinking level across providers                       |
| `cache_retention` | `"short"`     | Prompt caching strategy                                       |
| `max_tokens`      | `"50%"`       | Maximum response tokens (percentage of model max, or integer) |
| `temperature`     | _(unset)_     | Sampling temperature; omitted unless explicitly set           |

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

Run all quality gates (luacheck, type checking, import conventions, tests) with a single command:

```bash
make qa
```

`make qa` runs all four gates in parallel and bails on the first failure, re-displaying only the failed gate's output. This is the single command to run before committing.

Other Makefile targets:

```bash
make develop       # Launch Neovim with Flemma loaded for local testing
make changeset     # Create a new changeset (interactive)
make screencast    # Create a VHS screencast
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

With autopilot and built-in tools (bash, file read/write/edit), Flemma is a fully autonomous coding agent that lives inside your editor. Give it a task – "refactor this module", "add tests for the auth flow", "find and fix the bug in checkout" – and watch it work: reading files, planning changes, writing code, running tests, iterating on failures. You stay in Neovim the whole time, with full visibility into every step. Flemma is not trying to replace dedicated agents like Claude Code or Codex, but it gives you an agent that speaks your language – Vim buffers, not a separate terminal.

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

- **Nothing happens when I send:** confirm the buffer name ends with `.chat` and the first message uses a role marker (`@You:` or `@System:`) on its own line with content below it.
- **Frontmatter errors:** notifications list the exact line and file. Fix the error and resend; Flemma will not contact the provider until the frontmatter parses cleanly. Frontmatter diagnostics also appear in `:Flemma status`.
- **Misspelled command or tool name:** Flemma suggests the closest match — e.g., `Unknown command 'staus'. Did you mean 'status'?`. This applies to `:Flemma` sub-commands, tool names in `flemma.opt.tools`, and tool names in `auto_approve`.
- **Attachments ignored:** ensure the file exists relative to the `.chat` file and that the provider supports its MIME type. Use `;type=` to override when necessary.
- **Temperature ignored:** when thinking is enabled (default `"high"`), Anthropic and OpenAI disable temperature (this is an API requirement, not a Flemma choice). Vertex AI passes temperature regardless. Moonshot locks temperature per thinking mode (1.0 when thinking, 0.6 when not on kimi-k2.5). Set `thinking = false` if you need temperature control on Anthropic/OpenAI.
- **Vertex refuses requests:** double-check `parameters.vertex.project_id` and authentication. Run `gcloud auth print-access-token` manually to ensure credentials are valid.
- **Tool execution doesn't respond:** make sure the cursor is on or near the `**Tool Use:**` block. Only tools with registered executors can be run – check `:lua print(vim.inspect(require("flemma.tools").get_all()))`.
- **Keymaps clash:** disable built-in mappings via `keymaps.enabled = false` and register your own `:Flemma` commands.
- **Sandbox blocks writes:** If a tool reports "permission denied" on a path you expect to be writable, run `:Flemma status` (or `:Flemma sandbox:status`) and verify the path is inside `rw_paths`. Add it to `sandbox.policy.rw_paths` or disable sandboxing to troubleshoot.
- **Cross-buffer issues:** Flemma manages state per-buffer. If something feels off after switching between multiple `.chat` buffers, ensure each buffer has been saved (unsaved buffers lack `__dirname` for path resolution).

## License

Flemma is licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0).

Happy prompting!
