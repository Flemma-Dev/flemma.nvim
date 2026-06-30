# Session API

Flemma tracks token usage and costs for every API request in a global session object. The session lives in memory for the lifetime of the Neovim instance and is accessible through the `flemma.session` module.

## Module functions

### `session.get()`

Returns the global `Session` instance that tracks all requests across all buffers.

```lua
local session = require("flemma.session").get()
```

### `session.now()`

Returns the current wall-clock time as a Unix timestamp with microsecond precision (e.g. `1700000042.123456`). Used internally for request timestamps but available for general use.

```lua
local ts = require("flemma.session").now()
```

## Reading the current session

Two ways to observe session state: poll the singleton on demand, or subscribe to the `request:finished` hook (see [docs/extending.md](extending.md#hooks-lifecycle-events)). The hook fires after a request is recorded and carries the just-added `flemma.session.Request` as `data.request`, so you can update UI without polling.

> [!NOTE]
> A request is only added to the session when the resolved model has registry pricing. Requests against custom or unknown models — where `flemma.models.registry.get_model_info(...).pricing` returns `nil` — silently skip session recording. If you're iterating on a new model and see no `request:finished` payload and an unchanged session, that's why.

```lua
local session = require("flemma.session").get()

-- Aggregate stats
print("Requests:", session:get_request_count())
print("Input tokens:", session:get_total_input_tokens())
print("Output tokens:", session:get_total_output_tokens())
print("Thinking tokens:", session:get_total_thoughts_tokens())
print("Total cost: $" .. string.format("%.4f", session:get_total_cost()))

-- Iterate individual requests
for _, request in ipairs(session.requests) do
  print(string.format(
    "%s/%s  in=%d out=%d  $%.4f  %s",
    request.provider,
    request.model,
    request:get_total_input_tokens(),
    request:get_total_output_tokens(),
    request:get_total_cost(),
    request.filepath or "(unnamed)"
  ))
end

-- Inspect the most recent request
local latest = session:get_latest_request()
if latest then
  print("Last model:", latest.provider .. "/" .. latest.model)
end

-- Filter by file
local req = session:get_latest_request_for_filepath(vim.fn.expand("%:p"))
```

## Request fields

Each request stores raw data -- tokens, per-million prices, cache pricing, and timestamps -- so costs are always derived from the underlying components.

| Field                                                    | Description                                                                                                                                                                                         |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `provider`, `model`                                      | Provider and model that handled the request                                                                                                                                                         |
| `input_tokens`, `output_tokens`, `thoughts_tokens`       | Raw token counts (see `output_has_thoughts` for how thinking tokens relate to output)                                                                                                               |
| `input_price`, `output_price`                            | USD per million tokens (snapshot at request time)                                                                                                                                                   |
| `cache_read_input_tokens`, `cache_creation_input_tokens` | Cache token counts                                                                                                                                                                                  |
| `cache_read_price`, `cache_write_price`                  | USD per million cache tokens (`nil` when the provider does not support caching)                                                                                                                     |
| `output_has_thoughts`                                    | Whether `output_tokens` already includes thinking tokens (true for OpenAI/Anthropic, false for Vertex)                                                                                              |
| `started_at`, `completed_at`                             | Timestamps as seconds since epoch with microsecond precision (e.g. `1700000042.123456`)                                                                                                             |
| `filepath`, `bufnr`                                      | Source buffer identifier (`filepath` is the resolved absolute path; either may be `nil`)                                                                                                            |
| `rate_limits`                                            | Subscription rate-limit snapshot (`flemma.session.RateLimitSnapshot`) when the provider reports one (e.g. the experimental Codex / ChatGPT-subscription provider); `nil` for usage-billed providers |

### Subscription rate limits

Providers that bill against a subscription quota rather than per-token attach a rate-limit snapshot to each request through the `rate_limits` field. Currently only the experimental Codex / ChatGPT-subscription provider populates it (parsed from the response headers); every other provider leaves it `nil`.

| Type                               | Shape                                                                                                                                                 |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `flemma.session.RateLimitSnapshot` | `plan_name?` (human-readable plan, e.g. `"Plus"`/`"Pro"`), `windows` (a list of `RateLimitWindow`, ordered shortest-window-first / most-urgent-first) |
| `flemma.session.RateLimitWindow`   | `used_percent` (0–100 consumed), `window_seconds` (rolling window length), `resets_at?` (Unix seconds when the window resets)                         |

These feed the usage bar and the lualine resolvers (see [docs/integrations.md](integrations.md)); the 5-hour and weekly Codex windows are the typical entries.

## Request methods

| Method                      | Returns  | Description                                                                                                                            |
| --------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `get_input_cost()`          | `number` | Input cost in USD (cache-aware: uses cache-specific prices when available, falls back to input price)                                  |
| `get_output_cost()`         | `number` | Output cost in USD (adds `thoughts_tokens` when they are separate from `output_tokens`)                                                |
| `get_total_cost()`          | `number` | Sum of input and output cost                                                                                                           |
| `get_total_input_tokens()`  | `number` | `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` (the API reports `input_tokens` as only the non-cached portion) |
| `get_total_output_tokens()` | `number` | Total output tokens including thinking (provider-aware: includes `thoughts_tokens` only when separate)                                 |

## Session methods

| Method                                      | Returns        | Description                                              |
| ------------------------------------------- | -------------- | -------------------------------------------------------- |
| `get_request_count()`                       | `number`       | Number of requests in the session                        |
| `get_total_input_tokens()`                  | `number`       | Sum of `get_total_input_tokens()` across all requests    |
| `get_total_output_tokens()`                 | `number`       | Sum of `get_total_output_tokens()` across all requests   |
| `get_total_thoughts_tokens()`               | `number`       | Sum of raw `thoughts_tokens` across all requests         |
| `get_total_input_cost()`                    | `number`       | Total input cost in USD                                  |
| `get_total_output_cost()`                   | `number`       | Total output cost in USD                                 |
| `get_total_cost()`                          | `number`       | Total cost in USD                                        |
| `get_latest_request()`                      | `Request\|nil` | Most recent request, or `nil` if none                    |
| `get_latest_request_for_filepath(filepath)` | `Request\|nil` | Most recent request matching the given absolute filepath |
| `reset()`                                   |                | Clear all requests                                       |
| `load(requests_data)`                       |                | Replace session with a list of `RequestOpts` tables      |

## Recipes

### Resetting the session

`Session:reset()` clears all accumulated requests, zeroing token and cost counters without restarting Neovim:

```lua
require("flemma.session").get():reset()
```

### Saving and restoring a session

`Session:load()` accepts a list of option tables in the same format as `add_request()` and replaces the current session contents. Combined with reading `session.requests`, this enables crude persistence:

```lua
local json = require("flemma.utilities.json")

-- Save to a JSON file
local session = require("flemma.session").get()
local encoded = json.encode(session.requests)
vim.fn.writefile({ encoded }, vim.fn.stdpath("data") .. "/flemma_session.json")

-- Restore from a saved file
local path = vim.fn.stdpath("data") .. "/flemma_session.json"
local lines = vim.fn.readfile(path)
if #lines > 0 then
  require("flemma.session").get():load(json.decode(table.concat(lines, "\n")))
end
```
