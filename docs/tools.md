# Tools

Flemma's tool system lets models request actions – run a calculation, execute a shell command, read or modify files – and receive structured results, all within the `.chat` buffer. This document covers approval, per-buffer configuration, custom tool registration, and the resolver API.

For a quick overview of built-in tools and the basic workflow, see [The Agent](../README.md#the-agent) section in the README.

---

## Tool approval

By default, Flemma requires you to review tool calls before execution. A single keypress (<kbd>Ctrl-]</kbd>) drives the entire flow through three phases:

### The three-phase cycle

**Phase 1 – Categorize.** When the model responds with `**Tool Use:**` blocks, pressing <kbd>Ctrl-]</kbd> checks each tool call against your approval settings and injects a `**Tool Result:**` placeholder with a status:

| Status     | Meaning                                              |
| ---------- | ---------------------------------------------------- |
| `approved` | Auto-approved by policy; will execute immediately    |
| `pending`  | Requires your review; blocks the cycle until you act |
| `denied`   | Blocked by policy; an error result is injected       |

The cursor moves to the first `pending` placeholder so you can review it.

**Phase 2 – Execute.** On the next <kbd>Ctrl-]</kbd> (or automatically via `vim.schedule` when Phase 1 produced only `approved`/`denied` tools), Flemma processes each placeholder by status:

- **`approved`** → the tool executes and its output replaces the placeholder.
- **`denied`** → an error result is injected (the model sees the tool was blocked).
- **`rejected`** → an error result is injected, using any content you wrote inside the block as the error message.
- **`pending`** → blocks the cycle. The cursor moves here and Flemma waits for you to act.

**Phase 3 – Send.** When no lifecycle-status placeholders remain (every tool has a real result), the next <kbd>Ctrl-]</kbd> sends the conversation to the provider.

With [autopilot](configuration.md#autopilot) enabled (the default), Phases 1–3 chain automatically for approved tools. You only interact when a tool lands on `pending`.

### Tool status suffix

Each placeholder carries its status in a parenthesized suffix on the `**Tool Result:**` header. The fenced block below the header is a plain code block — empty for pending placeholders, populated for errors or resolved results:

````
**Tool Result:** `toolu_01` (pending)

```
```
````

The suffix is modeline-parseable: a bare word like `(pending)` upgrades to `status=pending`; explicit keys like `(status=pending sandbox=false)` mix status with future metadata. Unrecognized tokens round-trip through the `meta` field on the tool_result AST node.

You can **edit the status directly** in the header. This is the primary way to interact with pending tools:

- **Approve:** change `(pending)` to `(approved)`, then press <kbd>Ctrl-]</kbd>.
- **Reject:** change `(pending)` to `(rejected)`, then press <kbd>Ctrl-]</kbd>. Flemma injects an error result telling the model the tool was rejected.
- **Reject with a message:** change the status to `rejected` and type your reason inside the fence – the model sees your text as the error:

  ````
  **Tool Result:** `toolu_01` (rejected)

  ```
  I don't want to run rm -rf on my home directory.
  ```
  ````

- **Execute one tool:** press <kbd>Alt-Enter</kbd> on any tool block to execute or resolve it immediately (works for `approved`, `pending`, `rejected`, and `denied`).
- **Approve via command:** `:Flemma tool:approve` toggles the tool under the cursor to `(approved)` without executing it – the next <kbd>Ctrl-]</kbd> runs it.
- **Reject via command:** `:Flemma tool:reject` toggles the tool under the cursor to `(rejected)`. Append an optional message (`:Flemma tool:reject do not run rm -rf`) and it's written into the fence as the rejection reason the model will see.

### Content-overwrite protection

If you paste or type output inside a `pending` block, Flemma treats it as a user-provided result: on <kbd>Ctrl-]</kbd> the `(pending)` suffix is cleared from the header and your content is sent to the model as a normal tool result. This is useful when you run a command manually and want to provide the output yourself.

If you edit the content inside an `approved` block, Flemma skips execution to protect your edits – a warning is shown and the cycle pauses so you can review. Clear the `(approved)` suffix from the header manually to send your content.

### Configuring approval

Out of the box, `auto_approve` is set to `{ "$standard" }`, which auto-approves `read`, `write`, `edit`, `find`, `grep`, and `ls` while keeping `bash` gated behind manual approval. This gives you a working agent loop without opting out of safety for shell commands.

Disable approval entirely with `tools.require_approval = false` – this registers a catch-all resolver at priority 0 that auto-approves every tool call. Alternatively, use `tools.auto_approve` to build a custom policy with presets, tool names, or a function:

```lua
tools = {
  -- Preset references and tool names can be mixed freely
  auto_approve = { "$readonly", "bash" },

  -- Function form for full control
  auto_approve = function(tool_name, input, ctx)
    if tool_name == "grep" then return true end
    if tool_name == "bash" and input.command:match("rm %-rf") then return "deny" end
    return false  -- require approval
  end,
}
```

Entries containing `*` are treated as glob patterns — `"flemma.*"` matches any tool whose name starts with `flemma.`. This is how the built-in `$standard` preset auto-approves all harness tools.

### Approval presets

Presets are named collections of tool approval rules referenced with a `$` prefix in `auto_approve`. They keep common policies concise and composable.

**Built-in presets:**

| Preset      | Approves                                                  | Description                                                           |
| ----------- | --------------------------------------------------------- | --------------------------------------------------------------------- |
| `$readonly` | `read`, `find`, `grep`, `ls`                              | Read-only access – safe for exploration buffers                       |
| `$standard` | `read`, `write`, `edit`, `find`, `grep`, `ls`, `flemma.*` | File operations and harness tools, without shell access (the default) |

**User-defined presets** override built-ins by name. Define them in `presets`:

```lua
presets = {
  ["$yolo"] = { auto_approve = { "bash", "read", "write", "edit" } },
},
tools = {
  auto_approve = { "$yolo" },
}
```

Each preset is a table with an `auto_approve` array — the tool names to auto-approve.

**Composition rules:**

- **Union.** When multiple presets appear in `auto_approve`, their `approve` sets are merged.
- **Plain tool names** mix freely with presets: `{ "$standard", "bash" }` approves everything in `$standard` plus `bash`.

### Per-buffer approval

Override approval on a per-buffer basis using `flemma.opt.tools.auto_approve` in Lua frontmatter. The unified config resolver reads the merged value from all layers, so frontmatter values take precedence over global config automatically — there's no separate resolver to coordinate:

````lua
```lua
-- Preset form: read-only access for this buffer
flemma.opt.tools.auto_approve = { "$readonly" }

-- List form: auto-approve these tools in this buffer
flemma.opt.tools.auto_approve = { "bash", "read" }

-- Mix presets and tool names
flemma.opt.tools.auto_approve = { "$standard", "bash" }

-- Function form: full control per-buffer
flemma.opt.tools.auto_approve = function(tool_name, input, ctx)
  if tool_name == "grep" then return true end
  return nil  -- pass to next resolver
end
```
````

The function form returns `true` (approve), `false` (require approval), `"deny"` (block), or `nil` (pass to the next resolver in the chain).

**ListOption operations** let you modify the default policy incrementally instead of replacing it:

````lua
```lua
-- Start from default, but remove write access
flemma.opt.tools.auto_approve = { "$standard" }
flemma.opt.tools.auto_approve:remove("write")

-- Add bash to the default set
flemma.opt.tools.auto_approve = { "$standard" }
flemma.opt.tools.auto_approve:append("bash")

-- Operator shorthand: + (append), - (remove)
flemma.opt.tools.auto_approve = flemma.opt.tools.auto_approve + "bash" - "write"
```
````

When you `:remove()` a tool that lives inside a preset (e.g., removing `"write"` from `{ "$standard" }`), the tool is excluded at expansion time – the preset itself stays in the list, but the named tool is filtered out when the resolver evaluates it.

---

## Tool execution

- **Async tools** (like `bash`) show an animated spinner while running and can be cancelled.
- **Buffer locking** – the buffer is made non-modifiable during tool execution to prevent race conditions.
- **Output truncation** – large outputs (> 2000 lines or 50KB) are automatically truncated. The full output is saved to the [tool result store](#tool-result-store) and the truncated content ends with a notice pointing at it.
- **Cursor positioning** – after injection, the cursor can move to the result (`"result"`), stay put (`"stay"`), or jump to the next `@You:` prompt (`"next"`). Controlled by `tools.cursor_after_result`.

### Bash execution backend

On Neovim 0.12+ the `bash` tool executes commands inside a hidden terminal buffer rather than a raw `jobstart` process. This gives the command a real TTY so colour codes, progress bars, and curses-style tools render as the model would see them in a normal shell. Output is captured up to Neovim's compiled maximum scrollback (1M lines on 0.12+) before truncation kicks in. On Neovim 0.11 the tool falls back to `jobstart` since terminal buffers were not safe to drive from background contexts in that release.

This is transparent to your config — there's nothing to opt into. The terminal buffer is hidden, named after the tool invocation, and deleted once the command exits.

### Parallel tool use

All supported providers handle parallel tool calls. Press <kbd>Ctrl-]</kbd> to execute all pending calls at once, or use <kbd>Alt-Enter</kbd> on individual blocks. Flemma validates that every `**Tool Use:**` block has a matching `**Tool Result:**` before sending.

### Concurrency limit

`tools.max_concurrent` (default `2`) limits how many tools execute simultaneously per buffer. When the model returns more tool calls than the concurrency limit allows, Flemma queues the excess and starts them as earlier tools complete. This prevents resource exhaustion when the model emits many parallel calls.

Set `tools.max_concurrent = 0` for unlimited concurrency. Override per-buffer via `flemma.opt.tools.max_concurrent` in frontmatter.

---

## Background jobs

Async tools can run in the background without blocking the conversation. The tool continues executing while the model responds to other tool results or the user types a new message. When the job completes, its result is queued and delivered as a `**Job Result:**` block in an `@You` message.

### How tools enter background

**Model-initiated.** Flemma injects a `flemma.background` boolean parameter into every async tool's schema (a [harness parameter](#harness-parameters), invisible to the tool itself). When the model sets `"flemma.background": true`, the tool executes in the background from the start — the tool_result placeholder receives a job ID and a placeholder message, and the conversation continues immediately. [The parameter description](../lua/flemma/messages/tool-parameter--background.chat) encourages foreground by default; the model should only background a tool when it has other meaningful work to do while waiting and no upcoming decision depends on the result.

**User-initiated.** Press <kbd>Alt-B</kbd> (or `:Flemma tool:background`) while the cursor is on an executing tool to move it to background mid-flight. The tool keeps running, but the buffer unlocks and the conversation advances. If all foreground tools are now clear, autopilot triggers the next send automatically.

### Result delivery

Completed background jobs are queued until one of two delivery points:

- **Conversation idle** – after the model's response contains no tool calls, queued results are injected.
- **User send** – when the user presses <kbd>Ctrl-]</kbd> to send a new message, queued results are drained first.

Results appear as `` **Job Result:** `job_xxx` `` blocks inside `@You` messages. If the user is typing in the current `@You` block, the job result is inserted above in a separate `@You` block to avoid disrupting their work. Multiple results from different jobs merge into the same `@You` block when possible. Background `tool_result` placeholders are kept open (not auto-folded) while their job is still running, so the placeholder text and spinner remain visible.

> [!IMPORTANT]
> **Some models hallucinate pending job results.** When early jobs complete and their results are delivered before later jobs finish, the model sees a pattern — some results present, others pending — and may "complete" it by generating fabricated job output as plain text in its response. The hallucinated text can be convincingly detailed: plausible command output, tool IDs that mimic the real format, and formatting that resembles (but doesn't match) the actual `**Job Result:**` syntax.
>
> This has been observed with Gemini Flash 3.5 but can occur with any model prone to pattern completion over instruction following. The key thing to remember is that **job results can only appear in `@You:` messages** — jobs execute on your machine, and Flemma delivers their output on your behalf. Any reference to job results in an `@Assistant:` message is purely fabricated. The real results always arrive later as proper `**Job Result:**` blocks in `@You:` messages.

### Autopilot integration

When autopilot is enabled and background jobs complete at idle, Flemma schedules a debounced auto-continue after `tools.autopilot.resume_delay` milliseconds (default `2000`). This gives you time to review the result before the model sees it. Press <kbd>Ctrl-C</kbd> during the delay to cancel. Entering insert mode during the delay also cancels auto-continue. When completions arrive during an active autopilot loop (not at idle), the delay is skipped and the conversation continues immediately.

### `flemma.jobs.status` tool

A built-in harness tool that lets the model query the status of a background job by its `job_id`. Returns one of:

| Status                                  | Meaning                                      |
| --------------------------------------- | -------------------------------------------- |
| `running`                               | The tool is still executing                  |
| `queued`                                | Execution finished; result awaiting delivery |
| `completed`                             | Result already delivered into the buffer     |
| `completed (removed from conversation)` | Job existed but its result block was deleted |

The tool cross-checks in-memory state against the buffer AST, so even if the process state is cleared (e.g., after a restart), it falls back to scanning for `**Job Result:**` blocks.

### Orphan recovery

When reopening a `.chat` file that contains `tool_result` placeholders with a `job=job_xxx` modeline but no matching `**Job Result:**` block (e.g., after a crash or forced quit), Flemma detects these orphans on buffer load (`BufRead`/`BufNewFile`) and injects error results so the model knows the job was lost. A notification reports how many orphans were resolved.

### LSP integration

When `lsp.enabled` is set (defaults to `true` whenever `vim.lsp` is available), job-related blocks gain hover and go-to-definition support:

- **Hover** on a `tool_result` with a `job=` modeline shows the job's current status (`pending`, `completed`, or `error`) above the standard AST dump.
- **Go-to-definition** (`gd`) on a `tool_result` with a `job=` modeline jumps to the corresponding `**Job Result:**` block. On a `**Job Result:**` block, `gd` jumps back to the originating `tool_result`.

### Opting out

Set `backgroundable = false` on a tool definition to prevent the `flemma.background` parameter from being injected into its schema. Sync tools never receive the parameter regardless. The `flemma.jobs.status` harness tool is also not backgroundable.

---

## Tool result store

Large tool outputs need a durable home outside the buffer. The **store** is a per-conversation directory — co-located with the `.chat` file by default — where Flemma writes full tool outputs. Three things write to it:

- **Truncation overflow** — when a result exceeds the truncation limits (2000 lines / 50KB), the truncated content injected into the buffer ends with a `Full output: <path>` notice pointing at the complete output in the store. Always on; nothing to enable.
- **`flemma.save_to` redirects** — the model can ask for any tool's output to be written to a file instead of injected into the conversation (see [below](#flemmasave_to--redirecting-output-to-a-file)).
- **Eager materialization** — with `tools.store.materialize = true`, _every_ tool and job result is written to the store, truncated or not. Defaults to `false`: on tool-heavy conversations this duplicates content that already lives in the buffer.

### Store location

`tools.store.path_format` controls where results are written. It accepts a preset name or a template string:

| Preset            | Expands to                                                                                                                 |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `$chat` (default) | `{{ __dirname }}/.flemma/{{ flemma.path.basename(__filename) }}/{{ source }}_{{ name }}_{{ id }}.txt`                      |
| `$state`          | `${XDG_STATE_HOME:-$HOME/.flemma}/flemma/store/{{ flemma.path.flatten(__filename) }}/{{ source }}_{{ name }}_{{ id }}.txt` |

With the default `$chat` preset, a truncated `bash` result in `~/notes/example.chat` lands in `~/notes/.flemma/example.chat/tool_bash_toolu_01.txt` — the store travels with the conversation. `$state` keeps chat directories clean by routing everything under `$XDG_STATE_HOME/flemma/store/` instead (`~/.flemma/store/` when `XDG_STATE_HOME` is unset), with the chat path flattened into a single directory name (`home--user--notes--example.chat`).

Custom templates render with the standard [templating environment](templates.md) plus:

| Variable                               | Value                                                                       |
| -------------------------------------- | --------------------------------------------------------------------------- |
| `{{ source }}`                         | `"tool"` for foreground results, `"job"` for background job deliveries      |
| `{{ name }}`                           | The tool name, wire-encoded (dots become `__`, e.g. `flemma__jobs__status`) |
| `{{ id }}`                             | The tool/job ID, escaped — characters outside `[A-Za-z0-9._-]` become `--`  |
| `{{ __filename }}` / `{{ __dirname }}` | Chat file path / directory                                                  |
| `{{ bufnr }}`                          | Buffer number                                                               |
| `flemma.path.*`                        | Path helpers (`basename`, `flatten`, …)                                     |

After template rendering, `$VAR` / `${VAR:-default}` environment expansion applies, doubled `flemma` namespace segments collapse (`.flemma/flemma/` → `.flemma/`), and a tool name repeated within a single path segment is de-duplicated — IDs that embed the tool name don't produce `tool_bash_bash--…` filenames.

Unsaved buffers have no chat path to derive from, so they use `tools.store.unnamed_path_format` instead (default: `${TMPDIR:-/tmp}/flemma/unnamed/{{ flemma.pid }}/{{ bufnr }}/{{ source }}_{{ name }}_{{ id }}.txt` — the process ID keeps concurrent Neovim instances apart). Presets are not valid there.

> [!NOTE]
> The store replaces the `tools.truncate.output_path_format` option from v0.12 and earlier. Truncation overflow now follows `tools.store.path_format` — by default landing next to the chat file instead of in `$TMPDIR`.

### Overwrites and backups

Re-running a tool writes to the same store path. Before overwriting, the configured backup strategy runs — the default `version` strategy renames the existing file to the next free `<stem>.<n>.<ext>` (e.g. `tool_bash_toolu_01.1.txt`), so the canonical path always holds the latest run. Set `tools.store.backup = false` to overwrite in place, or pass a Lua module path exporting `backup(path)` for a custom strategy.

### `flemma.save_to` – redirecting output to a file

Flemma injects an optional `flemma.save_to` string parameter into **every** tool's schema. When the model supplies a path, the full output is written there and the conversation receives a stub instead: a short head preview (`tools.store.preview`, default 10 lines / 2KB) followed by `[Output saved: /path/to/file — 1.2MB, 54321 lines]`.

- Relative paths resolve against the chat file's directory; absolute and `~/…` paths work too.
- `$FLEMMA_TOOLS_STORE_PATH/<filename>` targets the conversation's store directory.
- An existing file at the destination is backed up first through `tools.store.backup` (the default `version` strategy renames it to the next free `<stem>.<n>.<ext>`), so a redirect never silently destroys prior content — set `tools.store.backup = false` to overwrite in place.
- With the [sandbox](sandbox.md) enabled, the destination must be writable under the sandbox policy.
- Redirects apply only to successful results, and work for both foreground results and background job deliveries.
- If the redirect fails (destination is a directory, sandbox denies the write, …), the full output is injected as if `flemma.save_to` had not been set, and a warning is logged.

### `$FLEMMA_TOOLS_STORE_PATH`

The `bash` tool exports `$FLEMMA_TOOLS_STORE_PATH` into every command's environment, pointing at the conversation's store directory. Shell commands can write artefacts directly there (`curl -o "$FLEMMA_TOOLS_STORE_PATH/response.json" …`), and the same variable works inside `flemma.save_to` values. The store directory is granted read-write access in the default sandbox policy via the `urn:flemma:store` variable (see [docs/sandbox.md](sandbox.md#flemma-urn-variables)).

### Harness parameters

`flemma.background` and `flemma.save_to` are **harness parameters**: Flemma injects them into each tool's schema when serializing the prompt and strips them from the input before the tool's `execute` runs. Tool implementations never see them, and the namespaced names can't collide with real tool parameters. For [strict-mode](#strict-mode-for-tool-schemas) tools they are injected as nullable (`type: [t, "null"]`) and appended to `required`, preserving strict-schema invariants across providers.

### Configuration

```lua
tools = {
  store = {
    path_format = "$chat",          -- "$chat", "$state", or a template string
    unnamed_path_format = "${TMPDIR:-/tmp}/flemma/unnamed/{{ flemma.pid }}/{{ bufnr }}/{{ source }}_{{ name }}_{{ id }}.txt",
    materialize = false,            -- Write every result to the store, not just overflow and redirects
    preview = {
      lines = 10,                   -- Preview lines shown in the buffer for flemma.save_to redirects (0 = no preview)
      bytes = 2048,                 -- Preview size cap
    },
    backup = "version",             -- Backup strategy before overwriting (false to disable)
  },
}
```

All options can be overridden per-buffer via `flemma.opt.tools.store` in frontmatter.

---

## Tool previews

When a tool call is pending approval, its tool_result placeholder fence is empty – you'd normally need to scroll up to the `**Tool Use:**` block to see what the tool will do. Tool previews eliminate that: Flemma renders a virtual line inside each empty placeholder showing a compact summary of the tool call.

For example, a pending `read` tool might show:

```
read: src/config.lua  +0,50 — checking config
```

And a pending `bash` tool:

```
bash: $ make test — running tests
```

Each preview has two parts: a **detail** (the raw technical summary — path, command, pattern) and a **label** (the LLM's stated intent, taken from the tool call's `label` field), separated by `—`. Detail leads because it is the part you scan for to identify the call; label trails as human-readable context. When the available width is limited, detail is truncated first (with `…`), preserving the label. Previews are non-editable virtual text (extmarks) that disappear once the tool executes and its result replaces the placeholder.

Folded message previews use the same `detail — label` layout but render label and detail as separate highlight chunks. The virt-line placeholder preview is a single string with one combined highlight — see [Styling](#styling).

When `ui.approval.syntax_highlighting` is enabled (the default), preview content receives treesitter syntax highlighting — JSON tool inputs and YAML-style generic previews render with proper syntax colours.

### Built-in preview formatters

Every built-in tool ships with a tailored `format_preview` function that returns a structured `{ label, detail }` preview:

| Tool    | Label source  | Detail format                        | Example                                     |
| ------- | ------------- | ------------------------------------ | ------------------------------------------- |
| `bash`  | `input.label` | `$ command`                          | `bash: $ git status — checking repo`        |
| `read`  | `input.label` | Path with optional `+offset[,limit]` | `read: config.lua  +100,50 — reading tail`  |
| `edit`  | `input.label` | Path                                 | `edit: config.lua — fixing typo`            |
| `write` | `input.label` | Path with content size               | `write: output.txt  (2.3KB) — saving log`   |
| `grep`  | `input.label` | `/pattern/` with optional path/glob  | `grep: /TODO/  *.lua — finding TODOs`       |
| `find`  | `input.label` | Pattern with optional search path    | `find: *.test.lua  in src/ — finding tests` |
| `ls`    | `input.label` | Path with optional depth             | `ls: src/  depth=3 — exploring structure`   |

Every built-in tool's `input_schema` includes a required `label` field — the LLM is prompted to supply a short intent string when it makes the call. The double-space gap in the `read`/`write`/`grep`/`find`/`ls` examples comes from joining the detail array (see [return shapes](#return-shapes) below).

### Generic fallback

Tools without a `format_preview` function get a YAML-style generic preview. Scalar values appear as `key: value` pairs and compound values are JSON-encoded. When the inline rendering (`{key: "value", ...}`) fits within the available width, it displays on a single line; otherwise it splits into a multi-line block mapping — for example, `tool_name: {query: "search term", limit: 10}`. If the input table contains a string `label` field, it is auto-promoted to the label slot and the rendering becomes `tool_name: {kv_body} — label`. This auto-promotion only applies to the generic fallback — when a tool ships its own `format_preview`, that function controls label entirely.

### Custom preview formatters

Register a `format_preview` function on your tool definition to control how it appears in pending placeholders. The function returns a `flemma.tools.ToolPreview`, which is either a structured `{ label?, detail? }` table or a plain string:

```lua
local s = require("flemma.schema")
local tools = require("flemma.tools")

tools.register("my_search", {
  name = "my_search",
  description = "Search a knowledge base",
  strict = true,
  input_schema = s.object({
    label = s.string():describe("A short human-readable label for this operation"),
    query = s.string():describe("Search query"),
    limit = s.number():nullable():describe("Max results (default 10)"),
  }):strict(),
  format_preview = function(input)
    return {
      label = input.label,
      detail = input.limit and ("limit " .. input.limit) or nil,
    }
  end,
  execute = function(input, ctx) --[[ ... ]] end,
})
```

The full type signature is `fun(input: table, max_length: integer): flemma.tools.ToolPreview`. `max_length` is the available width after the `"name: "` prefix is rendered — but the surrounding code already truncates the returned strings to fit, so built-in tools all ignore the argument and simply do `function(input)`.

#### Return shapes

| Return type                     | Behaviour                                                                                                                                                                                                                |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `string`                        | Treated as `{ detail = the_string }`. Label is **never** auto-promoted from `input.label` for explicit returns — only the [generic fallback](#generic-fallback) does that.                                               |
| `{ label?, detail? }`           | Rendered as `detail — label` when both are present; otherwise just whichever is given.                                                                                                                                   |
| `{ label?, detail = string[] }` | The `detail` array is joined with a **double space** before display.                                                                                                                                                     |
| `{ ..., highlight? }`           | When `highlight = { lang = "yaml" }` (or another treesitter language), the preview receives syntax highlighting if `ui.approval.syntax_highlighting` is enabled. The generic fallback uses this for YAML-style previews. |

Newlines in either field are collapsed to the `eol` character from `listchars` (or `↵` by default) and the result is truncated to fit the editor width.

### Styling

Tool previews use three highlight groups:

| Group               | Default                         | Applies to                                                                     |
| ------------------- | ------------------------------- | ------------------------------------------------------------------------------ |
| `FlemmaToolPreview` | `Comment`                       | The whole virt-line placeholder preview (single combined highlight)            |
| `FlemmaToolLabel`   | `tool_preview` color + `italic` | The label chunk in folded message previews and the approved tool-result footer |
| `FlemmaToolDetail`  | `Comment`                       | The detail chunk inside folded message previews                                |

The virt-line placeholder preview is rendered as a single string with `FlemmaToolPreview` blended over the role's line background — so label and detail share one highlight and there is no italic distinction in that view. The label/detail split (the label adds italic over the same muted color) is only visible in folded message previews, where each chunk gets its own highlight.

Customise `FlemmaToolDetail` via `highlights.tool_detail` in your config. `FlemmaToolLabel` is the preview color (`highlights.tool_preview`) with the `highlights.tool_label` accent merged on top — italic by default; set a `fg` in `highlights.tool_label` to recolor it. See [docs/ui.md](ui.md#highlights-and-styles) for details.

---

## Exploration tools

Three of Flemma's built-in tools — `grep`, `find`, and `ls` — handle codebase exploration alongside `read`, `edit`, `write`, and `bash`:

| Tool   | Type  | Description                                                                                                                   |
| ------ | ----- | ----------------------------------------------------------------------------------------------------------------------------- |
| `grep` | async | Search file contents using ripgrep (`rg`), GNU grep with PCRE (`grep -P`), or POSIX ERE (`grep -E`) – whichever is available. |
| `find` | async | Find files by glob pattern using `fd`, `git ls-files`, or GNU `find` – whichever is available.                                |
| `ls`   | sync  | List directory contents with configurable recursion depth and entry limit. Directories appear first (suffixed with `/`).      |

All three are included in the `$standard` and `$readonly` approval presets, so they are auto-approved by default when using either preset.

### Configuration

Each tool has an optional config section under `tools`:

```lua
tools = {
  grep = {
    cwd = "urn:flemma:buffer:path",                         -- working directory
    exclude = { ".git", "node_modules", "__pycache__",      -- patterns to exclude
                ".venv", "target", "dist", "build", "vendor" },
  },
  find = {
    cwd = "urn:flemma:buffer:path",
    exclude = { ".git", "node_modules", "__pycache__",
                ".venv", "target", "dist", "build", "vendor" },
  },
  ls = {
    cwd = "urn:flemma:buffer:path",
  },
}
```

### Backend detection

`grep` and `find` auto-detect the best available backend at first use and cache the result:

| Tool   | Priority 1                | Priority 2                     | Priority 3            |
| ------ | ------------------------- | ------------------------------ | --------------------- |
| `grep` | `rg` (ripgrep, JSON mode) | `grep -P` (GNU grep with PCRE) | `grep -E` (POSIX ERE) |
| `find` | `fd` / `fdfind`           | `git ls-files`                 | GNU `find`            |

When using the `grep -E` fallback, Perl-style shorthand classes (`\d`, `\w`, `\s`) are automatically translated to POSIX equivalents.

---

## Per-buffer tool selection

Control which tools are available per-buffer using `flemma.opt` in Lua frontmatter:

````lua
```lua
flemma.opt.tools = {"bash", "read"}             -- only these tools
flemma.opt.tools:remove("write")               -- remove from defaults
flemma.opt.tools:append("grep")                -- add a tool
flemma.opt.tools = flemma.opt.tools + "read"    -- operator overloads work too
```
````

Each evaluation starts from defaults (all enabled tools). Misspelled tool names produce an error with a "did you mean" suggestion.

### Glob patterns in tool lists

Entries containing `*` are treated as glob patterns and expanded against the registered tools. This is the natural way to bulk-enable namespaced tools (MCP servers, custom harness tools):

````lua
```lua
-- Enable every Slack tool that the MCPorter discovery surfaced
flemma.opt.tools:append("slack.*")

-- Replace defaults with just GitHub + Linear search tools
flemma.opt.tools = { "github.search_*", "linear.search_*" }

-- Drop a noisy MCP server's tools from this buffer
flemma.opt.tools:remove("linear.*")
```
````

Globs work with all list operations (`set`, `append`, `prepend`, `remove`). Expansion runs in two passes:

1. **Write-time** (best-effort) — when you assign or `:append`/`:remove` a glob, the schema coerce tries to substitute matching tool names immediately. If the tool registry is still loading (e.g. MCPorter discovery hasn't returned), the glob is stored verbatim for now.
2. **Finalize-time** (authoritative) — after setup completes and all async tool sources have resolved, every stored op is re-run through the coerce so verbatim globs get their second chance. Then the deferred validator runs: a pattern that still matches **no** registered tools at this point fails with `"Glob pattern 'x' matched no tools"`.

This is why typos in `flemma.opt.tools` surface as errors rather than silent no-ops — the finalize pass guarantees the tool registry is fully populated before validation decides anything.

> [!NOTE]
> **`tools.auto_approve` uses a different mechanism.** Globs in the auto-approval list (and in `$standard`'s `"flemma.*"` entry) are stored verbatim, never expanded by the config layer, and matched against incoming tool calls at **approval time** in the resolver chain (`lua/flemma/tools/approval.lua:202`). The end result is similar — `{ "flemma.*" }` approves every harness tool — but no deferred validator runs over the list, so a typo in `auto_approve` (e.g. `"flmma.*"`) silently approves nothing instead of erroring. Use `:Flemma status verbose` to see the resolved list and confirm your pattern is reaching the resolver.

### Per-buffer parameter overrides

General and provider-specific parameters can be overridden per-buffer using `flemma.opt` in Lua frontmatter:

````lua
```lua
-- General parameters (work across all providers)
flemma.opt.thinking = "medium"          -- override the unified thinking level
flemma.opt.cache_retention = "long"     -- override prompt caching strategy
flemma.opt.max_tokens = 8000            -- override max output tokens
flemma.opt.temperature = 0.3            -- override sampling temperature

-- Provider-specific overrides (take priority over general)
flemma.opt.anthropic.thinking_budget = 20000
flemma.opt.openai.reasoning = "high"
flemma.opt.vertex.thinking_budget = 4096
```
````

When both general and provider-specific parameters are set, provider-specific values win. For example, setting both `flemma.opt.thinking = "low"` and `flemma.opt.anthropic.thinking_budget = 20000` will use 20,000 tokens on Anthropic.

---

## Registering custom tools

`require("flemma.tools").register()` is a single entry point that accepts several forms:

**Single definition** – pass a name and definition table:

```lua
local s = require("flemma.schema")
local tools = require("flemma.tools")

tools.register("my_tool", {
  name = "my_tool",
  description = "Does something useful",
  strict = true,
  input_schema = s.object({
    label = s.string():describe("A short human-readable label for this operation"),
    query = s.string():describe("The input query"),
  }):strict(),
  format_preview = function(input)
    return { label = input.label, detail = '"' .. input.query .. '"' }
  end,
  execute = function(input, ctx)
    return { success = true, output = "done: " .. input.query }
  end,
})
```

`input_schema` accepts either a `flemma.schema.Node` (built with `s.object`, `s.string`, …) or a raw JSON Schema table. Every built-in uses the DSL — it serializes to JSON Schema lazily on request, gives you EmmyLua-friendly types, and makes [strict mode](#strict-mode-for-tool-schemas) effectively free. See [Tool input schemas with the schema DSL](#tool-input-schemas-with-the-schema-dsl) below for the full surface.

**Module name** – pass a module path. If the module exports `.definitions` (an array of definition tables), they are registered synchronously. If it exports `.resolve(register, done)`, it is registered as an async source (see [Async tool definitions](#async-tool-definitions)):

```lua
tools.register("my_plugin.tools.search")
```

> [!NOTE]
> Built-in tool modules moved from `flemma.tools.definitions.*` to `flemma.tools.definitions.builtin.*` in v0.12, and the jobs harness tool lives at `flemma.tools.definitions.harness.jobs`. If you `require()` a built-in tool module by path, update the import.

**Batch** – pass an array of definition tables:

```lua
tools.register({
  {
    name = "tool_a",
    description = "...",
    strict = true,
    input_schema = s.object({ label = s.string() }):strict(),
    execute = function(input, ctx) --[[ ... ]] end,
  },
  {
    name = "tool_b",
    description = "...",
    strict = true,
    input_schema = s.object({ label = s.string() }):strict(),
    execute = function(input, ctx) --[[ ... ]] end,
  },
})
```

### Tool input schemas with the schema DSL

The `flemma.schema` module exposes a chainable DSL for declaring tool inputs:

| Factory                                                     | Notes                                                                                              |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `s.string()` / `s.number()` / `s.integer()` / `s.boolean()` | Scalars. Optional positional default: `s.string("hello")`.                                         |
| `s.object({...})`                                           | Object schema. **Strict by default** — `additionalProperties = false`, all listed fields required. |
| `s.list(item)`                                              | JSON Schema array. (`s.array` does **not** exist — use `s.list`.)                                  |
| `s.map(key, value)`                                         | Open object — JSON Schema `additionalProperties` with typed values.                                |
| `s.enum({"a", "b"})`                                        | Enumerated string.                                                                                 |
| `s.union(a, b, ...)`                                        | `anyOf`.                                                                                           |
| `s.literal(value)`                                          | Exact-value match.                                                                                 |
| `s.optional(inner)`                                         | Field may be **absent** (omitted from `required`).                                                 |
| `s.nullable(inner)`                                         | Field is present but its value may be `null`. Required in JSON Schema; type becomes `[t, "null"]`. |

Chainable methods on every schema node:

| Method            | Effect                                                                                               |
| ----------------- | ---------------------------------------------------------------------------------------------------- |
| `:describe(text)` | Sets the `description` shown to the model.                                                           |
| `:nullable()`     | Sugar for `s.nullable(self)`. The idiomatic way to mark a tool parameter as optional in strict mode. |
| `:optional()`     | Sugar for `s.optional(self)`. The field may be absent — only valid outside strict mode.              |

Object-specific:

| Method           | Effect                                                                                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `:strict()`      | Marks the object as strict (`additionalProperties = false`). This is the default for `s.object` — every built-in keeps the call as an explicit readability marker. |
| `:passthrough()` | Inverse of `:strict()` — allow unknown keys.                                                                                                                       |

Strict-mode invariants the docs used to spell out by hand are handled automatically: fields wrapped in `s.optional(...)` are excluded from `required`, all others are required in sorted order, and `additionalProperties = false` is emitted when the object is strict.

---

## ExecutionContext

Every tool's `execute` function receives up to three arguments: `input`, `context`, and an optional `callback`. The context is an `ExecutionContext` object that provides the stable contract tools code against – tools should never `require()` internal Flemma modules directly.

```lua
-- Sync tools: return an ExecutionResult directly
execute = function(input, ctx)
  return { success = true, output = "done" }
end

-- Async tools: call callback(result) when done, return a cancel function
execute = function(input, ctx, callback)
  -- ...
end
```

### Core fields

| Field            | Type      | Description                                                                                                                                                                                                                                                                                  |
| ---------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ctx.bufnr`      | `integer` | Buffer number for the current execution                                                                                                                                                                                                                                                      |
| `ctx.tool_id`    | `string?` | The tool-call ID — the same string that appears in the ``**Tool Use:** `name` (`tool_id`)`` header. Buffer-unique; use it as a correlation key for scratch files, log tags, or any per-call artefact you need to namespace. Optional in the type but always populated during real execution. |
| `ctx.cwd`        | `string`  | Absolute working directory (resolved from config or Neovim)                                                                                                                                                                                                                                  |
| `ctx.timeout`    | `integer` | Default timeout in seconds (from `config.tools.default_timeout`)                                                                                                                                                                                                                             |
| `ctx.__dirname`  | `string?` | Directory containing the `.chat` buffer (`nil` for unsaved)                                                                                                                                                                                                                                  |
| `ctx.__filename` | `string?` | Full path of the `.chat` buffer (`nil` for unsaved)                                                                                                                                                                                                                                          |

### Namespaces

The following namespaces are lazy-loaded on first access (zero cost if unused):

#### `ctx.path` – Path resolution

```lua
local absolute = ctx.path.resolve("relative/file.txt")
-- Resolves against __dirname (or cwd if buffer is unsaved)
-- Absolute paths pass through unchanged
```

#### `ctx.sandbox` – Sandbox enforcement

```lua
-- Check if a path is writable under the current sandbox policy
if not ctx.sandbox.is_path_writable(path) then
  return { success = false, error = "Sandbox: path not writable" }
end

-- Wrap a command for sandbox enforcement (returns nil + error on failure)
local wrapped_cmd, err = ctx.sandbox.wrap_command({ "bash", "-c", "echo hello" })
```

#### `ctx.truncate` – Output truncation

```lua
-- Truncate from the end (keep last N lines/bytes) – use for streaming output
local result = ctx.truncate.truncate_tail(full_output)
-- result.content, result.truncated, result.total_lines, result.output_lines, ...

-- Truncate from the start (keep first N lines/bytes) – use for file reads
local result = ctx.truncate.truncate_head(content)

-- Tail-truncate with automatic overflow handling: when truncation occurs, the
-- full output is saved to the tool result store (named with this tool call's
-- id) and a "Full output: /path/..." notice is appended to the returned
-- content. This is what `bash` uses for its streaming output.
local result = ctx.truncate.truncate_with_overflow(full_output, { direction = "tail" })

-- Format byte counts for display
local size_str = ctx.truncate.format_size(12345)  -- "12.1KB"

-- Constants
ctx.truncate.MAX_LINES  -- 2000
ctx.truncate.MAX_BYTES  -- 51200 (50KB)
```

### `ctx:get_config()` – Tool-specific config

Returns a read-only copy of `config.tools[tool_name]`, or `nil` if no config subtree exists for this tool. The returned table is a deep copy – modifications do not affect the global config.

```lua
local tool_config = ctx:get_config()
if tool_config and tool_config.shell then
  -- Use configured shell
end
```

### `ctx:get_parsed_document()` – Buffer AST access

Returns the cached `flemma.ast.DocumentNode` for `ctx.bufnr`. Use it when a tool needs to inspect the surrounding conversation structure — for example, the `flemma.jobs.status` harness tool cross-checks in-memory state against `**Job Result:**` segments in the buffer.

```lua
local doc = ctx:get_parsed_document()
for _, msg in ipairs(doc.messages) do
  -- inspect roles, segments, tool calls...
end
```

Reach for this only when buffer truth matters — most tools should operate on `input` and filesystem state, not the conversation transcript.

### Complete example

```lua
local s = require("flemma.schema")
local tools = require("flemma.tools")

tools.register("export", {
  name = "export",
  description = "Save content to a file in the project",
  strict = true,
  async = false,
  input_schema = s.object({
    label = s.string():describe("A short human-readable label (e.g., 'saving log')"),
    path = s.string():describe("Output file path (relative or absolute)"),
    content = s.string():describe("Content to write"),
  }):strict(),
  format_preview = function(input)
    return {
      label = input.label,
      detail = { input.path, "(" .. #input.content .. "B)" },
    }
  end,
  execute = function(input, ctx)
    local path = ctx.path.resolve(input.path)

    if not ctx.sandbox.is_path_writable(path) then
      return { success = false, error = "Sandbox: write denied for " .. input.path }
    end

    -- Use tool-specific config (e.g. config.tools.export = { max_size = 102400 })
    local tool_config = ctx:get_config()
    local max_size = (tool_config and tool_config.max_size) or ctx.truncate.MAX_BYTES

    if #input.content > max_size then
      return {
        success = false,
        error = "Content exceeds " .. ctx.truncate.format_size(max_size) .. " limit",
      }
    end

    -- ... write logic ...

    return { success = true, output = "Saved " .. #input.content .. " bytes to " .. input.path }
  end,
})
```

---

## Strict mode for tool schemas

OpenAI's Responses API supports [strict mode](https://platform.openai.com/docs/guides/structured-outputs) for function calling, which guarantees that the model's arguments will conform exactly to your JSON Schema. All of Flemma's built-in tools use strict mode.

To opt in for your custom tools, set `strict = true` on the definition and build the `input_schema` with `s.object(...):strict()`. The DSL handles every strict-mode invariant automatically:

- Every field listed on the object is added to `required` in sorted order — wrap a field in `s.optional(...)` to exclude it.
- `additionalProperties = false` is emitted when the object is strict (which is the default for `s.object`).
- Optional parameters use `:nullable()`, which produces a `type: [t, "null"]` shape on the JSON Schema side. The field stays in `required`.

```lua
local s = require("flemma.schema")

tools.register("my_tool", {
  name = "my_tool",
  description = "Does something",
  strict = true,
  input_schema = s.object({
    query       = s.string():describe("Required input"),
    max_results = s.number():nullable():describe("Optional limit (default: 10)"),
  }):strict(),
  execute = function(input, ctx)
    local limit = input.max_results or 10
    return { success = true, output = "found results" }
  end,
})
```

When `strict` is not set (or set to `false`), the field is omitted from the API request entirely. You can still pass a raw JSON Schema table for `input_schema` if you need full control — Flemma forwards whatever you give it.

The injected [harness parameters](#harness-parameters) (`flemma.background`, `flemma.save_to`) follow these invariants automatically: on strict tools they are added as nullable and appended to `required`.

---

## Async tool definitions

Tool definitions that need to call external processes or remote APIs can resolve asynchronously. Flemma gates API requests on all sources being ready – if you send while definitions are still loading, the buffer shows "Waiting for tool definitions to load..." and auto-sends once everything resolves.

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

Flemma's built-in [MCP integration](mcp.md) is implemented as an async tool source -- it's a good reference for the pattern in practice (`lua/flemma/tools/definitions/builtin/mcporter.lua`).

---

## Approval resolvers

Flemma uses a priority-based resolver chain to decide whether a tool call should be auto-approved, require user approval, or be denied. The chain evaluates resolvers in priority order (highest first); the first non-nil result wins. If no resolver returns a decision, the default is `"require_approval"`.

Built-in resolvers are registered during `setup()`:

| Priority | Name                            | Source                                                                                                                                                                                                        |
| -------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 100      | `urn:flemma:approval:config`    | Unified resolver — reads the merged `tools.auto_approve` value from all config layers (DEFAULTS → SETUP → RUNTIME → FRONTMATTER), evaluates a list, function, or `$preset` reference, and returns a decision. |
| 25       | `urn:flemma:approval:sandbox`   | Auto-approve tools with `can_auto_approve_if_sandboxed` capability when sandbox is enabled and available                                                                                                      |
| 0        | `urn:flemma:approval:catch-all` | Only when `tools.require_approval = false`                                                                                                                                                                    |

Third-party plugins register at the default priority of 50. Set `priority` higher to run before built-in resolvers (e.g., 200 to override config), or lower to act as a fallback.

> [!NOTE]
> Earlier releases used separate `config` and `frontmatter` resolvers. The unified resolver at priority 100 now consults the merged config store directly, so frontmatter overrides take effect through layer precedence rather than a separate resolver entry. Per-buffer `flemma.opt.tools.auto_approve` writes still beat global config — the merge happens before the resolver runs.

The sandbox resolver (priority 25) auto-approves tools that declare `"can_auto_approve_if_sandboxed"` in their `capabilities` array when the sandbox is enabled with an available backend and the user hasn't opted out per-tool or globally. Currently only the built-in `bash` tool declares this capability. Disable with `tools.auto_approve_sandboxed = false` in config, exclude specific tools per-buffer with `auto_approve:remove("bash")` in frontmatter, or take ownership of the policy with `auto_approve:set(...)` in frontmatter (a `set` op signals you're handling approval entirely for that buffer). See [docs/sandbox.md](sandbox.md#requirements) for the full list of conditions.

### Registering a resolver

```lua
local approval = require("flemma.tools.approval")

approval.register("my_plugin.security_policy", {
  description = "Block dangerous bash commands",
  resolve = function(tool_name, input, context)
    if tool_name == "bash" and input.command:match("rm %-rf") then
      return "deny"
    end
    return nil  -- pass to next resolver
  end,
})
```

The `resolve` function receives:

- **`tool_name`** (`string`) – the name of the tool being called (e.g., `"bash"`, `"read"`).
- **`input`** (`table`) – the tool call's input arguments.
- **`context`** (`table`) – contains `bufnr` (buffer number) and `tool_id` (unique ID for this tool call).

Return values:

| Return value         | Effect                                              |
| -------------------- | --------------------------------------------------- |
| `"approve"`          | Auto-approve; skip the approval placeholder step    |
| `"require_approval"` | Show the placeholder and wait for user confirmation |
| `"deny"`             | Block execution; inject an error result             |
| `nil`                | Pass; let the next resolver in the chain decide     |

If a resolver throws an error, it is logged and skipped (treated as `nil`).

### Bundling a resolver with a tool module

A module loaded via `tools.modules` can also register an approval resolver by exporting an `approval` table alongside its tool definitions. This is the idiomatic way to ship security policy alongside the tools it governs — one entry in the user's config wires up both:

```lua
-- In lua/my_plugin/tools.lua
return {
  definitions = {
    { name = "deploy", description = "...", input_schema = { ... }, execute = ... },
    { name = "rollback", description = "...", input_schema = { ... }, execute = ... },
  },
  approval = {
    priority = 75,  -- optional, defaults to 50
    description = "Gate deploy/rollback on git branch",
    resolve = function(tool_name, input, context)
      if tool_name == "deploy" and vim.fn.system("git branch --show-current"):match("^main") then
        return "require_approval"
      end
      return nil
    end,
  },
}
```

Wire it up once:

```lua
require("flemma").setup({
  tools = { modules = { "my_plugin.tools" } },
})
```

The resolver is registered under the module path (e.g. `my_plugin.tools`), which becomes its name in the resolver chain. Use this pattern when the resolver and the tools it governs ship together; use the direct `approval.register()` API for plugins that only contribute policy.

### Unregistering a resolver

```lua
approval.unregister("my_plugin.security_policy")  -- returns true if found
```

Re-registering with the same name replaces the existing resolver.

### Introspection

```lua
approval.get("urn:flemma:approval:config")  -- returns the resolver entry or nil
approval.get_all()                    -- all resolvers sorted by priority (deep copy)
approval.count()                      -- number of registered resolvers
```
