# Flemma 🪶

> [!CAUTION]
> **Actively Evolving**
>
> Flemma is growing fast – new tools, providers, and UI features land regularly. Expect occasional breaking changes while the project matures. Pin a commit if you need a steady target.

Flemma turns Neovim into a first-class AI workspace. It gives `.chat` buffers streaming conversations, tool calling, reusable prompt templates, attachment support, cost tracking, and ergonomic commands for the three major providers: Anthropic, OpenAI, and Google Vertex AI.

<a href="assets/frame_linux_slate.webp" target="_blank"><img align="center" width="730" height="882" src="assets/frame_linux_slate.webp" alt="Flemma chat buffer example" /></a>

---

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

…accidentally pressing <kbd>&lt;C-R></kbd> and refreshing the page midway through a prompt (or <kbd>&lt;C-W></kbd> trying to delete a word)… or Chrome sending a tab to sleep whilst I had an unsaved session… or having to worry about whether files I shared with Claude Workbench were stored on some Anthropic server indefinitely. I can be fast! I can be reckless! I can tinker! I can use my Vim keybindings and years of muscle memory!

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

## What Flemma Delivers

- **Multi-provider chat** – work with Anthropic, OpenAI, and Vertex AI models through one command tree while keeping prompts in plain `.chat` buffers.
- **Tool calling** – models can request calculator evaluations, bash commands, file reads, edits, and writes. Flemma executes them (with your approval) and injects results back into the buffer. Works across all three providers with parallel tool support. Per-buffer `flemma.opt` lets you control which tools each conversation can use. Custom tools can resolve definitions asynchronously – from CLI subprocesses, remote APIs, or plugin loaders – with zero startup cost.
- **Extended thinking and reasoning** – stream Anthropic thinking traces, tune OpenAI reasoning effort, and control Vertex thinking budgets. Thinking blocks auto-fold and get dedicated highlighting.
- **`.chat` editing tools** – get Markdown folding, visual rulers, `<thinking>` highlighting, tool call syntax highlighting, and message text objects tuned for chat transcripts.
- **Structured templates** – combine Lua or JSON frontmatter, inline `{{ expressions }}`, and `include()` helpers to assemble prompts without leaving Neovim.
- **Context attachments** – reference local files with `@./path`; Flemma handles MIME detection and surfaces warnings when a provider can't ingest the asset.
- **Theme-aware UI** – line highlights, rulers, and signs adapt to your colour scheme via blend expressions. Dark and light modes are first-class.
- **Usage reporting** – per-request and session notifications show token totals, costs, and cache metrics (read/write tokens) using the bundled pricing tables.
- **Presets and hooks** – store favourite provider configurations, run `on_request_*` callbacks, auto-write finished chats, and recall the latest usage notification when auditing work.
- **Contributor tooling** – toggle structured logs, drop into the project's Nix dev shell, and run the bundled headless tests without extra setup.

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

4. Press <kbd>Ctrl-]</kbd> (normal or insert mode) or run `:Flemma send`. Flemma freezes the buffer while the request is streaming and shows `@Assistant: Thinking...`. <kbd>Ctrl-]</kbd> is a hybrid key – if the model responded with tool calls, pressing it again executes them all, and once every tool has a result, the next press sends the conversation back to the provider.
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

- **Frontmatter** sits on the first line and must be fenced with triple backticks. Lua and JSON parsers ship with Flemma; you can register more via `flemma.frontmatter.parsers.register("yaml", parser_fn)`. Lua frontmatter also exposes `flemma.opt` for [per-buffer tool selection](#per-buffer-tool-selection).
- **Messages** begin with `@System:`, `@You:`, or `@Assistant:`. The parser is whitespace-tolerant and handles blank lines between messages.
- **Thinking blocks** appear only in assistant messages. Anthropic and Vertex AI models stream `<thinking>` sections; Flemma folds them automatically and keeps dedicated highlights for the tags and body.

### Folding and layout

| Fold level | What folds                 | Why                                                             |
| ---------- | -------------------------- | --------------------------------------------------------------- |
| Level 3    | The frontmatter block      | Keep templates out of the way while you focus on chat history.  |
| Level 2    | `<thinking>...</thinking>` | Reasoning traces are useful, but often secondary to the answer. |
| Level 1    | Each message               | Collapse long exchanges without losing context.                 |

Toggle folds with your usual mappings (`za`, `zc`, etc.). The fold text shows a snippet of the hidden content so you know whether to expand it. The initial fold level is configurable via `editing.foldlevel` (default `1`, which collapses thinking blocks).

Between messages, Flemma draws a ruler using the configured `ruler.char` and highlight. This keeps multi-step chats legible even with folds open.

### Navigation and text objects

Inside `.chat` buffers Flemma defines:

- `]m` / `[m` – jump to the next/previous message header.
- `im` / `am` (configurable) – select the inside or entire message as a text object. `am` selects linewise and includes thinking blocks and trailing blank lines, making `dam` delete entire conversation turns. `im` skips `<thinking>` sections so yanking `im` never includes reasoning traces.
- Buffer-local mappings for send/cancel default to `<C-]>` and `<C-c>` in normal mode. `<C-]>` is a hybrid key: it executes all pending tool calls when any exist, otherwise sends the conversation. Insert-mode `<C-]>` behaves identically but re-enters insert when the operation finishes.

Disable or remap these through the `keymaps` section (see [Configuration reference](#configuration-reference)).

---

## Commands and Provider Management

Use the single entry point `:Flemma {command}`. Autocompletion lists every available sub-command.

| Command                                             | Purpose                                                                   | Example                                                                     |
| --------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `:Flemma send [key=value …]`                        | Send the current buffer. Optional callbacks run before/after the request. | `:Flemma send on_request_start=stopinsert on_request_complete=startinsert!` |
| `:Flemma cancel`                                    | Abort the active request and clean up the spinner.                        |                                                                             |
| `:Flemma switch …`                                  | Choose or override provider/model parameters.                             | See below.                                                                  |
| `:Flemma import`                                    | Convert Claude Workbench code snippets into `.chat` format.               |                                                                             |
| `:Flemma message:next` / `:Flemma message:previous` | Jump through message headers.                                             |                                                                             |
| `:Flemma tool:execute`                              | Execute the tool at the cursor position.                                  |                                                                             |
| `:Flemma tool:cancel`                               | Cancel the tool execution at the cursor.                                  |                                                                             |
| `:Flemma tool:cancel-all`                           | Cancel all pending tool executions in the buffer.                         |                                                                             |
| `:Flemma tool:list`                                 | List pending tool executions with IDs and elapsed time.                   |                                                                             |
| `:Flemma logging:enable` / `:…:disable` / `:…:open` | Toggle structured logging and open the log file.                          |                                                                             |
| `:Flemma notification:recall`                       | Reopen the last usage/cost notification.                                  |                                                                             |

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

| Provider  | Defaults            | Extra parameters                                                                                                                    | Notes                                                                                 |
| --------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Anthropic | `claude-sonnet-4-5` | `thinking_budget` enables extended thinking (≥ 1024). `cache_retention` controls prompt caching (`"short"`, `"long"`, or `"none"`). | Supports text, image, and PDF attachments. Thinking blocks stream into the buffer.    |
| OpenAI    | `gpt-5`             | `reasoning=<low\|medium\|high>` toggles reasoning effort.                                                                           | Cost notifications include reasoning tokens. Lualine shows the reasoning level.       |
| Vertex AI | `gemini-2.5-pro`    | `project_id` (required), `location` (default `global`), `thinking_budget` (≥ 1 to activate).                                        | `thinking_budget` activates Google's thinking output; set to `0` or `nil` to disable. |

The full model catalogue (including pricing) is in `lua/flemma/models.lua`. You can access it from Neovim with:

```lua
:lua print(vim.inspect(require("flemma.provider.config").models))
```

### Prompt caching (Anthropic)

Flemma automatically adds cache breakpoints to Anthropic API requests, letting the provider reuse previously processed prefixes at a fraction of the cost[^anthropic-cache]. Three breakpoints are placed: the tool definitions, the system prompt, and the last user message. Tools are sorted alphabetically so the prefix stays stable across requests.

The `cache_retention` parameter controls the caching strategy[^anthropic-cache-pricing]:

| Value     | TTL    | Write cost | Read cost | Description                    |
| --------- | ------ | ---------- | --------- | ------------------------------ |
| `"short"` | 5 min  | 1.25×      | 0.1×      | Default. Good for active chat. |
| `"long"`  | 1 hour | 2.0×       | 0.1×      | Better for long-running tasks. |
| `"none"`  | —      | —          | —         | Disable caching entirely.      |

When caching is active, usage notifications show a `Cache:` line with read and write token counts. Costs are adjusted accordingly – cache reads are 90% cheaper than regular input tokens.

> [!NOTE]
> Anthropic requires a **minimum number of tokens** in the cached prefix before caching activates[^anthropic-cache-limits]. The thresholds vary by model: **4096 tokens** for Opus 4.6, Opus 4.5, and Haiku 4.5; **1024 tokens** for Sonnet 4.5, Opus 4.1, Opus 4, and Sonnet 4. If your conversation is below this threshold, the API returns zero cache tokens and charges the standard input rate. This is expected – caching benefits grow with longer conversations and system prompts.

### Prompt caching (OpenAI)

OpenAI applies prompt caching automatically to all Chat Completions API requests[^openai-cache]. No configuration or request-side changes are needed – the API detects reusable prompt prefixes and serves them from cache transparently. When a cache hit occurs, the usage notification shows a `Cache:` line with the number of read tokens. Costs are adjusted to reflect the 50% discount on cached input[^openai-cache-pricing].

| Metric      | Value        | Description                                                        |
| ----------- | ------------ | ------------------------------------------------------------------ |
| Read cost   | 0.5× (50%)   | Cached input tokens cost half the normal input rate.               |
| Write cost  | —            | No additional charge; caching is automatic.                        |
| Min. tokens | 1,024        | Prompts shorter than 1,024 tokens are never cached.                |
| TTL         | 5–10 minutes | Caches are cleared after inactivity; always evicted within 1 hour. |

> [!IMPORTANT]
> OpenAI caching is **best-effort and not guaranteed**. Even when the prompt meets all requirements, the API may return zero cached tokens. Key conditions:
>
> - **Minimum 1,024 tokens** in the prompt prefix[^openai-cache]. Shorter prompts are never cached.
> - **Prefix must be byte-identical** between requests. Any change to tools, system prompt, or earlier messages invalidates the cache from that point forward.
> - **Cache propagation takes time.** The first request populates the cache; subsequent requests can hit it. Sending requests in rapid succession (within a few seconds) may miss the cache because the entry hasn't propagated yet. Wait at least 5–10 seconds between requests for the best chance of a hit.
> - **128-token granularity.** Only the first 1,024 tokens plus whole 128-token increments are cacheable. Tokens beyond the last 128-token boundary are always processed fresh.
> - **No user control.** Unlike Anthropic, there is no `cache_retention` parameter or opt-out – caching is entirely managed by OpenAI's infrastructure. You cannot force a cache hit or extend the TTL.

### Prompt caching (Vertex AI)

Gemini 2.5+ models support implicit context caching[^vertex-cache]. When consecutive requests share a common input prefix, the Vertex AI serving infrastructure automatically caches and reuses it – no configuration or request changes are needed. When a cache hit occurs, the usage notification shows a `Cache:` line with the number of read tokens. Costs are adjusted to reflect the 90% discount on cached input[^vertex-cache-pricing].

| Metric      | Value         | Description                                            |
| ----------- | ------------- | ------------------------------------------------------ |
| Read cost   | 0.1× (10%)    | Cached input tokens cost 10% of the normal input rate. |
| Write cost  | —             | No additional charge; caching is automatic.            |
| Min. tokens | 1,024 / 2,048 | 1,024 for Flash models, 2,048 for Pro models.          |

> [!IMPORTANT]
> Vertex AI implicit caching is **automatic and best-effort** – cache hits are not guaranteed. Key conditions:
>
> - **Minimum token thresholds** vary by model: **1,024 tokens** for Flash, **2,048 tokens** for Pro[^vertex-cache]. Shorter prompts are never cached.
> - **Prefix must be identical** between requests. Changing tools, system instructions, or earlier conversation turns invalidates the cache from that point forward.
> - **Only Gemini 2.5+ models** support implicit caching. Older Gemini models (2.0, 1.5) do not report cached tokens.
> - **Cache propagation takes time.** Like OpenAI, the first request populates the cache and immediate follow-up requests may not see a hit. Allow a few seconds between requests.
> - **No user control.** There is no TTL parameter or opt-out – caching is managed entirely by Google's infrastructure.
>
> Google also offers an **explicit Context Caching API**[^vertex-cache-explicit] that creates named cache resources with configurable TTLs via a separate endpoint. Explicit caching requires a different workflow (create cache, then reference it) and is not yet supported by Flemma.

---

## Tool Calling

Flemma includes a tool system that lets models request actions – run a calculation, execute a shell command, read or modify files – and receive structured results, all within the `.chat` buffer.

### How it works

1. When you send a message, Flemma includes definitions for available tools in the API request.
2. If the model decides to use a tool, it emits a `**Tool Use:**` block in its response:

   ````markdown
   @Assistant: Let me calculate that for you.

   **Tool Use:** `calculator` (`toolu_abc123`)

   ```json
   { "expression": "20 + 30 + 50" }
   ```
   ````

3. You can execute the tool by pressing <kbd>Alt-Enter</kbd> with the cursor on or near the tool use block. Flemma runs the tool, locks the buffer during execution, and injects a `**Tool Result:**` block. Alternatively, press <kbd>Ctrl-]</kbd> to execute all pending tool calls at once:

   ````markdown
   @You: **Tool Result:** `toolu_abc123`

   ```
   100
   ```
   ````

4. Send the buffer again (<kbd>Ctrl-]</kbd> or `:Flemma send`) to continue the conversation. The model sees the tool result and can respond accordingly.

### Built-in tools

| Tool         | Type  | Description                                                                                                         |
| ------------ | ----- | ------------------------------------------------------------------------------------------------------------------- |
| `calculator` | sync  | Evaluates mathematical expressions using Lua's `math` library. Sandboxed – only `math.*` functions are available.   |
| `bash`       | async | Executes shell commands. Configurable shell, working directory, and environment. Supports timeout and cancellation. |
| `read`       | sync  | Reads file contents with optional offset and line limit. Relative paths resolve against the `.chat` file.           |
| `write`      | sync  | Writes or creates files. Creates parent directories automatically.                                                  |
| `edit`       | sync  | Find-and-replace with exact text matching. The old text must appear exactly once in the target file.                |

### Tool execution

- **<kbd>Ctrl-]</kbd>** – the single interaction key. When pending tool calls exist it executes them all; when every tool call has a result it sends the conversation to the provider.
- **<kbd>Alt-Enter</kbd>** – execute the tool at the cursor position (normal mode). Useful when you want to run one specific tool call instead of all pending ones.
- **Async tools** (like `bash`) show an animated spinner while running and can be cancelled.
- **Buffer locking** – the buffer is made non-modifiable during tool execution to prevent race conditions.
- **Output truncation** – large outputs (> 4000 lines or 8 MB) are automatically truncated with a summary. The full output is saved to a temporary file and the path is included in the truncated result.
- **Cursor positioning** – after injection, the cursor can move to the result (`"result"`), stay put (`"stay"`), or jump to the next `@You:` prompt (`"next"`). Controlled by `tools.cursor_after_result`.

### Parallel tool use

All three providers support parallel tool calls – the model can request multiple tools in a single response. Press <kbd>Ctrl-]</kbd> to execute all pending calls at once, or use <kbd>Alt-Enter</kbd> on individual blocks.

Flemma validates that every `**Tool Use:**` block has a matching `**Tool Result:**` before sending. Missing results produce a diagnostic warning.

### Registering custom tools

`require("flemma.tools").register()` is a single entry point that accepts several forms:

**Single definition** – pass a name and definition table:

```lua
local tools = require("flemma.tools")
tools.register("my_tool", {
  name = "my_tool",
  description = "Does something useful",
  input_schema = {
    type = "object",
    properties = {
      query = { type = "string", description = "The input query" },
    },
    required = { "query" },
  },
  execute = function(input)
    return { success = true, output = "done: " .. input.query }
  end,
})
```

**Module name** – pass a module path. If the module exports `.definitions` (an array of definition tables), they are registered synchronously. If it exports `.resolve(register, done)`, it is registered as an async source (see below):

```lua
tools.register("my_plugin.tools.search")
```

**Batch** – pass an array of definition tables:

```lua
tools.register({
  { name = "tool_a", description = "…", input_schema = { type = "object", properties = {} } },
  { name = "tool_b", description = "…", input_schema = { type = "object", properties = {} } },
})
```

### Async tool definitions

Tool definitions that need to call external processes or remote APIs can resolve asynchronously. Flemma gates API requests on all sources being ready – if you send while definitions are still loading, the buffer shows "Waiting for tool definitions to load…" and auto-sends once everything resolves.

**Function form** – pass a resolve function directly:

```lua
tools.register(function(register, done)
  vim.fn.jobstart({ "my-cli", "list-tools" }, {
    on_exit = function()
      register("discovered_tool", { --[[ definition ]] })
      done()       -- signals this source is complete
    end,
  })
end)
```

**Table form** – pass a table with `.resolve` and an optional `.timeout` (seconds):

```lua
tools.register({
  timeout = 60,
  resolve = function(register, done)
    -- fetch definitions from a remote API...
    register("remote_tool", { --[[ definition ]] })
    done()
  end,
})
```

**Module form** – export a `resolve` function from your module:

```lua
-- In lua/my_plugin/tools.lua
local M = {}

function M.resolve(register, done)
  -- async work...
  register("my_tool", { --[[ definition ]] })
  done()
end

M.timeout = 45  -- optional, defaults to tools.default_timeout (30s)

return M
```

```lua
-- In your setup:
tools.register("my_plugin.tools")
```

Key details:

- **`register(name, def)`** can be called multiple times within a single source to register several tools.
- **`done(err?)`** must be called exactly once. Pass an error string to signal failure (the source completes but a warning is shown). Double-calling `done()` is safe (idempotent).
- **Timeout** – if `done()` is never called, the source times out after `tools.default_timeout` seconds (default 30). This prevents a broken source from blocking requests forever.
- **Error handling** – if the resolve function throws, `done(err)` is called automatically.

### Tool configuration

```lua
require("flemma").setup({
  tools = {
    default_timeout = 30,              -- Timeout for async tools (seconds)
    show_spinner = true,               -- Animated spinner during execution
    cursor_after_result = "result",    -- "result" | "stay" | "next"
    bash = {
      shell = nil,                     -- Shell binary (default: bash)
      cwd = nil,                       -- Working directory (nil = buffer dir)
      env = nil,                       -- Extra environment variables
    },
  },
})
```

### Per-buffer tool selection

Control which tools are available on a per-buffer basis using `flemma.opt` in Lua frontmatter. The API follows `vim.opt` conventions:

````lua
```lua
-- Only send specific tools with the request:
flemma.opt.tools = {"bash", "read"}

-- Remove a tool from the defaults:
flemma.opt.tools:remove("calculator")

-- Add a tool (including disabled tools like calculator_async used in debugging):
flemma.opt.tools:append("calculator_async")

-- Add at the beginning of the tool list:
flemma.opt.tools:prepend("read")

-- Operator overloads (same as vim.opt):
flemma.opt.tools = flemma.opt.tools + "read"        -- append
flemma.opt.tools = flemma.opt.tools - "calculator"   -- remove
flemma.opt.tools = flemma.opt.tools ^ "read"         -- prepend

-- All methods accept both strings and tables:
flemma.opt.tools:remove({"calculator", "bash"})
flemma.opt.tools:append({"read", "write"})
```
````

Each evaluation starts from defaults (all enabled tools). Changes only affect the current buffer's request – other buffers and future evaluations are unaffected.

Tools registered with `enabled = false` (such as `calculator_async` used by Flemma devs for debugging tool calls) are excluded from the defaults but can be explicitly added via `:append()` or direct assignment.

Misspelled tool names produce an error with a "did you mean" suggestion when a close match exists.

### Per-buffer provider parameter overrides

Provider-specific parameters can also be overridden per-buffer using `flemma.opt.<provider>.*`:

````lua
```lua
-- Override Anthropic parameters for this buffer:
flemma.opt.anthropic.cache_retention = "none"   -- Disable prompt caching
flemma.opt.anthropic.thinking_budget = 20000    -- Increase thinking budget

-- Override OpenAI parameters:
flemma.opt.openai.reasoning = "high"

-- Override Vertex parameters:
flemma.opt.vertex.thinking_budget = 4096

-- Table assignment also works:
flemma.opt.anthropic = { cache_retention = "long", thinking_budget = 10000 }
```
````

Provider parameter overrides follow the same per-buffer isolation as tool selection – each buffer starts from the global defaults.

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

Each completed request emits a floating report that names the provider/model, lists input/output tokens (reasoning tokens are counted under `⊂ thoughts`), and – when pricing is enabled – shows the per-request and cumulative session cost derived from `lua/flemma/models.lua`. When prompt caching is active (Anthropic, OpenAI, or Vertex AI), a `Cache:` line shows read and write token counts, and costs are adjusted to reflect the provider-specific discount on cached input. Token accounting persists for the lifetime of the Neovim instance; call `require("flemma.state").reset_session()` if you need to zero the counters without restarting. `pricing.enabled = false` suppresses the dollar amounts while keeping token totals for comparison.

Notifications are buffer-local – each `.chat` buffer gets its own notification stack, positioned relative to its window. Notifications for hidden buffers (e.g., in another tab) are queued and shown when the buffer becomes visible.

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

While a request runs Flemma appends `@Assistant: Thinking...` with an animated braille spinner using virtual text extmarks. The line is flagged as non-spellable so spell check integrations stay quiet. Once streaming starts, the spinner is removed and replaced with the streamed content.

Tool execution also shows a spinner next to the tool result block while the tool is running.

---

## Lualine Integration

Add the bundled component to show the active model (and reasoning effort or thinking status when set):

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

The component only renders in `chat` buffers. Switching providers or toggling reasoning/thinking causes Flemma to refresh lualine automatically.

The display format is configurable:

```lua
require("flemma").setup({
  statusline = {
    thinking_format = "{model}  ✓ thinking",   -- When thinking_budget is set
    reasoning_format = "{model} ({level})",     -- When OpenAI reasoning is set
  },
})
```

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
    anthropic = {
      thinking_budget = nil,                 -- Extended thinking (≥ 1024, or nil to disable)
      cache_retention = "short",             -- Prompt caching: "none" | "short" (5-min) | "long" (1h TTL)
    },
    vertex = {
      project_id = nil,                      -- Google Cloud project ID (required for Vertex)
      location = "global",                   -- Google Cloud region
      thinking_budget = nil,                 -- Thinking output (≥ 1 to enable, nil/0 to disable)
    },
    openai = {
      reasoning = nil,                       -- "low" | "medium" | "high" (nil to disable)
    },
  },
  presets = {},                              -- Named presets: ["$name"] = "provider model key=val"
  tools = {
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
    thinking_format = "{model}  ✓ thinking",
    reasoning_format = "{model} ({level})",
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

Additional notes:

- `editing.auto_write = true` writes the buffer after each successful request or cancellation.
- `editing.foldlevel` controls the initial fold state: `0` folds everything, `1` keeps messages open but collapses thinking blocks, `99` opens everything.
- Set `text_object = false` to disable the message text object entirely.
- `notify.default_opts` exposes floating-window appearance (timeout, width, border, title).
- `logging.enabled = true` starts the session with logging already active.
- `keymaps.enabled = false` disables all built-in mappings so you can register your own `:Flemma` commands.
- The `send` key is a hybrid dispatch: when pending tool calls exist it executes them all, otherwise it sends the conversation to the provider. To restore the previous send-only behaviour, disable the built-in mapping and bind directly to `send_to_provider`:

  ```lua
  keymaps = { normal = { send = false }, insert = { send = false } },
  ```

  ```lua
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "chat",
    callback = function()
      vim.keymap.set("n", "<C-]>", function()
        require("flemma.core").send_to_provider()
      end, { buffer = true })
    end,
  })
  ```

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

To exercise the plugin without installing it globally:

```bash
nvim --cmd "set runtimepath+=`pwd`" \
  -c 'lua require("flemma").setup({})' \
  -c ':edit scratch.chat'
```

> [!NOTE]
> **Almost every line of code** in Flemma has been authored through AI pair-programming tools (Aider, Amp, Claude Code, and Codex). Traditional contributions are welcome – just keep changes focused, documented, and tested.

---

## Session API

Flemma tracks token usage and costs for every API request in a global session object. The session lives in memory for the lifetime of the Neovim instance and is accessible through the `flemma.session` module.

### Reading the current session

```lua
local session = require("flemma.session").get()

-- Aggregate stats
print("Requests:", session:get_request_count())
print("Total cost: $" .. string.format("%.2f", session:get_total_cost()))

-- Iterate individual requests
for _, request in ipairs(session.requests) do
  print(string.format(
    "%s/%s  in=%d out=%d  $%.4f  %s",
    request.provider,
    request.model,
    request.input_tokens,
    request:get_total_output_tokens(),
    request:get_total_cost(),
    request.filepath or "(unnamed)"
  ))
end
```

Each request stores raw data – tokens, per-million prices, cache multipliers, and timestamps – so costs are always derived from the underlying components. Available fields on a request:

| Field                                                    | Description                                                                             |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `provider`, `model`                                      | Provider and model that handled the request                                             |
| `input_tokens`, `output_tokens`, `thoughts_tokens`       | Raw token counts                                                                        |
| `input_price`, `output_price`                            | USD per million tokens (snapshot at request time)                                       |
| `cache_read_input_tokens`, `cache_creation_input_tokens` | Cache token counts                                                                      |
| `cache_read_multiplier`, `cache_write_multiplier`        | Cache cost multipliers (nil when not applicable)                                        |
| `output_has_thoughts`                                    | Whether `output_tokens` already includes thinking tokens                                |
| `started_at`, `completed_at`                             | Timestamps as seconds since epoch with microsecond precision (e.g. `1700000042.123456`) |
| `filepath`, `bufnr`                                      | Source buffer identifier                                                                |

Methods: `get_input_cost()`, `get_output_cost()`, `get_total_cost()`, `get_total_output_tokens()`.

### Saving and restoring a session

`Session:load()` accepts a list of option tables in the same format as `add_request()` and replaces the current session contents. Combined with reading `session.requests`, this enables crude persistence:

```lua
-- Save to a JSON file (use vim.json for full numeric precision)
local session = require("flemma.session").get()
local json = vim.json.encode(session.requests)
vim.fn.writefile({ json }, vim.fn.stdpath("data") .. "/flemma_session.json")

-- Restore from a saved file
local path = vim.fn.stdpath("data") .. "/flemma_session.json"
local lines = vim.fn.readfile(path)
if #lines > 0 then
  require("flemma.session").get():load(vim.json.decode(table.concat(lines, "\n")))
end
```

---

## Troubleshooting Checklist

- **Nothing happens when I send:** confirm the buffer name ends with `.chat` and the first message starts with `@You:` or `@System:`.
- **Frontmatter errors:** notifications list the exact line and file. Fix the error and resend; Flemma will not contact the provider until the frontmatter parses cleanly.
- **Attachments ignored:** ensure the file exists relative to the `.chat` file and that the provider supports its MIME type. Use `;type=` to override when necessary.
- **Vertex refuses requests:** double-check `parameters.vertex.project_id` and authentication. Run `gcloud auth application-default print-access-token` manually to ensure credentials are valid.
- **Tool execution doesn't respond:** make sure the cursor is on or near the `**Tool Use:**` block. Only tools with registered executors can be run – check `:lua print(vim.inspect(require("flemma.tools").get_all()))`.
- **Keymaps clash:** disable built-in mappings via `keymaps.enabled = false` and register your own `:Flemma` commands.
- **Cross-buffer issues:** Flemma manages state per-buffer. If something feels off after switching between multiple `.chat` buffers, ensure each buffer has been saved (unsaved buffers lack `__dirname` for path resolution).

Happy prompting!

[^anthropic-cache]: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching
[^anthropic-cache-pricing]: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching#pricing
[^anthropic-cache-limits]: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching#cache-limitations
[^openai-cache]: https://platform.openai.com/docs/guides/prompt-caching
[^openai-cache-pricing]: https://platform.openai.com/docs/pricing
[^vertex-cache]: https://developers.googleblog.com/en/gemini-2-5-models-now-support-implicit-caching/
[^vertex-cache-pricing]: https://cloud.google.com/vertex-ai/generative-ai/pricing
[^vertex-cache-explicit]: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/context-cache/context-cache-overview
