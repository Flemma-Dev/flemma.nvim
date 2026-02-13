# Session API

Flemma tracks token usage and costs for every API request in a global session object. The session lives in memory for the lifetime of the Neovim instance and is accessible through the `flemma.session` module.

## Reading the current session

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

## Saving and restoring a session

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
