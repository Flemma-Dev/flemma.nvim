<h1><img src="https://images.weserv.nl/?url=avatars.githubusercontent.com%2Fu%2F231013899%3Fs%3D400%26v%3D4&mask=circle" width="38" height="38" valign="bottom" alt="Flemma's logo"> Flemma</h1>

**An AI workspace inside Neovim where every conversation is a document you own.**

https://github.com/user-attachments/assets/cd1c509d-faea-48e1-bd4d-d01e234d6856

> [!IMPORTANT]
> **Actively Evolving.** [See the roadmap](ROADMAP.md) for what's coming next. Pin a tag if you need a stable target.

---

## What Is Flemma?

Flemma is an AI plugin for Neovim. You write in `.chat` files -- plain text with simple role markers -- and Flemma handles everything else: streaming responses, running tools, managing providers, and keeping the conversation clean and navigable.

```markdown
@You:
Turn my rough notes into a project update for the team.

- Auth module now validates JWTs server-side.
- Migrated billing webhook to v2 API.
- Fixed the flaky CI timeout on integration tests.

Use `git log` for commit details.

@Assistant:
(response streams here)
```

What makes Flemma different from other AI tools is a simple design choice: **the `.chat` file is the conversation.** There's no database behind it, no hidden session state, no opaque storage. The file you see is the file the model sees. That one decision unlocks everything else.

### Quick Start

```lua
-- lazy.nvim (any plugin manager works):
{ "Flemma-Dev/flemma.nvim", opts = {} }

-- If your plugin manager doesn't auto-call setup(), add this to your config:
require("flemma").setup({})
```

```bash
export ANTHROPIC_API_KEY="sk-ant-..."   # or OPENAI_API_KEY, MOONSHOT_API_KEY
```

Create a file ending in `.chat`. Type your message after `@You:`. Press <kbd>Ctrl-]</kbd>.

**Requirements:** Neovim 0.11+, `curl`, Markdown Tree-sitter grammar. Optional: [`bwrap`](https://github.com/containers/bubblewrap) for sandboxing (Linux), [`file`](https://www.darwinsys.com/file/) for MIME detection.

<details>
<summary><strong>Setting up credentials</strong></summary>

Flemma never accepts API keys in your Lua config -- credentials stay in environment variables or your platform's secure keyring.

**Environment variables** (simplest approach):

| Provider  | Variable                                                 |
| --------- | -------------------------------------------------------- |
| Anthropic | `ANTHROPIC_API_KEY`                                      |
| OpenAI    | `OPENAI_API_KEY`                                         |
| Moonshot  | `MOONSHOT_API_KEY`                                       |
| Vertex AI | `VERTEX_AI_ACCESS_TOKEN` (or service-account flow below) |

**Linux keyring** (Secret Service) -- store once, reuse across all Neovim sessions:

```bash
secret-tool store --label="Anthropic API Key" service anthropic key api
secret-tool store --label="OpenAI API Key" service openai key api
secret-tool store --label="Moonshot API Key" service moonshot key api
```

**macOS Keychain** is also supported.

**Vertex AI** requires a Google Cloud service account:

1. Create a service account with the _Vertex AI User_ role.
2. Export its JSON credentials via `VERTEX_SERVICE_ACCOUNT='{"type": "..."}'`, or store them in the Linux keyring with `secret-tool store --label="Vertex AI Service Account" service vertex key api project_id your-project`.
3. Ensure `gcloud` is on your `$PATH` -- Flemma uses `gcloud auth print-access-token` to refresh tokens.
4. Set `project_id` in your config or via `:Flemma switch vertex gemini-3.1-pro-preview project_id=my-project`.

Flemma tries each resolver in order and uses the first one that returns a credential. When everything fails, the notification tells you exactly which resolvers were tried and why each one couldn't help. You can also write custom resolvers for tools like Bitwarden or 1Password -- read more in [extending.md](docs/extending.md#credential-resolution).

</details>

---

## Why Conversations as Files?

Most AI tools treat conversations as disposable. Some let you resume a session or rewind to a checkpoint, but you can't go back and edit a message you sent two turns ago and have the model treat it as if it was always there. The conversation is the tool's state, not yours. Flemma takes the opposite approach.

**Your conversations are files.** Save them. Reopen them tomorrow. `git commit` them. `grep` across months of work. Share a conversation with a colleague by sending them the file -- they open it in Flemma and pick up exactly where you left off, with the same model settings, the same system prompt, the same everything.

**You can edit anything.** The model hallucinated? Fix the response and resend. Went down the wrong path? Delete the last few turns and try again. Want to test how a different model handles the same prompt? Switch providers mid-conversation with `:Flemma switch openai` and press <kbd>Ctrl-]</kbd>. There's no hidden state to get out of sync because there is no hidden state.

**Every conversation can have its own settings.** One `.chat` file uses Claude for code review with full tool access. Another uses Gemini for brainstorming with thinking turned off. A third is a reusable template your team shares for incident postmortems. The settings live inside each file -- no global config changes needed.

**You stay in Neovim.** Vim motions, your keybindings, your colour scheme, your workflow. Flemma adds a handful of buffer-local mappings and gets out of the way.

---

## What Can You Do With It?

Flemma is more than a chatbot. Here are some of the things people use it for:

- **Code with an AI agent.** Give it a task -- "add error handling to the payment module" -- and let autopilot do the work. Flemma explores the codebase, reads files, writes code, runs tests, reads the output, fixes failures, and repeats. You approve each step or let it run fully autonomously, _YOLO_.
- **Write and create.** Technical documents, project updates, architecture decisions, client proposals. Feed it rough notes and context files, get polished output.
- **Research and explore.** Attach files with `@./path/to/file`, ask questions, iterate. Switch between Claude and GPT to compare perspectives on the same problem.
- **Build reusable prompts.** A `.chat` file with a system prompt and variables becomes a template. Share it with your team. Each person fills in their details and gets consistent results.
- **Work across providers.** Start a conversation with Anthropic, switch to OpenAI for a second opinion, try Vertex for the final draft. All in the same file, all without leaving Neovim.

---

## Providers

Four built-in providers. Switch at any time -- even mid-conversation:

```vim
:Flemma switch openai gpt-5 temperature=0.3
:Flemma switch $fast  " named presets
```

| Provider      | Default Model            |
| ------------- | ------------------------ |
| **Anthropic** | `claude-sonnet-4-6`      |
| **OpenAI**    | `gpt-5.4`                |
| **Vertex AI** | `gemini-3.1-pro-preview` |
| **Moonshot**  | `kimi-k2.5`              |

All four support extended thinking/reasoning through a single `thinking` parameter that Flemma maps to each provider's native format. Set `thinking = "high"` once and it works everywhere -- see the [full mapping table](docs/configuration.md#thinking-parameter-mapping) in configuration.md. Prompt caching is handled automatically -- read more in [prompt-caching.md](docs/prompt-caching.md).

Credentials are resolved automatically from environment variables or your platform keyring -- see **Setting up credentials** under Quick Start above.

Define presets for quick switching:

```lua
require("flemma").setup({
  presets = {
    ["$fast"] = "vertex gemini-2.5-flash thinking=minimal",
    ["$review"] = { provider = "anthropic", model = "claude-sonnet-4-6", max_tokens = 6000 },
  },
})
```

---

## The Agent

Flemma can work autonomously. When the model needs to read a file, edit code, or run a command, it uses tools -- and with autopilot enabled (the default), the entire cycle happens without you pressing a key:

1. You send a message.
2. The model responds with tool calls (read a file, run a test, write a fix).
3. Flemma executes approved tools and sends the results back.
4. The model decides what to do next. Repeat until the task is done.

You can watch the whole thing happen in the buffer. Every tool call, every result, every decision is visible text that you can read, edit, or undo.

### Built-in tools

| Tool    | What it does                            |
| ------- | --------------------------------------- |
| `bash`  | Runs shell commands                     |
| `read`  | Reads file contents                     |
| `edit`  | Find-and-replace in files               |
| `write` | Creates or overwrites files             |
| `grep`  | Searches with ripgrep (experimental)    |
| `find`  | Finds files by pattern (experimental)   |
| `ls`    | Lists directory contents (experimental) |

### Safety

- **Approval.** By default, file tools (`read`, `edit`, `write`, `grep`, `find`, `ls`) are auto-approved. `bash` is auto-approved when the sandbox is available, or requires your review otherwise. You see a preview of what the tool will do before approving: `bash: running tests -- $ make test`. Customize approval with presets (`$standard`, `$readonly`) or write your own logic.
- **Sandbox.** On Linux, shell commands run inside a Bubblewrap container with a read-only root filesystem. Only your project directory and `/tmp` are writable. Enabled by default. The sandbox is damage control, not a security boundary -- it limits the blast radius of common accidents, not deliberate attacks.
- **Turn limit.** Autopilot stops after 100 consecutive turns to prevent runaway cost.
- **You're in control.** Let it run fully autonomous, supervise and approve tools one at a time, or stop at any point, edit the conversation, and resume.

---

## Where Flemma Fits

Flemma is a **document-based AI workspace**. There are broadly two kinds of AI coding tools: inline assistants that suggest and apply diffs to your source files, and agent-style tools where you give a task and watch it work. Flemma is the second kind -- closest to the terminal agent pattern, but embedded in your editor.

What it does well:

- **Long-lived conversations.** Your `.chat` files stick around. Reopen them, share them, version them. Build a library of reusable prompts and templates.
- **Multi-provider flexibility.** Switch between Claude, GPT, Gemini, and Kimi mid-conversation. Compare models on the same problem without starting over.
- **Autonomous multi-step tasks.** Point it at a codebase, describe what you want, and let it iterate -- reading, writing, testing, fixing.
- **Non-coding work.** Technical writing, research, brainstorming, project planning. Flemma is not just a code tool.

What it doesn't try to do:

- **Inline diffs.** Flemma doesn't overlay proposed changes on your source files. It edits files through tools, like a terminal agent would.
- **Visual selection.** There's no "select code, ask a question" flow. You reference files with `@./path` or paste context into the conversation.

---

## Commands and Keymaps

All commands live under `:Flemma` with tab completion. Misspelled commands get did-you-mean suggestions.

| `:Flemma` Command                        | Purpose                                                                     |
| ---------------------------------------- | --------------------------------------------------------------------------- |
| `send`                                   | Send the buffer to the provider                                             |
| `cancel`                                 | Abort the active request or tool                                            |
| `switch ...`                             | Change provider, model, or parameters                                       |
| `status [verbose]`                       | Show runtime status and resolved configuration                              |
| `import`                                 | Import from Claude Workbench format (see [importing.md](docs/importing.md)) |
| `autopilot:enable\|disable\|status`      | Toggle or inspect autonomous mode                                           |
| `sandbox:enable\|disable\|status`        | Toggle or inspect sandboxing                                                |
| `tool:execute\|cancel\|cancel-all\|list` | Manage tool executions                                                      |
| `message:next\|previous`                 | Jump between messages                                                       |
| `logging:enable\|disable\|open`          | Structured logging                                                          |
| `diagnostics:enable\|disable\|diff`      | Request diagnostics (useful for debugging cache)                            |

### Keymaps (buffer-local to `.chat` files, all configurable)

| Mode               | Key                  | Action                                                |
| ------------------ | -------------------- | ----------------------------------------------------- |
| Normal<br />Insert | <kbd>Ctrl-]</kbd>    | Send to provider (or advance the tool approval cycle) |
| Normal             | <kbd>Ctrl-C</kbd>    | Cancel                                                |
| Normal             | <kbd>Alt-Enter</kbd> | Execute the tool under cursor                         |
| Normal             | `]m` / `[m`          | Next / previous message                               |
| Normal             | <kbd>Space</kbd>     | Toggle message fold                                   |
| Operator           | `im` / `am`          | Inner / around message text objects                   |

---

## Configuration

Flemma works without arguments -- `require("flemma").setup({})` uses sensible defaults. Here's a practical starting point:

```lua
require("flemma").setup({
  provider = "anthropic",               -- "anthropic" | "openai" | "vertex" | "moonshot"
  thinking = "high",                    -- unified across all providers
  presets = {
    ["$fast"] = "vertex gemini-2.5-flash thinking=minimal",
    ["$opus"] = "anthropic claude-opus-4-6 thinking=max",
  },
  sandbox = { backend = "required" },   -- warn if no sandbox backend is available
  editing = { auto_write = true },      -- save .chat files after each response
})
```

Individual `.chat` files can override any of these settings. Detailed references:

- [configuration.md](docs/configuration.md) -- every option explained with inline comments
- [tools.md](docs/tools.md) -- tool approval, custom tools, and the resolver API
- [templates.md](docs/templates.md) -- per-file settings, expressions, and file includes
- [sandbox.md](docs/sandbox.md) -- sandbox policies, path variables, and custom backends
- [ui.md](docs/ui.md) -- highlights, rulers, turns, notifications, and folding
- [session-api.md](docs/session-api.md) -- programmatic access to token usage and cost data

---

## Going Deeper

Flemma is designed to be extended. Everything plugs in through clean registries:

- **Custom tools** -- define your own with `require("flemma.tools").register()`. Read more in [tools.md](docs/tools.md#registering-custom-tools).
- **Approval policies** -- priority-based resolver chain for tool approval. Read more in [tools.md](docs/tools.md#approval-resolvers).
- **Hooks** -- lifecycle events (`FlemmaRequestSending`, `FlemmaToolFinished`, etc.) as standard `User` autocmds. Read more in [extending.md](docs/extending.md).
- **Custom providers** -- inherit from the base class or `openai_chat` for compatible APIs. Read more in [extending.md](docs/extending.md).
- **Sandbox backends** -- add platform-specific sandboxing beyond Bubblewrap. Read more in [sandbox.md](docs/sandbox.md#custom-backends).
- **Template system** -- Lua/JSON per-file configuration, inline expressions, file includes, composable system prompts. Read more in [templates.md](docs/templates.md).
- **Personalities** -- dynamic system prompt generators that assemble tools, environment, and project context (reads `CLAUDE.md`, `.cursorrules`, etc.). Read more in [personalities.md](docs/personalities.md).

Integrations with lualine and bufferline.nvim are documented in [integrations.md](docs/integrations.md). nvim-web-devicons gets a `.chat` file icon automatically.

---

## What It's Like to Use

After each response, a floating notification shows the model name, token counts, cost for this request, and cumulative session cost. When prompt caching kicks in, you'll see the cache hit rate -- green when it's saving you money, red when it's not.

Messages fold cleanly: thinking blocks and tool calls collapse automatically so you can focus on the conversation. Press <kbd>Space</kbd> to toggle a message fold, `za` for individual blocks. Rulers separate messages visually, and line highlights give each role a subtle background tint. Everything adapts to your colour scheme.

Flemma ships integrations for lualine (model and cost in the statusline) and bufferline (busy indicator on `.chat` tabs). Read more in [ui.md](docs/ui.md) and [integrations.md](docs/integrations.md).

---

## Developing and Testing

The repository uses a Nix shell for a reproducible development environment. Run `nix develop` to enter it.

From there, `make develop` launches Neovim with Flemma loaded from your working directory -- useful for trying out changes. `make qa` runs every quality gate in parallel (linting, type checking, import conventions, and the full test suite) and is the single command to run before committing.

> [!NOTE]
> Almost every line of code in Flemma has been authored through AI pair-programming tools. Traditional contributions are welcome -- keep changes focused, documented, and tested.

---

## FAQ

<details>
<summary><strong>Can I use different models for different conversations?</strong></summary>

Yes. Each `.chat` file can set its own provider, model, and parameters. You can also switch mid-conversation with `:Flemma switch openai gpt-5`. Read more in [configuration.md](docs/configuration.md).

</details>

<details>
<summary><strong>Can I attach files, images, or PDFs?</strong></summary>

Yes. Type `@./path/to/file` in your message and Flemma inlines the content before sending. Images and PDFs are base64-encoded and sent as multipart attachments where the provider supports it. MIME types are detected automatically. Read more in [templates.md](docs/templates.md).

</details>

<details>
<summary><strong>Can I build reusable prompt templates?</strong></summary>

Yes. A `.chat` file with a system prompt, variables, and expressions becomes a template. Define variables in a code block at the top of the file and reference them throughout your messages. You can also include other files and compose system prompts from building blocks. Read more in [templates.md](docs/templates.md).

</details>

<details>
<summary><strong>Can I control which tools the agent can use?</strong></summary>

Yes. Tools are governed by an approval system with built-in presets (`$standard` for file tools, `$readonly` for read-only access). You can auto-approve specific tools, require manual review for others, or write custom approval logic. Each `.chat` file can override the global policy. Read more in [tools.md](docs/tools.md).

</details>

<details>
<summary><strong>How do I store API keys securely?</strong></summary>

Flemma checks environment variables first, then your platform keyring (Linux Secret Service or macOS Keychain), then `gcloud` for Vertex AI. You never have to put keys in a config file. Read more in [extending.md](docs/extending.md#credential-resolution).

</details>

<details>
<summary><strong>Can I add my own tools or integrate with other systems?</strong></summary>

Yes. Register custom tools, approval resolvers, credential resolvers, sandbox backends, and more -- everything plugs in through registries. Read more in [tools.md](docs/tools.md#registering-custom-tools) and [extending.md](docs/extending.md).

</details>

<details>
<summary><strong>Who made this?</strong></summary>

[<img src="https://images.weserv.nl/?url=gravatar.com%2Favatar%2Fea3f8f366bb2aa0855db031884e3a8e8%3Fs%3D400%26d%3Drobohash%26r%3Dg&mask=circle" valign="middle" width="18" height="18" alt="Photo of @StanAngeloff">&thinsp;@StanAngeloff](https://github.com/StanAngeloff). Flemma started as a personal tool for thinking, writing, and experimenting with AI inside Neovim. It's been used for everything from architecture documents and project planning to bedtime stories.

</details>

---

## Troubleshooting

**Start with `:Flemma status`.** It shows a tree of everything Flemma knows about the current buffer -- provider, model, resolved parameters, sandbox state, enabled tools, approval policies, and which config layer set each value. Add `verbose` for the full picture. If something isn't working, this is the fastest way to find out why.

| Problem                 | Fix                                                                                           |
| ----------------------- | --------------------------------------------------------------------------------------------- |
| Nothing happens on send | Buffer must end with `.chat`. Messages need `@You:` on its own line, content below.           |
| Vertex refuses requests | Check `parameters.vertex.project_id`. Run `gcloud auth print-access-token` manually.          |
| Sandbox blocks writes   | `:Flemma sandbox:status` to check writable paths.                                             |
| Keymaps clash           | `keymaps.enabled = false` to disable all built-in mappings.                                   |
| Temperature ignored     | Thinking (default `"high"`) disables temperature on Anthropic/OpenAI. Set `thinking = false`. |

---

## Under the Surface

<details>
<summary>For the curious -- things Flemma does that you'll probably never think about, but that make the experience work.</summary>

- **Copy-on-Write configuration.** Config isn't merged tables. It's an operation log across four priority layers where scalars resolve top-down and lists accumulate with `append`/`remove`/`prepend` semantics. That's how a single `.chat` file can remove one tool from the approval list without replacing the whole thing.
- **Jinja-style template engine.** Beyond simple `{{ expressions }}`, Flemma supports `{% code %}` blocks for loops, conditionals, and variable assignment -- with whitespace trimming (`{%- -%}`), graceful error degradation, and strict undefined-variable detection. It compiles templates to Lua and runs them in a sandboxed environment.
- **Sinks.** Streaming data from providers is accumulated in hidden scratch buffers with batched flushing on a 50ms timer, handling partial lines across network chunks. Buffers are lazily created on first write and cleaned up automatically. If you wanted to, you can hook into these buffers to get a live view of the response as it streams in.
- **Full AST.** Every `.chat` file is parsed into a structured document tree -- messages, segments, tool blocks, thinking blocks, expressions, all with position tracking and diagnostics. During streaming, only the newly appended lines are re-parsed; the rest is frozen in a snapshot.
- **In-process LSP.** Flemma runs an LSP server inside Neovim for `.chat` buffers. Hover shows AST node details for the element under cursor. Go-to-definition jumps between tool use and result blocks, and resolves `include()` paths and `@./file` references. `gf` works on file references too.
- **Output truncation.** Large tool outputs (over 2,000 lines or 50KB) are automatically truncated to keep the context window manageable. The full output is saved to a temp file so nothing is lost.
- **Prompt caching optimization.** Tool definitions are sorted alphabetically, JSON keys are ordered for maximum shared prefix, and environment data (date, time) is cached per buffer -- all to keep the request body byte-identical between turns so provider-side caching actually works.
- **Cross-provider thinking preservation.** Thinking blocks carry provider-namespaced signatures (`anthropic:signature="..."`, `openai:signature="..."`). When you switch providers mid-conversation, old signatures stay in the buffer but are filtered out of the new provider's request -- so you can switch back without losing reasoning state.

</details>

---

## License

[AGPL-3.0](LICENSE)

Happy prompting!
