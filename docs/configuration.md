# Configuration Reference

Flemma works without arguments – `require("flemma").setup({})` uses sensible defaults (Anthropic provider, `thinking = "high"`, prompt caching enabled). Every option is documented with inline comments below.

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
    require_approval = true,                 -- When false, auto-approves all tools
    auto_approve = nil,                      -- string[] | function | nil
    default_timeout = 30,                    -- Async tool timeout (seconds)
    show_spinner = true,                     -- Animated spinner during execution
    cursor_after_result = "result",          -- "result" | "stay" | "next"
    autopilot = {
      enabled = true,                        -- Auto-execute approved tools and re-send
      max_turns = 100,                       -- Safety limit on consecutive autonomous turns
    },
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
    tool_preview = "Comment",
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
  sandbox = {
    enabled = true,                          -- Enable filesystem sandboxing
    backend = "auto",                        -- "auto" | "required" | explicit name
    policy = {
      rw_paths = {                           -- Read-write paths (all others read-only)
        "$CWD",                              --   Vim working directory
        "$FLEMMA_BUFFER_PATH",               --   Directory of the .chat file
        "/tmp",                              --   System temp directory
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
      next_message = "]m",
      prev_message = "[m",
    },
    insert = {
      send = "<C-]>",                        -- Same hybrid behaviour, re-enters insert after
    },
  },
})
```

## Option details

This section explains options that benefit from more context than an inline comment provides. For UI-related options (highlights, line highlights, signs, ruler, spinner, notifications), see [docs/ui.md](ui.md) for detailed explanations and examples.

### Thinking parameter priority

Provider-specific parameters take priority over the unified `thinking` value when both are set:

1. `parameters.anthropic.thinking_budget` overrides `thinking` for Anthropic (clamped to min 1,024 tokens).
2. `parameters.openai.reasoning` overrides `thinking` for OpenAI (accepts `"low"`, `"medium"`, `"high"`).
3. `parameters.vertex.thinking_budget` overrides `thinking` for Vertex AI (min 1 token).

This lets you set `thinking = "high"` as a cross-provider default and fine-tune specific providers when needed.

### Editing behaviour

| Key                         | Default | Effect                                                                                                                                                                                                                |
| --------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `editing.disable_textwidth` | `true`  | Sets `textwidth = 0` in chat buffers to prevent hard wrapping.                                                                                                                                                        |
| `editing.auto_write`        | `false` | When `true`, automatically writes the buffer to disk after each completed request.                                                                                                                                    |
| `editing.manage_updatetime` | `true`  | Lowers `updatetime` to 100ms while a chat buffer is focused (enables responsive `CursorHold` events for UI updates). The original value is restored on `BufLeave`, with reference counting for multiple chat buffers. |
| `editing.foldlevel`         | `1`     | Initial fold level: `0` = all folds closed, `1` = thinking blocks and frontmatter collapsed, `99` = all folds open.                                                                                                   |

### Notification options

The `notify` key accepts a table with these fields (defaults shown from `lua/flemma/notify.lua`):

| Key         | Default     | Effect                                                  |
| ----------- | ----------- | ------------------------------------------------------- |
| `enabled`   | `true`      | Set `false` to suppress all floating notifications.     |
| `timeout`   | `8000`      | Milliseconds before auto-dismiss.                       |
| `max_width` | `60`        | Character width cap; longer lines are word-wrapped.     |
| `padding`   | `1`         | Spaces around content inside the floating window.       |
| `border`    | `"rounded"` | Any Neovim border style (`"single"`, `"double"`, etc.). |
| `title`     | `nil`       | Optional window title string.                           |

### Keymaps and hybrid dispatch

The `send` keymap (<kbd>Ctrl-]</kbd>) is a hybrid dispatch with a three-phase cycle:

1. **Inject:** If the response contains `**Tool Use:**` blocks without corresponding results, insert empty `**Tool Result:**` placeholders for review.
2. **Execute:** If there are tool result placeholders with a `flemma:tool` status (`approved`, `denied`, `rejected`), process them accordingly. `pending` blocks pause the cycle for user review.
3. **Send:** If no tools are pending, send the conversation to the provider.

Each press of <kbd>Ctrl-]</kbd> advances to the next applicable phase. In insert mode, <kbd>Ctrl-]</kbd> behaves identically but re-enters insert mode when the operation finishes.

Set `keymaps.enabled = false` to disable all built-in mappings. For send-only behaviour (skipping the tool dispatch phases), bind directly to `require("flemma.core").send_to_provider()`.

### Autopilot

Autopilot turns Flemma into an autonomous agent. After each LLM response containing tool calls, it executes approved tools (as determined by `auto_approve` and any registered approval resolvers), collects all results, and re-sends the conversation. This loop repeats until the model stops calling tools or a tool requires manual approval. A single <kbd>Ctrl-]</kbd> can trigger dozens of autonomous tool calls – the model reads files, writes code, runs tests, and iterates, all without further input.

| Key                         | Default | Effect                                                                                                                                                                |
| --------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tools.autopilot.enabled`   | `true`  | Enable the autonomous execute-and-resend loop. Set `false` to restore the manual three-phase <kbd>Ctrl-]</kbd> cycle.                                                 |
| `tools.autopilot.max_turns` | `100`   | Maximum consecutive LLM turns before autopilot stops and emits a warning. Prevents runaway loops when a model repeatedly calls tools without converging on an answer. |

When a tool requires user approval, autopilot injects a `flemma:tool status=pending` placeholder and pauses the loop. The buffer is unlocked at this point, so you can review the tool call and even edit the content inside the pending block. Press <kbd>Ctrl-]</kbd> to approve and resume. If you have edited the content of a `flemma:tool` block, Flemma detects your changes and will not overwrite them – it warns and stays paused so you can review.

Press <kbd>Ctrl-C</kbd> at any point to cancel the active request or tool execution. Cancellation fully disarms autopilot, so pressing <kbd>Ctrl-]</kbd> afterwards starts a fresh send rather than resuming the interrupted loop.

Toggle autopilot at runtime without changing your config:

- `:Flemma autopilot:enable` – activate for the current session.
- `:Flemma autopilot:disable` – deactivate for the current session.
- `:Flemma autopilot:status` – print whether autopilot is currently active and the buffer's loop state.

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

| Key                               | Default                                     | Effect                                                                                |
| --------------------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------- |
| `sandbox.enabled`                 | `true`                                      | Master switch for sandboxing.                                                         |
| `sandbox.backend`                 | `"auto"`                                    | `"auto"` = detect silently, `"required"` = detect and warn, or explicit backend name. |
| `sandbox.policy.rw_paths`         | `{ "$CWD", "$FLEMMA_BUFFER_PATH", "/tmp" }` | Paths with read-write access. Supports path variables.                                |
| `sandbox.policy.network`          | `true`                                      | Allow network access inside the sandbox.                                              |
| `sandbox.policy.allow_privileged` | `false`                                     | Allow `sudo` and capabilities inside the sandbox.                                     |

Override per-buffer via `flemma.opt.sandbox` in frontmatter (boolean shorthand `true`/`false` supported). Toggle at runtime with `:Flemma sandbox:enable/disable/status`.

See [docs/sandbox.md](sandbox.md) for the full reference on policy options, path variables, custom backends, and security considerations.

### Per-buffer overrides

Beyond global configuration, individual buffers can override parameters, tool selection, approval policies, and sandbox settings through `flemma.opt` in Lua frontmatter. See [docs/templates.md](templates.md#per-buffer-overrides-with-flemmaopt) for the full reference.
