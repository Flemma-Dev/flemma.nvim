# Flemma 🪶

> [!CAUTION]
> **Actively Evolving**
>
> Flemma is growing fast – new tools, providers, and UI features land regularly. Expect occasional breaking changes while the project matures. Pin a commit if you need a steady target.

Flemma turns Neovim into an AI agent. Give it a task, and it works – calling tools, reading and editing files, running shell commands, and re-sending results back to the model in a fully autonomous loop. You stay in control: every action is visible in the `.chat` buffer, every tool call can require your approval, and you can take the wheel at any point. But when you trust the model, Flemma gets out of the way and lets it drive.

Streaming conversations, reusable prompt templates, file attachments, cost tracking, and ergonomic commands for Anthropic, OpenAI, and Google Vertex AI.

https://github.com/user-attachments/assets/2c688830-baef-4d1d-98ef-ae560faacf61

- **Autonomous agent loop** – Flemma executes approved tool calls and re-sends results automatically, repeating until the task is done or your approval is needed. One keypress can kick off an entire multi-step workflow.
- **Tool calling** – bash, file read/edit/write, with approval policies and parallel execution. Register your own tools and approval resolvers.
- **User at the wheel** – every tool call is visible in the buffer. Require approval globally, per-tool, or per-buffer. Pause, inspect, edit, resume – or let autopilot handle everything.
- **Multi-provider** – Anthropic, OpenAI, and Vertex AI through one unified interface.
- **Extended thinking** – unified `thinking` parameter across all providers, with automatic mapping to Anthropic budgets, OpenAI reasoning effort, and Vertex thinking budgets.
- **Template system** – Lua/JSON frontmatter, inline `{{ expressions }}`, `include()` helpers.
- **Context attachments** – reference local files with `@./path`; MIME detection and provider-aware formatting.
- **Usage reporting** – per-request and session token totals, costs, and cache metrics.
- **Filesystem sandboxing** – shell commands run inside a read-only rootfs with write access limited to your project directory. Limits the blast radius of common accidents. Auto-detects the best available backend; silently degrades on platforms without one.
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
- [Autopilot](#autopilot)
- [Sandboxing](#sandboxing)
- [Template System](#template-system)
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
| [`bwrap`](https://github.com/containers/bubblewrap) (optional, Linux)    | Enables filesystem sandboxing for tool execution. Without it, tools run unsandboxed.                            |

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

4. Press <kbd>Ctrl-]</kbd> (normal or insert mode) or run `:Flemma send`. Flemma freezes the buffer while the request is streaming and shows `@Assistant: Thinking...`. With [autopilot](#autopilot) enabled (the default), tool calls are executed and re-sent automatically – you only need to intervene when a tool requires manual approval.
5. When the reply finishes, a floating notification lists token counts and cost for the request and the session.

Cancel an in-flight response with <kbd>Ctrl-C</kbd> or `:Flemma cancel`.

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

- **Frontmatter** sits on the first line and must be fenced with triple backticks. Lua and JSON parsers ship with Flemma; you can register more via `flemma.codeblock.parsers.register("yaml", parser_fn)`. Lua frontmatter also exposes `flemma.opt` for [per-buffer tool selection, approval, and provider parameter overrides](docs/tools.md#per-buffer-tool-selection).
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

| Command                                                     | Purpose                                                                                                                                                  | Example                                                                     |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `:Flemma status [verbose]`                                  | Show runtime status (provider, parameters, autopilot, sandbox, tools) in a scratch buffer. `verbose` appends the full config dump with Lua highlighting. | `:Flemma status verbose`                                                    |
| `:Flemma send [key=value ...]`                              | Send the current buffer. Optional callbacks run before/after the request.                                                                                | `:Flemma send on_request_start=stopinsert on_request_complete=startinsert!` |
| `:Flemma cancel`                                            | Abort the active request and clean up the spinner.                                                                                                       |                                                                             |
| `:Flemma switch ...`                                        | Choose or override provider/model parameters.                                                                                                            | See below.                                                                  |
| `:Flemma import`                                            | Convert Claude Workbench code snippets into `.chat` format ([guide](docs/importing.md)).                                                                 |                                                                             |
| `:Flemma message:next` / `:Flemma message:previous`         | Jump through message headers.                                                                                                                            |                                                                             |
| `:Flemma tool:execute`                                      | Execute the tool at the cursor position.                                                                                                                 |                                                                             |
| `:Flemma tool:cancel`                                       | Cancel the tool execution at the cursor.                                                                                                                 |                                                                             |
| `:Flemma tool:cancel-all`                                   | Cancel all pending tool executions in the buffer.                                                                                                        |                                                                             |
| `:Flemma tool:list`                                         | List pending tool executions with IDs and elapsed time.                                                                                                  |                                                                             |
| `:Flemma autopilot:enable` / `:...:disable` / `:...:status` | Toggle autopilot or view its state (status opens the full status buffer).                                                                                |                                                                             |
| `:Flemma sandbox:enable` / `:...:disable` / `:...:status`   | Toggle sandboxing or view its state (status opens the full status buffer).                                                                               |                                                                             |
| `:Flemma logging:enable` / `:...:disable` / `:...:open`     | Toggle structured logging and open the log file.                                                                                                         |                                                                             |
| `:Flemma notification:recall`                               | Reopen the last usage/cost notification.                                                                                                                 |                                                                             |

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

When thinking is active, the Lualine component shows the resolved level – e.g., `claude-sonnet-4-5 (high)` or `o3 (medium)`.

### Provider-specific capabilities

| Provider  | Defaults            | Extra parameters                                                                                                        | Notes                                                                              |
| --------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Anthropic | `claude-sonnet-4-5` | `thinking_budget` overrides the unified `thinking` parameter with an exact token budget (clamped to min 1,024).         | Supports text, image, and PDF attachments. Thinking blocks stream into the buffer. |
| OpenAI    | `gpt-5`             | `reasoning` overrides the unified `thinking` parameter with an explicit effort level (`"low"`, `"medium"`, `"high"`).   | Cost notifications include reasoning tokens. Lualine shows the reasoning level.    |
| Vertex AI | `gemini-2.5-pro`    | `project_id` (required), `location` (default `global`), `thinking_budget` overrides with an exact token budget (min 1). | `thinking_budget` overrides the unified `thinking` parameter for Vertex.           |

The full model catalogue (including pricing) is in `lua/flemma/models.lua`. You can access it from Neovim with:

```lua
:lua print(vim.inspect(require("flemma.models")))
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

Flemma's tool system is what makes it an agent. Models can execute shell commands, read files, write files, and apply edits – and with [autopilot](#autopilot), the entire cycle is autonomous: call a tool, get the result, decide what to do next, call another tool, repeat.

### How it works

1. When you send a message, Flemma includes definitions for available tools in the API request.
2. If the model decides to use a tool, it emits a `**Tool Use:**` block in its response.
3. With [autopilot](#autopilot) enabled (the default), approved tools execute automatically and the conversation re-sends until the model stops calling tools or a tool requires your approval.
4. When a tool needs approval, Flemma injects a `flemma:tool status=pending` placeholder and pauses. Press <kbd>Ctrl-]</kbd> to approve and resume.

A single <kbd>Ctrl-]</kbd> can kick off a chain of dozens of tool calls – the model reads a codebase, plans changes, edits files, runs tests, and iterates on failures, all without further input. You watch it happen in real time in the buffer.

With autopilot disabled, the flow is manual: press <kbd>Ctrl-]</kbd> to inject review placeholders, again to execute, and again to re-send.

### Built-in tools

| Tool    | Type  | Description                                                                                                         |
| ------- | ----- | ------------------------------------------------------------------------------------------------------------------- |
| `bash`  | async | Executes shell commands. Configurable shell, working directory, and environment. Supports timeout and cancellation. |
| `read`  | sync  | Reads file contents with optional offset and line limit. Relative paths resolve against the `.chat` file.           |
| `write` | sync  | Writes or creates files. Creates parent directories automatically.                                                  |
| `edit`  | sync  | Find-and-replace with exact text matching. The old text must appear exactly once in the target file.                |

By default, every tool call requires your approval before execution – <kbd>Ctrl-]</kbd> injects review placeholders first, then executes on a second press. Whitelist safe tools globally with `tools.auto_approve = { "read" }`, or per-buffer via `flemma.opt.tools.auto_approve` in frontmatter. Set `tools.require_approval = false` to skip approval entirely. You can also register your own tools with `require("flemma.tools").register()` and extend the approval chain with custom resolvers for plugin-level security policies. See [docs/tools.md](docs/tools.md) for the full reference on approval, per-buffer configuration, custom tool registration, and the resolver API.

---

## Autopilot

Autopilot is what turns Flemma from a chat interface into an autonomous agent. It is enabled by default.

When the model responds with tool calls, autopilot takes over: it executes every approved tool, collects the results, and re-sends the conversation – automatically, in a loop, until the model is done or needs your input. One prompt can trigger an entire multi-step workflow: the model reads files to understand a codebase, plans its approach, writes code, runs tests, reads the failures, fixes them, and re-runs – all from a single <kbd>Ctrl-]</kbd>.

You are always in control. The entire conversation – every tool call, every result, every decision the model makes – is visible in the buffer. You can:

- **Let it run.** Auto-approve trusted tools (e.g., `read`) and let the model work autonomously.
- **Supervise.** Keep `require_approval = true` (the default) so autopilot pauses before each tool executes. Review the call, press <kbd>Ctrl-]</kbd> to approve, and the loop resumes.
- **Intervene.** Press <kbd>Ctrl-C</kbd> at any point to stop everything. Edit the buffer. Change the model's plan. Then press <kbd>Ctrl-]</kbd> to continue.

### Safety

- **Turn limit:** A configurable safety cap (`tools.autopilot.max_turns`, default 100) stops the loop with a warning if exceeded, preventing runaway cost from models that loop without converging.
- **Cancellation:** <kbd>Ctrl-C</kbd> cancels the active request or tool execution and fully disarms autopilot – no surprises when you next press <kbd>Ctrl-]</kbd>.
- **Conflict detection:** If autopilot pauses for approval and you edit the content inside a `flemma:tool` block, Flemma detects your changes and will not overwrite them. It warns and stays paused so you can review.

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
      rw_paths = { "$CWD" },    -- only the project directory is writable
      network = false,          -- no network access
    },
  },
})
```

Override per-buffer via `flemma.opt.sandbox` in frontmatter, or toggle at runtime with `:Flemma sandbox:enable/disable`. See [docs/sandbox.md](docs/sandbox.md) for the full reference on policy options, path variables, custom backends, and security considerations.

---

## Template System

Flemma's prompt pipeline supports Lua/JSON frontmatter, inline `{{ expressions }}`, and an `include()` helper for composable prompts. Errors surface as diagnostics before the request leaves your editor. Embed local files with `@./path` syntax – Flemma detects MIME types and formats attachments per-provider. See [docs/templates.md](docs/templates.md) for the full reference.

---

## Usage, Pricing, and Notifications

Each completed request emits a floating report that names the provider/model, lists input/output tokens (reasoning tokens are counted under `thoughts`), and – when pricing is enabled – shows the per-request and cumulative session cost derived from `lua/flemma/models.lua`. When prompt caching is active, a `Cache:` line shows read and write token counts. Token accounting persists for the lifetime of the Neovim instance; call `require("flemma.state").reset_session()` to zero the counters without restarting. `pricing.enabled = false` suppresses the dollar amounts while keeping token totals.

Notifications are buffer-local – each `.chat` buffer gets its own notification stack, positioned relative to its window. Notifications for hidden buffers are queued and shown when the buffer becomes visible. Recall the most recent notification with `:Flemma notification:recall`.

For programmatic access to token usage and cost data, see [docs/session-api.md](docs/session-api.md).

---

## UI Customisation

Flemma adapts to your colour scheme with theme-aware highlights, line backgrounds, rulers, sign column indicators, and folding. Every visual element is configurable – see [docs/ui.md](docs/ui.md) for the full reference.

The bundled [Lualine component](docs/ui.md#lualine-integration) shows the active model and thinking level in your statusline.

---

## Configuration Reference

Flemma works without arguments – `require("flemma").setup({})` uses sensible defaults (Anthropic provider, `thinking = "high"`, prompt caching enabled). Every option is documented with inline comments in the [full configuration reference](docs/configuration.md).

Key defaults:

| Parameter         | Default       | Description                                             |
| ----------------- | ------------- | ------------------------------------------------------- |
| `provider`        | `"anthropic"` | `"anthropic"` / `"openai"` / `"vertex"`                 |
| `thinking`        | `"high"`      | Unified thinking level across providers                 |
| `cache_retention` | `"short"`     | Prompt caching strategy                                 |
| `max_tokens`      | `4000`        | Maximum response tokens                                 |
| `temperature`     | `0.7`         | Sampling temperature (disabled when thinking is active) |

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

- **Nothing happens when I send:** confirm the buffer name ends with `.chat` and the first message starts with `@You:` or `@System:`.
- **Frontmatter errors:** notifications list the exact line and file. Fix the error and resend; Flemma will not contact the provider until the frontmatter parses cleanly.
- **Attachments ignored:** ensure the file exists relative to the `.chat` file and that the provider supports its MIME type. Use `;type=` to override when necessary.
- **Temperature ignored:** when thinking is enabled (default `"high"`), Anthropic and OpenAI disable temperature. Set `thinking = false` if you need temperature control.
- **Vertex refuses requests:** double-check `parameters.vertex.project_id` and authentication. Run `gcloud auth application-default print-access-token` manually to ensure credentials are valid.
- **Tool execution doesn't respond:** make sure the cursor is on or near the `**Tool Use:**` block. Only tools with registered executors can be run – check `:lua print(vim.inspect(require("flemma.tools").get_all()))`.
- **Keymaps clash:** disable built-in mappings via `keymaps.enabled = false` and register your own `:Flemma` commands.
- **Sandbox blocks writes:** If a tool reports "permission denied" on a path you expect to be writable, run `:Flemma status` (or `:Flemma sandbox:status`) and verify the path is inside `rw_paths`. Add it to `sandbox.policy.rw_paths` or disable sandboxing to troubleshoot.
- **Cross-buffer issues:** Flemma manages state per-buffer. If something feels off after switching between multiple `.chat` buffers, ensure each buffer has been saved (unsaved buffers lack `__dirname` for path resolution).

## License

Flemma is licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0).

Happy prompting!
