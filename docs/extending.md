# Extending Flemma

Flemma uses registry patterns throughout – tools, approval resolvers, sandbox backends, credential resolvers, and personalities are all pluggable. This guide covers the extension points that don't have a dedicated document, and links to those that do.

---

## Hooks (Lifecycle Events)

Flemma emits [User autocmds](https://neovim.io/doc/user/autocmd.html#User) at lifecycle boundaries. External plugins listen with standard Neovim autocommand APIs – no Flemma-specific setup required.

### Available events

| Event name         | Autocmd pattern         | Payload fields                                                       | When it fires                                |
| ------------------ | ----------------------- | -------------------------------------------------------------------- | -------------------------------------------- |
| `request:sending`  | `FlemmaRequestSending`  | `bufnr`                                                              | Just before an API request is sent           |
| `request:finished` | `FlemmaRequestFinished` | `bufnr`, `status` (`"completed"`, `"cancelled"`, or `"errored"`)     | After an API request completes (any outcome) |
| `tool:executing`   | `FlemmaToolExecuting`   | `bufnr`, `tool_name`, `tool_id`                                      | When a tool invocation starts execution      |
| `tool:finished`    | `FlemmaToolFinished`    | `bufnr`, `tool_name`, `tool_id`, `status` (`"success"` or `"error"`) | When a tool invocation completes             |
| `boot:complete`    | `FlemmaBootComplete`    | _(none)_                                                             | After all async tool sources finish loading  |
| `sink:created`     | `FlemmaSinkCreated`     | `bufnr`, `name`                                                      | When a new output buffer (sink) is created   |
| `sink:destroyed`   | `FlemmaSinkDestroyed`   | `bufnr`, `name`                                                      | When an output buffer (sink) is destroyed    |

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
- `tool:finished` → `FlemmaToolFinished`
- Hyphenated words are split: `tool-use:finished` → `FlemmaToolUseFinished`

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

---

## Credential Resolution

Flemma resolves API keys and tokens through a priority-based resolver chain. The first resolver that finds a credential wins. Results are cached with TTL awareness to avoid repeated lookups.

### Resolution order

| Priority | Resolver       | Platform     | What it checks                                                       |
| -------- | -------------- | ------------ | -------------------------------------------------------------------- |
| 100      | Environment    | All          | `{SERVICE}_{KIND}` env var (e.g., `ANTHROPIC_API_KEY`), then aliases |
| 50       | Secret Service | Linux        | `secret-tool lookup service {service} key {kind}` (GNOME Keyring)    |
| 50       | Keychain       | macOS        | `security find-generic-password -s {service} -a {kind} -w`           |
| 25       | Gcloud         | All (w/ CLI) | `gcloud auth print-access-token` (only for `access_token` kind)      |

### How it works

1. **Cache check** – if a cached credential exists and its TTL hasn't expired, return it immediately.
2. **Resolver iteration** – try each resolver in priority order (highest first). Each resolver's `supports()` method filters by platform, credential kind, or service.
3. **First match wins** – the first resolver that returns a value is used. The result is cached.
4. **Fallback** – if no resolver succeeds, a warning is shown with the credential description.

### Environment resolver conventions

The environment resolver constructs the variable name from the credential's service and kind:

| Service   | Kind            | Variable checked         |
| --------- | --------------- | ------------------------ |
| anthropic | api_key         | `ANTHROPIC_API_KEY`      |
| openai    | api_key         | `OPENAI_API_KEY`         |
| vertex    | access_token    | `VERTEX_AI_ACCESS_TOKEN` |
| vertex    | service_account | `VERTEX_SERVICE_ACCOUNT` |

Credentials can also define `aliases` – alternative variable names checked in order after the convention.

### TTL caching

Credentials are cached per `kind:service` key (e.g., `api_key:anthropic`). The effective TTL is:

```
effective_ttl = base_ttl * ttl_scale
```

Where `base_ttl` comes from the resolver result or credential config, and `ttl_scale` (default `1.0`) allows adjusting the refresh window (e.g., `0.8` to refresh at 80% of token lifetime). When no TTL is set, the credential caches indefinitely until manually invalidated.

### Registering a custom resolver

```lua
local secrets = require("flemma.secrets")

secrets.register("my_vault", {
  name = "my_vault",
  priority = 60,  -- between environment (100) and keyring (50)

  supports = function(self, credential)
    return credential.service == "my-service"
  end,

  resolve = function(self, credential)
    local value = vim.fn.system("vault read -field=value secret/" .. credential.kind)
    if vim.v.shell_error == 0 then
      return { value = vim.trim(value), ttl = 300 }
    end
    return nil  -- pass to next resolver
  end,
})
```

The resolver contract:

- **`supports(self, credential)`** → `boolean` – whether this resolver can attempt this credential.
- **`resolve(self, credential)`** → `{ value: string, ttl?: integer } | nil` – the credential value, or `nil` to pass.

### Invalidating credentials

```lua
local secrets = require("flemma.secrets")

secrets.invalidate("api_key", "anthropic")  -- invalidate a specific credential
secrets.invalidate_all()                    -- clear the entire cache
```

---

## Extension point index

These extension points have full documentation in their respective pages:

| Extension point     | What it does                                          | Documentation                                                                             |
| ------------------- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Custom tools        | Register tools the model can call                     | [docs/tools.md – Registering custom tools](tools.md#registering-custom-tools)             |
| Async tool sources  | Resolve tool definitions from external processes/APIs | [docs/tools.md – Async tool definitions](tools.md#async-tool-definitions)                 |
| Approval resolvers  | Priority-based chain for tool approval decisions      | [docs/tools.md – Approval resolvers](tools.md#approval-resolvers)                         |
| Sandbox backends    | Platform-specific sandbox enforcement                 | [docs/sandbox.md – Custom backends](sandbox.md#custom-backends)                           |
| Personalities       | Dynamic system prompt generators                      | [docs/personalities.md](personalities.md)                                                 |
| Frontmatter parsers | Custom frontmatter languages (e.g., YAML)             | [docs/templates.md – Custom frontmatter parsers](templates.md#custom-frontmatter-parsers) |
| Preview formatters  | Custom tool preview rendering in pending placeholders | [docs/tools.md – Custom preview formatters](tools.md#custom-preview-formatters)           |
