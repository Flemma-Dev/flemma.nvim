# Providers

Flemma talks to LLMs through **providers**. Four are built in; a fifth — the experimental Codex / ChatGPT-subscription adapter — is opt-in. The active provider is part of the _(conversation, environment)_ pair: it can be set globally in `setup()`, per-buffer in frontmatter, or switched at any time with `:Flemma switch`.

## Built-in providers

| Provider      | Default model            | Credential                                      |
| ------------- | ------------------------ | ----------------------------------------------- |
| **Anthropic** | `claude-sonnet-4-6`      | `ANTHROPIC_API_KEY`                             |
| **OpenAI**    | `gpt-5.4`                | `OPENAI_API_KEY`                                |
| **Vertex AI** | `gemini-3.1-pro-preview` | `VERTEX_AI_ACCESS_TOKEN` (or a service account) |
| **Moonshot**  | `kimi-k2.6`              | `MOONSHOT_API_KEY`                              |

All four support extended thinking/reasoning through the unified `thinking` parameter and automatic [prompt caching](prompt-caching.md). Credentials are resolved from environment variables or your platform keyring — see [Setting up credentials](../README.md#quick-start) in the README and the [credential resolution](extending.md#credential-resolution) reference.

## Selecting a provider and model

Set the provider and model in `setup()` (or per-buffer in frontmatter):

```lua
require("flemma").setup({
  provider = "anthropic",
  model = nil, -- nil = the provider's default model
})
```

Or switch at runtime with `:Flemma switch`:

```vim
:Flemma switch openai
:Flemma switch openai gpt-5.4 temperature=0.3
```

### `provider/model` slash syntax

`:Flemma switch` (and presets and frontmatter) also accept a combined `provider/model` token, which selects the provider and model in one go:

```vim
:Flemma switch codex/gpt-5.5
```

```lua
presets = {
  ["$codex"] = "codex/gpt-5.5",
}
```

This is the most convenient way to drive a non-default provider whose models you switch between often.

## Registering non-built-in adapters (`providers.modules`)

Adapters that are not part of the built-in set are registered through `providers.modules` — a list of Lua module paths, each resolving to a provider adapter:

```lua
require("flemma").setup({
  providers = {
    modules = { "flemma.provider.adapters.experimental.codex" },
  },
})
```

Each listed module is loaded at `setup()` and added to the provider registry, after which its provider name (and models) are usable with `:Flemma switch`, presets, and frontmatter exactly like a built-in. This is the extension point for the experimental Codex provider below, and for third-party or custom provider adapters.

## Codex / ChatGPT subscription (experimental)

> [!IMPORTANT]
> This provider is **experimental and opt-in**. It is not a built-in provider, its wire format may change, and it depends on the external [Codex CLI](https://github.com/openai/codex) for authentication.

The Codex adapter lets ChatGPT subscribers drive Flemma with the OAuth token from their existing `codex login` session — no OpenAI Platform API key required. It speaks the OpenAI Responses API wire format against the ChatGPT backend (`https://chatgpt.com/backend-api/codex/responses`), and usage is covered by your ChatGPT subscription rather than billed per token.

### 1. Enable the adapter

Register the module in `providers.modules`:

```lua
require("flemma").setup({
  providers = {
    modules = { "flemma.provider.adapters.experimental.codex" },
  },
})
```

### 2. Authenticate

Flemma does **not** run its own login flow — it reads the credentials written by the Codex CLI. Install the [Codex CLI](https://github.com/openai/codex), then run:

```bash
codex login
```

and choose **"Sign in with ChatGPT"**. Flemma then reads the resulting auth file, in this order:

1. `secrets.chatgpt.auth_file` (if you set an explicit path in `setup()`),
2. `$CODEX_HOME/auth.json`,
3. `~/.codex/auth.json` (the Codex CLI default).

Most users need no configuration — the default fallbacks find a standard `codex login`. The explicit path is optional, for when the auth file lives somewhere non-standard:

```lua
require("flemma").setup({
  secrets = {
    chatgpt = {
      auth_file = nil, -- nil = fall back to $CODEX_HOME/auth.json, then ~/.codex/auth.json
    },
  },
})
```

The file must be in ChatGPT-subscription mode (`auth_mode = "chatgpt"`); if it is in API-key mode, Flemma tells you to re-run `codex login` and pick the ChatGPT option.

> [!NOTE]
> When the access token expires, Flemma refreshes it against OpenAI's OAuth endpoint and **writes the refreshed token back into the Codex CLI's auth file** (the same file `codex` itself uses). If refresh fails, run `codex login` again.

### 3. Select a Codex model

Use the [`provider/model` slash syntax](#providermodel-slash-syntax):

```vim
:Flemma switch codex/gpt-5.5
```

| Model                 | Context (in / out) | Notes                      |
| --------------------- | ------------------ | -------------------------- |
| `gpt-5.5` (default)   | 272K / 128K        | Reasoning                  |
| `gpt-5.4`             | 272K / 128K        | Reasoning                  |
| `gpt-5.4-mini`        | 272K / 128K        | Reasoning, lighter/cheaper |
| `gpt-5.3-codex-spark` | 128K / 128K        | Reasoning                  |

> [!NOTE]
> The cost shown in the usage bar uses OpenAI Platform **list pricing for display only** — actual usage is covered by your ChatGPT subscription, not billed per token.

### Subscription rate limits

The Codex backend reports rolling rate-limit windows (typically a 5-hour and a weekly window) in its response headers. Flemma surfaces these in the usage bar and through the lualine `subscription.*` resolvers — see [integrations.md](integrations.md#lualine) and the [`rate_limits`](session-api.md#subscription-rate-limits) field in the session API.

This subscription display is keyed off the provider's `billing = "subscription"` metadata: instead of a per-token cost warning, switching to the Codex provider shows a subscription notice (_"Flemma draws from your subscription usage limit"_), and the usage bar / lualine present the rate-limit windows rather than a per-request dollar cost.

### Caveats

> [!IMPORTANT]
> This integration is for **personal development use** with **your own** ChatGPT subscription. It uses OpenAI's **unofficial** Codex OAuth path (the same one the Codex CLI uses) and **may break without notice** if OpenAI changes it. It is **not officially supported** by OpenAI, and using it is **at your own discretion regarding OpenAI's [Terms of Use](https://openai.com/policies/row-terms-of-use/)**. For production, multi-user, automated, or commercial use, use an OpenAI Platform API key instead. **Do not pool accounts or share credentials.**

- **Opt-in, not built-in** — requires the `providers.modules` registration above; it does not appear unless you add it.
- **Experimental wire format** — the request is sent with an `OpenAI-Beta: responses=experimental` header; the backend's behaviour may change.
- **Server-controlled output** — `max_tokens` and `temperature` are managed by the ChatGPT backend; values you set for them are silently ignored.
- **Token estimate is approximate before the first response** — there is no subscription token-count endpoint, so the statusline estimate is a `bytes / 4` heuristic until the first real response seeds actual usage from the server.
- **Flemma rewrites the Codex auth file** — token refresh updates `~/.codex/auth.json` in place (see above).
