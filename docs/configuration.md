# Configuration Reference

Flemma works without arguments – `require("flemma").setup({})` uses sensible defaults (Anthropic provider, `thinking = "high"`, prompt caching enabled). Every option is documented with inline comments below.

```lua
require("flemma").setup({
  provider = "anthropic",                    -- "anthropic" | "openai" | "vertex"
  model = nil,                               -- nil = provider default
  parameters = {
    max_tokens = "50%",                           -- Percentage of model's max_output_tokens, or integer
    temperature = 0.7,
    timeout = 600,                           -- Response timeout (seconds)
    connect_timeout = 10,                    -- Connection timeout (seconds)
    thinking = "high",                       -- "minimal" | "low" | "medium" | "high" | "max" | number | false
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
    require_approval = true,                 -- When false, auto-approves all tools
    auto_approve = { "$standard" },          -- $standard approves read, write, edit, find, grep, ls
    auto_approve_sandboxed = true,           -- Auto-approve sandboxed tools (set false to require manual approval)
    max_concurrent = 2,                      -- Max tools executing simultaneously per buffer (0 = unlimited)
    default_timeout = 30,                    -- Async tool timeout (seconds)
    show_spinner = true,                     -- Animated spinner during execution
    cursor_after_result = "result",          -- "result" | "stay" | "next"
    autopilot = {
      enabled = true,                        -- Auto-execute approved tools and re-send
      max_turns = 100,                       -- Safety limit on consecutive autonomous turns
    },
    bash = {
      shell = nil,                           -- Shell binary (default: bash)
      cwd = "urn:flemma:buffer:path",        -- Working directory; resolves to .chat file's directory (set nil for Neovim cwd)
      env = nil,                             -- Extra environment variables
    },
    grep = {                                 -- [experimental.tools] Grep tool configuration
      cwd = "urn:flemma:buffer:path",        -- Working directory for searches
      exclude = { ".git", "node_modules", "__pycache__", ".venv", "target", "dist", "build", "vendor" },
    },
    find = {                                 -- [experimental.tools] Find tool configuration
      cwd = "urn:flemma:buffer:path",        -- Working directory for file searches
      exclude = { ".git", "node_modules", "__pycache__", ".venv", "target", "dist", "build", "vendor" },
    },
    ls = {                                   -- [experimental.tools] Ls tool configuration
      cwd = "urn:flemma:buffer:path",        -- Working directory for directory listings
    },
    modules = {},                            -- Lua module paths for third-party tool sources (e.g., "3rd.tools.todos")
  },
  templating = {
    modules = {},                            -- Lua module paths for environment populators (see docs/templates.md)
  },
  defaults = {
    dark = { bg = "#000000", fg = "#ffffff" },
    light = { bg = "#ffffff", fg = "#000000" },
  },
  highlights = {
    system = "Special",
    user = "Normal",
    assistant = "Normal",
    lua_expression = "PreProc",
    lua_code_block = "PreProc",              -- {% code %} block content
    lua_delimiter = "FlemmaLuaExpression",   -- {{ }} and {% %} delimiters
    user_file_reference = "Include",
    thinking_tag = "Comment",
    thinking_block = { dark = "Comment+bg:#102020-fg:#111111",
                       light = "Comment-bg:#102020+fg:#111111" },
    tool_icon = "FlemmaToolUseTitle",
    tool_name = "Function",
    tool_use_title = "Function",
    tool_result_title = "Function",
    tool_result_error = "DiagnosticError",
    tool_preview = "Comment",
    tool_detail = "Comment",                 -- Raw technical detail in structured tool previews
    fold_preview = "Comment",
    fold_meta = "Comment",
    busy = "DiagnosticWarn",                 -- Busy indicator icon in integrations (e.g., bufferline)
  },
  role_style = "bold",
  ruler = {
    enabled = true,
    char = "─",
    hl = { dark = "Comment-fg:#303030", light = "Comment+fg:#303030" },
  },
  turns = {
    enabled = true,
    padding = { left = 1, right = 0 },
    hl = "FlemmaTurn",
  },
  line_highlights = {
    enabled = true,
    frontmatter = { dark = "Normal+bg:#201020", light = "Normal-bg:#201020" },
    system = { dark = "Normal+bg:#201000", light = "Normal-bg:#201000" },
    user = { dark = "Normal", light = "Normal" },
    assistant = { dark = "Normal+bg:#102020", light = "Normal-bg:#102020" },
  },
  notifications = {
    enabled = true,                            -- Set false to suppress all notifications
    timeout = 10000,                           -- Milliseconds before auto-dismiss (0 = persistent)
    limit = 1,                                 -- Maximum stacked notifications per buffer
    position = "overlay",                      -- "overlay" (pinned to window top)
    zindex = 30,                               -- Floating window z-index (above nvim-treesitter-context)
    highlight = "@text.note,PmenuSel",         -- Highlight group(s) for bar colours; first with both fg+bg wins
    border = false,                            -- Bottom border style, or false to disable
  },
  progress = {
    highlight = "StatusLine",                  -- Highlight group(s) for the progress bar; first with both fg+bg is used
    zindex = 50,                               -- Progress bar sits above notifications (zindex 30)
  },
  pricing = { enabled = true },
  statusline = {
    format = '#{model}#{?#{thinking}, (#{thinking}),}#{?#{booting}, ⏳,}', -- tmux-style format string (see docs/integrations.md)
  },
  text_object = "m",                         -- "m" or false to disable
  editing = {
    auto_prompt = true,                      -- Prepend @You: to empty .chat buffers on open
    disable_textwidth = true,
    auto_write = false,                      -- Write buffer after each request
    manage_updatetime = true,                -- Lower updatetime in chat buffers
    foldlevel = 1,                           -- 0=all closed, 1=thinking collapsed, 99=all open
    auto_close = {
      thinking = true,                       -- Auto-close thinking blocks when they become terminal
      tool_use = true,                       -- Auto-close tool_use blocks when completed
      tool_result = true,                    -- Auto-close tool_result blocks when terminal
      frontmatter = false,                   -- Auto-close frontmatter blocks (disabled by default)
    },
  },
  logging = {
    enabled = false,
    path = vim.fn.stdpath("cache") .. "/flemma.log",
    level = "DEBUG",                         -- Minimum log level: "TRACE", "DEBUG", "INFO", "WARN", "ERROR"
  },
  diagnostics = {
    enabled = false,                         -- Enable request diagnostics for debugging prompt caching issues
  },
  secrets = {
    gcloud = {
      path = "gcloud",                       -- Path to gcloud binary (override for NixOS, Guix, etc.)
    },
  },
  sandbox = {
    enabled = true,                          -- Enable filesystem sandboxing
    backend = "auto",                        -- "auto" | "required" | explicit name
    policy = {
      rw_paths = {                              -- Read-write paths (all others read-only)
        "urn:flemma:cwd",                       --   Vim working directory
        "urn:flemma:buffer:path",               --   Directory of the .chat file
        "/tmp",                                 --   System temp directory
        "${TMPDIR:-/tmp}",                      --   TMPDIR (deduped with /tmp if same)
        "${XDG_CACHE_HOME:-~/.cache}",          --   Package manager caches
        "${XDG_DATA_HOME:-~/.local/share}",     --   Package manager stores
      },
      network = true,                        -- Allow network access
      allow_privileged = false,              -- Allow sudo/capabilities
    },
    backends = {
      bwrap = {
        path = "bwrap",                      -- Bubblewrap binary path
        extra_args = {},                     -- Additional bwrap arguments
      },
    },
  },
  keymaps = {
    enabled = true,
    normal = {
      send = "<C-]>",                        -- Hybrid: execute pending tools or send
      cancel = "<C-c>",
      tool_execute = "<M-CR>",               -- Execute tool at cursor
      message_next = "]m",
      message_prev = "[m",
      fold_toggle = "<Space>",               -- Toggle fold; false to disable
    },
    insert = {
      send = "<C-]>",                        -- Same hybrid behaviour, re-enters insert after
    },
  },
  experimental = {
    lsp = vim.lsp ~= nil,                   -- In-process LSP for .chat buffers (hover, go-to-definition)
    tools = false,                          -- Enable exploration tools (grep, find, ls) — see docs/tools.md
  },
})
```

## Option details

This section explains options that benefit from more context than an inline comment provides. For UI-related options (highlights, line highlights, turns, ruler, notifications), see [docs/ui.md](ui.md) for detailed explanations and examples.

### Thinking parameter priority

Provider-specific parameters take priority over the unified `thinking` value when both are set:

1. `parameters.anthropic.thinking_budget` overrides `thinking` for Anthropic (clamped to min 1,024 tokens).
2. `parameters.openai.reasoning` overrides `thinking` for OpenAI (accepts `"low"`, `"medium"`, `"high"`).
3. `parameters.vertex.thinking_budget` overrides `thinking` for Vertex AI (min 1 token).

This lets you set `thinking = "high"` as a cross-provider default and fine-tune specific providers when needed.

### Editing behaviour

| Key                         | Default | Effect                                                                                                                                                                                                                |
| --------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `editing.auto_prompt`       | `true`  | Prepend `@You:` to empty `.chat` buffers when opened, so new users have a clear starting point.                                                                                                                       |
| `editing.disable_textwidth` | `true`  | Sets `textwidth = 0` in chat buffers to prevent hard wrapping.                                                                                                                                                        |
| `editing.auto_write`        | `false` | When `true`, automatically writes the buffer to disk after each completed request.                                                                                                                                    |
| `editing.manage_updatetime` | `true`  | Lowers `updatetime` to 100ms while a chat buffer is focused (enables responsive `CursorHold` events for UI updates). The original value is restored on `BufLeave`, with reference counting for multiple chat buffers. |
| `editing.foldlevel`         | `1`     | Initial fold level: `0` = all folds closed, `1` = thinking blocks and frontmatter collapsed, `99` = all folds open.                                                                                                   |
| `editing.auto_close.*`      | varies  | Auto-close (fold) blocks when they reach a terminal state. See [Auto-close behaviour](#auto-close-behaviour) below.                                                                                                   |

### Notification options

The `notifications` key accepts a table with these fields:

| Key         | Default                 | Effect                                                                                                                                                    |
| ----------- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enabled`   | `true`                  | Set `false` to suppress all notification bars.                                                                                                            |
| `timeout`   | `10000`                 | Milliseconds before auto-dismiss. Set `0` for persistent notifications.                                                                                   |
| `limit`     | `1`                     | Maximum stacked notifications per buffer. Oldest are dismissed when the limit is exceeded.                                                                |
| `position`  | `"overlay"`             | Notification placement. Currently only `"overlay"` (pinned to the top of the chat window).                                                                |
| `zindex`    | `30`                    | Floating window z-index for notification bars (above nvim-treesitter-context).                                                                            |
| `highlight` | `"@text.note,PmenuSel"` | Comma-separated highlight groups to derive bar colours from. The first group that provides both `fg` and `bg` is used; remaining groups act as fallbacks. |
| `border`    | `false`                 | Bottom border style: `"underline"`, `"underdouble"`, `"undercurl"`, `"underdotted"`, `"underdashed"`, or `false` to disable.                              |

### Keymaps and hybrid dispatch

The `send` keymap (<kbd>Ctrl-]</kbd>) is a hybrid dispatch with a three-phase cycle:

1. **Inject:** If the response contains `**Tool Use:**` blocks without corresponding results, insert empty `**Tool Result:**` placeholders for review.
2. **Execute:** If there are tool result placeholders with a `flemma:tool` status (`approved`, `denied`, `rejected`), process them accordingly. `pending` blocks pause the cycle for user review.
3. **Send:** If no tools are pending, send the conversation to the provider.

Each press of <kbd>Ctrl-]</kbd> advances to the next applicable phase. In insert mode, <kbd>Ctrl-]</kbd> behaves identically but re-enters insert mode when the operation finishes.

Set `keymaps.enabled = false` to disable all built-in mappings. For send-only behaviour (skipping the tool dispatch phases), bind directly to `require("flemma.core").send_to_provider()`.

#### Insert-mode colon auto-newline

When keymaps are enabled, typing `:` after a role name (`@You`, `@System`, `@Assistant`) in insert mode automatically completes the marker, inserts a blank content line below, and positions the cursor there. A **grace period** of 800ms absorbs any immediately following Space or Enter keypress – this protects muscle memory from the previous inline format where you'd type `@You: ` with a trailing space.

#### Format migration

Old `.chat` files that use the previous inline role marker format (e.g., `@You: content on same line`) are **automatically migrated** to the new own-line format when opened. The migration is non-destructive: it splits inline content onto a new line without altering the text. Run `:Flemma format` to trigger migration manually on the current buffer.

### Autopilot

Autopilot turns Flemma into an autonomous agent. After each LLM response containing tool calls, it executes approved tools (as determined by `auto_approve` and any registered approval resolvers), collects all results, and re-sends the conversation. This loop repeats until the model stops calling tools or a tool requires manual approval. A single <kbd>Ctrl-]</kbd> can trigger dozens of autonomous tool calls – the model reads files, writes code, runs tests, and iterates, all without further input.

| Key                         | Default | Effect                                                                                                                                                                |
| --------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tools.autopilot.enabled`   | `true`  | Enable the autonomous execute-and-resend loop. Set `false` to restore the manual three-phase <kbd>Ctrl-]</kbd> cycle.                                                 |
| `tools.autopilot.max_turns` | `100`   | Maximum consecutive LLM turns before autopilot stops and emits a warning. Prevents runaway loops when a model repeatedly calls tools without converging on an answer. |

When a tool requires user approval, autopilot injects a `flemma:tool status=pending` placeholder and pauses the loop. The buffer is unlocked at this point, so you can review the tool call. Press <kbd>Ctrl-]</kbd> to approve and resume. If you paste output inside a `pending` block, <kbd>Ctrl-]</kbd> treats it as a user-provided result – the `flemma:tool` fence is stripped and your content is sent to the model. If you edit the content of an `approved` block, Flemma detects your changes, skips execution to protect your edits, and warns so you can review.

Press <kbd>Ctrl-C</kbd> at any point to cancel the active request or tool execution. Cancellation fully disarms autopilot, so pressing <kbd>Ctrl-]</kbd> afterwards starts a fresh send rather than resuming the interrupted loop.

Toggle autopilot at runtime without changing your config:

- `:Flemma autopilot:enable` – activate for the current session.
- `:Flemma autopilot:disable` – deactivate for the current session.
- `:Flemma autopilot:status` – open the status buffer and jump to the Autopilot section (shows enabled state, buffer loop state, max turns, and any frontmatter overrides).

Individual buffers can override the global setting via frontmatter: `flemma.opt.tools.autopilot = false`. See [docs/templates.md](templates.md#per-buffer-overrides-with-flemmaopt) for details.

### Command callbacks

`:Flemma send` accepts optional callback parameters that run Neovim commands at request boundaries:

```vim
:Flemma send on_request_start=stopinsert on_request_complete=startinsert!
```

| Callback              | When it runs                    | Example use case                    |
| --------------------- | ------------------------------- | ----------------------------------- |
| `on_request_start`    | Just before the request is sent | Exit insert mode during streaming   |
| `on_request_complete` | After the response finishes     | Re-enter insert mode for your reply |

Values are passed to `vim.cmd()`, so any Ex command works.

### Presets

Presets accept two formats:

**String form** – parsed like `:Flemma switch` arguments. Compact and good for simple overrides:

```lua
presets = {
  ["$fast"] = "vertex gemini-2.5-flash temperature=0.2",
}
```

**Table form** – explicit keys for full control:

```lua
presets = {
  ["$review"] = {
    provider = "anthropic",
    model = "claude-sonnet-4-6",
    max_tokens = 6000,
  },
}
```

Preset names must begin with `$`. Switch using `:Flemma switch $fast` and override individual values with additional `key=value` arguments: `:Flemma switch $review temperature=0.1`.

### Sandbox

Sandboxing constrains tool execution so that shell commands run inside a read-only filesystem with write access limited to an explicit allowlist. It is enabled by default and auto-detects a compatible backend (currently Bubblewrap on Linux). On platforms without a backend, Flemma silently degrades to unsandboxed execution.

| Key                               | Default                                                       | Effect                                                                                |
| --------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `sandbox.enabled`                 | `true`                                                        | Master switch for sandboxing.                                                         |
| `sandbox.backend`                 | `"auto"`                                                      | `"auto"` = detect silently, `"required"` = detect and warn, or explicit backend name. |
| `sandbox.policy.rw_paths`         | `{ "urn:flemma:cwd", "urn:flemma:buffer:path", "/tmp", ... }` | Paths with read-write access. Supports URNs, `$ENV`, `${ENV:-default}`.               |
| `sandbox.policy.network`          | `true`                                                        | Allow network access inside the sandbox.                                              |
| `sandbox.policy.allow_privileged` | `false`                                                       | Allow `sudo` and capabilities inside the sandbox.                                     |

Override per-buffer via `flemma.opt.sandbox` in frontmatter (boolean shorthand `true`/`false` supported). Toggle at runtime with `:Flemma sandbox:enable/disable/status`.

See [docs/sandbox.md](sandbox.md) for the full reference on policy options, path variables, custom backends, and security considerations.

### Auto-close behaviour

When blocks reach a terminal state (e.g., a thinking block finishes streaming, a tool result is injected), Flemma can automatically close (fold) them to keep the buffer tidy. Each block type is independently configurable:

| Key                              | Default | Effect                                                                     |
| -------------------------------- | ------- | -------------------------------------------------------------------------- |
| `editing.auto_close.thinking`    | `true`  | Auto-close `<thinking>` blocks when they finish streaming.                 |
| `editing.auto_close.tool_use`    | `true`  | Auto-close `**Tool Use:**` blocks after the tool executes.                 |
| `editing.auto_close.tool_result` | `true`  | Auto-close `**Tool Result:**` blocks when they reach a terminal state.     |
| `editing.auto_close.frontmatter` | `false` | Auto-close frontmatter blocks. Disabled by default so you can edit freely. |

### Tool concurrency

`tools.max_concurrent` (default `2`) limits how many tools execute simultaneously per buffer. When the model returns more tool calls than the limit, Flemma queues the excess and starts them as earlier tools complete. Set to `0` for unlimited concurrency.

Override per-buffer via `flemma.opt.tools.max_concurrent` in frontmatter.

### Progress bar

A persistent progress indicator appears as a floating bar while a request is streaming. It shows the current phase (thinking, streaming text, tool input) and repositions automatically if the target line scrolls off-screen.

| Key                  | Default        | Effect                                                                  |
| -------------------- | -------------- | ----------------------------------------------------------------------- |
| `progress.highlight` | `"StatusLine"` | Highlight group(s) for the progress bar; first with both fg+bg is used. |
| `progress.zindex`    | `50`           | Floating window z-index (above notifications at 30).                    |

### Diagnostics

Enable request diagnostics to inspect what Flemma sends to and receives from the provider. Useful for debugging prompt caching issues or understanding how the buffer maps to API requests.

| Key                   | Default | Effect                                                                       |
| --------------------- | ------- | ---------------------------------------------------------------------------- |
| `diagnostics.enabled` | `false` | Enable request diagnostics. Use `:Flemma diagnostics:diff` to view the diff. |

Toggle at runtime with `:Flemma diagnostics:enable` / `:Flemma diagnostics:disable`.

### Experimental LSP

Flemma includes an in-process LSP server for `.chat` buffers. It provides hover information (AST node details, segment types, message positions) and basic go-to-definition for `include()` expressions and `@./path` file references.

| Key                | Default          | Effect                                                           |
| ------------------ | ---------------- | ---------------------------------------------------------------- |
| `experimental.lsp` | `vim.lsp ~= nil` | Enable the LSP server. Auto-enabled when `vim.lsp` is available. |

The LSP attaches automatically to `.chat` buffers. Use your usual LSP keybindings (e.g., `K` for hover) to inspect buffer structure.

### Experimental exploration tools

Three additional built-in tools (`grep`, `find`, `ls`) are available for codebase exploration. They are disabled by default and must be opted into explicitly.

| Key                  | Default | Effect                                                                                                                      |
| -------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------- |
| `experimental.tools` | `false` | Enable `grep`, `find`, and `ls` tools. See [docs/tools.md](tools.md#experimental-exploration-tools) for the full reference. |

Each tool has an optional config section under `tools` (`tools.grep`, `tools.find`, `tools.ls`) for working directory and exclude patterns.

### Config aliases

Flemma defines top-level aliases for frequently used nested options. These work in both `setup()` config and `flemma.opt` frontmatter overrides:

| Alias         | Expands to               |
| ------------- | ------------------------ |
| `thinking`    | `parameters.thinking`    |
| `temperature` | `parameters.temperature` |
| `max_tokens`  | `parameters.max_tokens`  |
| `timeout`     | `parameters.timeout`     |

Under `tools`, an additional alias is available:

| Alias     | Expands to     |
| --------- | -------------- |
| `approve` | `auto_approve` |

This is why `flemma.opt.thinking = "medium"` works in frontmatter — it writes to `parameters.thinking` through the alias. Both the alias and the full path are equivalent; use whichever you prefer.

### Per-buffer overrides

Beyond global configuration, individual buffers can override parameters, tool selection, approval policies, and sandbox settings through `flemma.opt` in Lua frontmatter. See [docs/templates.md](templates.md#per-buffer-overrides-with-flemmaopt) for the full reference.
