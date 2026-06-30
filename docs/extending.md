# Extending Flemma

Flemma uses registry patterns throughout – tools, providers, approval resolvers, sandbox backends, credential resolvers, and personalities are all pluggable. This guide covers the extension points that don't have a dedicated document, and links to those that do. These registries are the seams into Flemma as a [harness](harness.md): lifecycle hooks (`FlemmaJobCompleted`, `FlemmaToolApprovalRequired`, `FlemmaAutopilotResuming`), programmatic approval, and credential resolution are where external code plugs into the harness's gating and coordination surfaces.

---

## Hooks (Lifecycle Events)

Flemma emits [User autocmds](https://neovim.io/doc/user/autocmd.html#User) at lifecycle boundaries. External plugins listen with standard Neovim autocommand APIs – no Flemma-specific setup required.

### Available events

| Event name                   | Autocmd pattern                  | Payload fields                                                                                                                                          | When it fires                                        |
| ---------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `request:sending`            | `FlemmaRequestSending`           | `bufnr`                                                                                                                                                 | Just before an API request is sent                   |
| `request:finished`           | `FlemmaRequestFinished`          | `bufnr`, `status` (`"completed"`, `"cancelled"`, or `"errored"`), `request?` (`flemma.session.Request` — present on completed status with pricing info) | After an API request completes (any outcome)         |
| `tool:executing`             | `FlemmaToolExecuting`            | `bufnr`, `tool_name`, `tool_id`                                                                                                                         | When a tool invocation starts execution              |
| `tool:completed`             | `FlemmaToolCompleted`            | `bufnr`, `tool_name`, `tool_id`, `status` (`"success"` or `"error"`)                                                                                    | When a tool invocation completes                     |
| `tool:approval-required`     | `FlemmaToolApprovalRequired`     | `bufnr`, `tools` (array of `{ tool_id, tool_name, input }`)                                                                                             | When one or more tool calls land on `(pending)`      |
| `usage:estimated`            | `FlemmaUsageEstimated`           | `bufnr`                                                                                                                                                 | When a buffer's token estimate cache changes         |
| `config:updated`             | `FlemmaConfigUpdated`            | _(none)_                                                                                                                                                | After runtime configuration changes (see note below) |
| `boot:complete`              | `FlemmaBootComplete`             | _(none)_                                                                                                                                                | After all async tool sources finish loading          |
| `buffer:created`             | `FlemmaBufferCreated`            | `bufnr`                                                                                                                                                 | After Flemma initializes a `.chat` buffer            |
| `buffer:destroyed`           | `FlemmaBufferDestroyed`          | `bufnr`                                                                                                                                                 | When a `.chat` buffer is wiped or deleted            |
| `sink:created`               | `FlemmaSinkCreated`              | `bufnr`, `name`                                                                                                                                         | When a new output buffer (sink) is created           |
| `sink:destroyed`             | `FlemmaSinkDestroyed`            | `bufnr`, `name`                                                                                                                                         | When an output buffer (sink) is destroyed            |
| `conversation:idle`          | `FlemmaConversationIdle`         | `bufnr`                                                                                                                                                 | When the conversation reaches idle after a response  |
| `job:submitted`              | `FlemmaJobSubmitted`             | `bufnr`, `job_id`, `tool_id`, `tool_name`, `active_count`                                                                                               | When a tool is moved to background execution         |
| `job:completed`              | `FlemmaJobCompleted`             | `bufnr`, `job_id`, `tool_id`, `tool_name`, `success`, `active_count`                                                                                    | When a background job result is delivered            |
| `autopilot:resume-scheduled` | `FlemmaAutopilotResumeScheduled` | `bufnr`, `delay_ms`                                                                                                                                     | When autopilot schedules a debounced auto-continue   |
| `autopilot:resume-cancelled` | `FlemmaAutopilotResumeCancelled` | `bufnr`                                                                                                                                                 | When a scheduled auto-continue is cancelled          |
| `autopilot:resumed`          | `FlemmaAutopilotResumed`         | `bufnr`                                                                                                                                                 | When autopilot fires after the resume delay          |

> [!WARNING]
> The **`config:updated`** event is not yet dispatched consistently across all config mutation paths. Today it only fires from `:Flemma switch` (provider switching). Other mutations — frontmatter changes, programmatic `config.apply()` calls — do not emit it yet. Treat it as a best-effort signal for now.

### Listening to events

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "FlemmaRequestFinished",
  callback = function(ev)
    if ev.data.status == "completed" then
      vim.notify("Request finished for buffer " .. ev.data.bufnr)
    end
  end,
})
```

Payload fields are available on `ev.data`. The data table is always present (never `nil`), even for events with no payload fields like `boot:complete`. Errors in consumer callbacks are caught and logged – they never crash the request pipeline.

### Naming convention

Internal hook names use `domain:action` format (e.g., `request:sending`). The autocmd pattern is derived by TitleCasing each segment and prepending `Flemma`:

- `request:sending` → `FlemmaRequestSending`
- `tool:completed` → `FlemmaToolCompleted`
- Hyphenated words are split: `tool-use:completed` → `FlemmaToolUseCompleted`

### Example: busy indicator

The built-in [bufferline integration](integrations.md#bufferline) uses hooks to track busy state:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "FlemmaRequestSending",
  callback = function(ev) increment_busy(ev.data.bufnr) end,
})
vim.api.nvim_create_autocmd("User", {
  pattern = "FlemmaRequestFinished",
  callback = function(ev) decrement_busy(ev.data.bufnr) end,
})
```

### Lua subscribers

In addition to User autocmds, hooks support direct Lua callbacks via `hooks.on()`. By default hooks are dispatched **asynchronously** via `vim.schedule` — both Lua subscribers and the User autocmd fire on the next event-loop tick. Within that tick, Lua subscribers run before the autocmd, in registration order, with per-subscriber error isolation so one buggy listener never blocks another.

```lua
local hooks = require("flemma.hooks")

local subscription = hooks.on("job:completed", function(data)
  if data.active_count == 0 then
    vim.notify("All background jobs finished")
  end
end)

-- Later: unsubscribe
subscription:off()
```

`hooks.on(name, callback)` returns a `flemma.hooks.Subscription` with an `:off()` method. Prefer autocmds for external plugins; prefer `hooks.on()` when you need guaranteed ordering relative to other subscribers or want to avoid the `ev.data` unwrapping overhead.

#### Synchronous dispatch

If a caller needs subscribers to complete before continuing (for cleanup hooks that must run before state is torn down), `hooks.dispatch(name, data, { sync = true })` skips the `vim.schedule` deferral and invokes subscribers inline. This is used internally for `buffer:destroyed`. Don't reach for this unless you genuinely need synchronous semantics — the async default keeps subscribers from blocking the main loop.

---

## Programmatic tool approval

The `tool:approval-required` hook pairs with a small public API for resolving approvals outside the buffer. This is how you replace the inline `(pending)` flow with a confirmation dialog, a statusline picker, or any other UI:

```lua
local hooks = require("flemma.hooks")
local tools = require("flemma.tools")

hooks.on("tool:approval-required", function(data)
  for _, call in ipairs(data.tools) do
    local choice = vim.fn.confirm(
      string.format("Approve %s?\n%s", call.tool_name, vim.inspect(call.input)),
      "&Approve\n&Reject",
      2
    )
    if choice == 1 then
      tools.approve(data.bufnr, call.tool_id)
    else
      tools.reject(data.bufnr, call.tool_id, "Denied via confirmation dialog")
    end
  end
end)
```

| Function                                 | Effect                                                                                                      |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `tools.approve(bufnr, tool_id)`          | Sets the tool_result header to `(approved)`. The next phase advance executes it.                            |
| `tools.reject(bufnr, tool_id, message?)` | Sets the header to `(rejected)`. Optional `message` is written into the fence body as the rejection reason. |

Both functions guard against approving/rejecting tools that no longer exist or have already resolved. They nudge autopilot via `autopilot.nudge()` so an in-flight loop picks up your decision without an extra <kbd>Ctrl-]</kbd>. See `contrib/extras/approval_dialog.lua` for a working example using `vim.fn.confirm()`.

The hook fires once per Phase 1 with **all** pending tools batched into a single `tools` array — pick the ones you care about and ignore the rest, or process them all in one prompt.

---

## Credential Resolution

Flemma resolves API keys and tokens through a priority-based resolver chain. The first resolver that finds a credential wins. Results are cached with TTL awareness to avoid repeated lookups.

### Resolution order

| Priority | Resolver       | Platform     | What it checks                                                       |
| -------- | -------------- | ------------ | -------------------------------------------------------------------- |
| 100      | Environment    | All          | `{SERVICE}_{KIND}` env var (e.g., `ANTHROPIC_API_KEY`), then aliases |
| 50       | Secret Service | Linux        | `secret-tool lookup service {service} key {kind}` (GNOME Keyring)    |
| 50       | Keychain       | macOS        | `security find-generic-password -s {service} -a {kind} -w`           |
| 50       | ChatGPT        | All          | `~/.codex/auth.json` OAuth token (only `chatgpt_subscription` kind)  |
| 25       | Gcloud         | All (w/ CLI) | `gcloud auth print-access-token` (only for `access_token` kind)      |

The ChatGPT resolver is **not** part of the default chain — it is registered only when the experimental Codex provider is loaded (`providers.modules = { "flemma.provider.adapters.experimental.codex" }`). See [docs/providers.md](providers.md#codex--chatgpt-subscription-experimental).

### How it works

1. **Cache check** – if a cached credential exists and its TTL hasn't expired, return it immediately.
2. **Resolver iteration** – try each resolver in priority order (highest first). Each resolver's `supports()` method filters by platform, credential kind, or service.
3. **First match wins** – the first resolver that returns a value is used. The result is cached.
4. **Fallback** – if no resolver succeeds, a warning notification lists every resolver that was tried and why it couldn't help (e.g., "ANTHROPIC_API_KEY not set", "secret-tool not found on PATH", "gcloud: executable not found"). This diagnostic output helps pinpoint which resolver to configure.

### Environment resolver conventions

The environment resolver constructs the variable name from the credential's service and kind:

| Service   | Kind            | Variable checked         |
| --------- | --------------- | ------------------------ |
| anthropic | api_key         | `ANTHROPIC_API_KEY`      |
| openai    | api_key         | `OPENAI_API_KEY`         |
| vertex    | access_token    | `VERTEX_ACCESS_TOKEN`    |
| vertex    | service_account | `VERTEX_SERVICE_ACCOUNT` |
| moonshot  | api_key         | `MOONSHOT_API_KEY`       |

Credentials can also define `aliases` – alternative variable names checked in order after the convention. For example, `vertex`/`access_token` also accepts the legacy `VERTEX_AI_ACCESS_TOKEN` alias.

### TTL caching

Credentials are cached per `kind:service` key (e.g., `api_key:anthropic`). The effective TTL is:

```
effective_ttl = base_ttl * ttl_scale
```

Where `base_ttl` comes from the resolver result or credential config, and `ttl_scale` (default `1.0`) allows adjusting the refresh window (e.g., `0.8` to refresh at 80% of token lifetime). When no TTL is set, the credential caches indefinitely until manually invalidated.

### Configuring resolvers

Built-in resolvers can be configured through the `secrets` config namespace. Two resolvers have configurable options today — gcloud and ChatGPT:

```lua
require("flemma").setup({
  secrets = {
    gcloud = {
      path = "/usr/local/bin/gcloud",  -- override the gcloud binary path (default: "gcloud")
    },
    chatgpt = {
      auth_file = "~/.codex/auth.json", -- override the Codex auth file path
    },
  },
})
```

The `gcloud.path` override is useful on NixOS, Guix, or systems where the gcloud CLI is not on `$PATH`. The `chatgpt.auth_file` override points the ChatGPT subscription resolver at a non-default Codex auth file; when unset it falls back to `$CODEX_HOME/auth.json`, then `~/.codex/auth.json`. Each resolver reads its own subtree (`secrets.gcloud`, `secrets.chatgpt`) via `ctx:get_config()`.

Each resolver **owns its config schema** (`metadata.config_schema`), composed into the `secrets` namespace via DISCOVER — the same pattern provider adapters and sandbox backends use — so a `secrets.<name>` key only validates once its resolver is registered. `secrets.gcloud` is always available (a built-in resolver); `secrets.chatgpt` only validates when the experimental Codex adapter is loaded, since that adapter self-registers the ChatGPT resolver.

### Registering a custom resolver

Credential resolution runs on the send pipeline, so resolvers must be **non-blocking**. Implement `resolve_async(self, credential, ctx, callback)` and drive subprocesses through `vim.system(cmd, opts, on_exit)` — never `vim.fn.system` and never `vim.system(cmd):wait()`. The walker prefers `resolve_async` when both forms are present.

```lua
local s = require("flemma.schema")
local secrets = require("flemma.secrets")

secrets.register("my_vault", {
  name = "my_vault",
  priority = 60,  -- between environment (100) and keyring (50)

  -- Optional: own a config schema so `secrets.my_vault.*` is a valid setup() key.
  -- Defaults materialize on registration; read the subtree via ctx:get_config().
  metadata = {
    config_schema = s.object({
      mount = s.string("secret"),
      address = s.optional(s.string()),
    }),
  },

  supports = function(self, credential)
    return credential.service == "my-service"
  end,

  resolve_async = function(self, credential, ctx, callback)
    if vim.fn.executable("vault") ~= 1 then
      ctx:diagnostic("vault not found on PATH")
      callback(nil)
      return
    end

    vim.system(
      { "vault", "read", "-field=value", "secret/" .. credential.kind },
      { text = true },
      vim.schedule_wrap(function(result)
        if result.code ~= 0 then
          ctx:diagnostic("vault exit " .. result.code .. ": " .. (result.stderr or ""))
          callback(nil)
          return
        end
        callback({ value = vim.trim(result.stdout or ""), ttl = 300 })
      end)
    )
  end,
})
```

The resolver contract:

- **`supports(self, credential, ctx)`** → `boolean` – whether this resolver can attempt this credential. `ctx` is a `SecretsContext` (see below).
- **`resolve_async(self, credential, ctx, callback)`** – the preferred form. Call `callback(result_or_nil)` exactly once when done. The walker awaits it via `flemma.readiness`, so the send pipeline doesn't block while you fetch a token.
- **`resolve(self, credential, ctx)`** → `{ value: string, ttl?: integer } | nil` – sync fallback, used only when `resolve_async` isn't defined. A sync `resolve` that does its own blocking I/O (`vim.fn.system`, `:wait()`, etc.) freezes the editor — don't do this.
- **`metadata.config_schema`** (optional) – a schema DSL object describing the resolver's `secrets.<name>` config. Defaults materialize when the resolver registers, and `ctx:get_config()` returns the resolved subtree. Mirrors how provider adapters and sandbox backends own their schema; without it, `secrets.<name>` accepts no keys.

Resolvers receive a `SecretsContext` that provides:

- **`ctx:get_config()`** → `table|nil` – returns the resolver's config subtree from `secrets.<resolver_name>` (e.g., `secrets.gcloud` for the gcloud resolver). Returns a deep copy; modifications don't affect global config.
- **`ctx:diagnostic(message)`** – record a diagnostic explaining why this resolver couldn't help. These are surfaced in the failure notification when all resolvers fail.

For a worked example, see `lua/flemma/secrets/resolvers/gcloud.lua` — it composes an async sub-resolution (service-account file → token) entirely through `vim.system` callbacks.

### Invalidating credentials

```lua
local secrets = require("flemma.secrets")

secrets.invalidate("api_key", "anthropic")  -- invalidate a specific credential
secrets.invalidate_all()                    -- clear the entire cache
```

---

## Custom providers

Provider adapters are registered the same way as the built-ins. Point `providers.modules` at one or more Lua module paths and Flemma loads each module, reads its `M.metadata`, and registers it alongside the built-in adapters:

```lua
require("flemma").setup({
  providers = {
    modules = { "my_plugin.provider.adapters.custom" },
  },
})
```

A provider module inherits from `flemma.provider.base` and exports an `M.metadata` table. The full contract — the abstract/required/virtual method groups, the constructor metatable chain, the callbacks contract — is documented inline at the top of `lua/flemma/provider/base.lua`, and [docs/providers.md – Registering non-built-in adapters](providers.md#registering-non-built-in-adapters-providersmodules) walks through wiring an adapter end to end.

### Provider capabilities and metadata

A few `metadata` fields shape how the request pipeline treats a provider. They are easy to overlook because the built-ins set them implicitly:

| Field                              | Where                            | Default      | What it does                                                                                                                                                                                                                                   |
| ---------------------------------- | -------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `capabilities.output_has_thoughts` | `metadata.capabilities`          | `false`      | Whether the provider's reported `output_tokens` already includes thinking tokens. Affects cost calculation — set `true` when the API folds reasoning tokens into the output count.                                                             |
| `capabilities.close_on_complete`   | `metadata.capabilities`          | `true`       | Whether to terminate the HTTP connection once `on_response_complete` fires. The default suits backends that leave the SSE stream open after the terminal event; set `false` for providers that must keep the connection alive past completion. |
| `billing`                          | `metadata`                       | _(unset)_    | `"usage"` or `"subscription"` — the cost model for the provider, surfaced in session accounting.                                                                                                                                               |
| `endpoint`                         | instance field (`self.endpoint`) | _(required)_ | The base API URL, returned by `get_endpoint()`. Set it on the instance in `new()`; override `get_endpoint()` for dynamic URL construction (e.g. Vertex embeds project/location).                                                               |

Missing boolean capabilities default to `false` at registration time, except `close_on_complete`, which defaults to `true`. The other capability flags (`supports_reasoning`, `supports_thinking_budget`, `outputs_thinking`, `min_thinking_budget`) govern reasoning/thinking normalization and are documented inline in `base.lua`.

---

## Tool capability tags

Custom tools can declare **capability tags** — a `capabilities` array of string flags on the tool definition. Resolvers, approval policies, and the harness-parameter injector query these tags to decide how to treat the tool, so a tool opts into (or out of) cross-cutting behavior declaratively rather than through bespoke wiring:

```lua
tools.register("my_tool", {
  name = "my_tool",
  description = "...",
  capabilities = { "disables_save_to" },
  input_schema = s.object({ label = s.string() }),
  execute = function(input, ctx) --[[ ... ]] end,
})
```

The tags follow a `verb_target` convention. The current vocabulary:

| Tag                          | Effect                                                                                                                                     |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `disables_background`        | Suppresses injection of the `flemma.background` harness parameter into the tool's schema (async tools only — sync tools never receive it). |
| `disables_save_to`           | Suppresses injection of the `flemma.save_to` harness parameter. Use for tools whose output is ephemeral coordination metadata.             |
| `auto_approves_if_sandboxed` | Lets the sandbox approval resolver auto-approve calls when the sandbox is enabled with an available backend.                               |
| `emits_template`             | Marks the tool's output as containing template expressions (e.g. `read` emits file content that may include `{{ }}` syntax).               |

Query a tag with `require("flemma.tools.registry").has_capability(name, tag)`. For the fuller treatment — how the harness-parameter injector consults `disables_background`/`disables_save_to` (see [Harness parameters](tools.md#harness-parameters)) and how the priority-25 resolver consults `auto_approves_if_sandboxed` (see [Approval resolvers](tools.md#approval-resolvers)) — see [docs/tools.md](tools.md). Sandbox auto-approval conditions are detailed in [docs/sandbox.md](sandbox.md#requirements).

---

## Architectural contracts for extension authors

A few cross-cutting mechanisms aren't extension points themselves but every non-trivial extension brushes against at least one.

### `flemma.readiness` — non-blocking suspension

Any code reachable from the send pipeline that needs to wait on subprocess I/O — credential resolution, MCP discovery, tool definition resolution, usage estimation — must use the Suspense/boundary pattern in `flemma.readiness`. Leaf code raises `error(readiness.Suspense.new(message, boundary))`; orchestrators catch the sentinel via `pcall`, subscribe to the boundary, and retry the pipeline when it resolves. Concurrent consumers of the same boundary key (e.g. `secrets:vertex:access_token`) share one in-flight runner. The async secrets-resolver example above is wired through this — `resolve_async` doesn't block; the walker keys a boundary on the credential and re-runs the send when the callback fires.

Two practical rules fall out of this:

- **Never** `vim.system(cmd):wait()` from code that can reach the send pipeline. Use the async `vim.system(cmd, opts, on_exit)` form and hang the wait off a readiness boundary.
- Any `pcall` between a leaf that raises `Suspense` and the orchestrator that catches it must check `readiness.is_suspense(err)` and re-raise — otherwise the sentinel is swallowed and the request silently dies.

### `flemma.bridge` — breaking circular requires

When two modules genuinely need to call each other and the obvious `require` would cycle, route through `flemma.bridge` instead of papering over with delayed `require`. Bridge exposes lazy accessors that resolve on first use; the source module installs the implementation when it loads.

### The buffer AST is the only structural truth

Anything that inspects conversation structure — roles, tool use/result blocks, thinking blocks, positions — must read from the cached `flemma.ast.DocumentNode` (via `parser.get_parsed_document(bufnr)` or, inside tools, `ctx:get_parsed_document()`). Don't pattern-match buffer lines. If the AST lacks a field you need, extend the AST rather than bypassing it.

### Module-path registration

Several registries accept a Lua module path string in user config and load it through `flemma.loader`:

- `tools.register_module(module_path)` — load a tool module from a path string; validates existence up front and defers the `require`. The user-facing surface is `tools.modules` in setup config.
- `sandbox.register_module(module_path)` — same shape for sandbox backends.
- `templating.modules` — environment populators, loaded the same way.

Use these instead of bare `require()` when the path comes from config or user input — the loader is Flemma's extensibility contract and gives consistent error messages, lazy semantics, and the path validation users expect.

### Preprocessors and confirmations

Preprocessors run after parsing and before the request leaves Flemma — they rewrite conversation segments (file references, includes, ambient context injection) and surface user confirmations. The registry lives at `lua/flemma/preprocessor/registry.lua` with built-in rewriters under `lua/flemma/preprocessor/rewriters/`. Confirmation rewriters use the same readiness/Suspense pattern: a rewriter that needs the user's decision raises Suspense on a boundary that resolves when the user replies. Documentation is currently code-only; treat the existing rewriters as the contract until a dedicated doc lands.

---

## Extension point index

These extension points have full documentation in their respective pages:

| Extension point      | What it does                                                                  | Documentation                                                                                                            |
| -------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Custom tools         | Register tools the model can call                                             | [docs/tools.md – Registering custom tools](tools.md#registering-custom-tools)                                            |
| Tool capability tags | Declarative flags resolvers and harness injection query (`capabilities`)      | [docs/tools.md – Harness parameters](tools.md#harness-parameters)                                                        |
| Async tool sources   | Resolve tool definitions from external processes/APIs                         | [docs/tools.md – Async tool definitions](tools.md#async-tool-definitions)                                                |
| Approval resolvers   | Priority-based chain for tool approval decisions                              | [docs/tools.md – Approval resolvers](tools.md#approval-resolvers)                                                        |
| Custom providers     | Register non-built-in API adapters (`providers.modules`)                      | [docs/providers.md – Registering non-built-in adapters](providers.md#registering-non-built-in-adapters-providersmodules) |
| Sandbox backends     | Platform-specific sandbox enforcement                                         | [docs/sandbox.md – Custom backends](sandbox.md#custom-backends)                                                          |
| Personalities        | Dynamic system prompt generators                                              | [docs/personalities.md](personalities.md)                                                                                |
| Template populators  | Custom globals for `{{ }}` and `{% %}` expressions                            | [docs/templates.md – Extending the Environment](templates.md#extending-the-environment)                                  |
| Frontmatter parsers  | Custom frontmatter languages (e.g., YAML)                                     | [docs/templates.md – Custom frontmatter parsers](templates.md#custom-frontmatter-parsers)                                |
| List op-prefixes     | Compose append/prepend/remove/preset spread on list config in any frontmatter | [docs/templates.md – Op-prefix syntax for list values](templates.md#op-prefix-syntax-for-list-values)                    |
| Preview formatters   | Custom tool preview rendering in pending placeholders                         | [docs/tools.md – Custom preview formatters](tools.md#custom-preview-formatters)                                          |
