# Plugin Integrations

Flemma ships optional integrations for popular Neovim plugins. None create hard dependencies — they're inert unless you wire them into your config.

## Lualine

Add the bundled component to show the active model and thinking level:

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

The component only renders in `chat` buffers and returns an empty string otherwise.

### Format string

The display format is configurable via `statusline.format` in the [configuration reference](configuration.md) using a tmux-style format syntax. The default is:

```
#{model}#{?#{thinking}, (#{thinking}),}
```

Which produces `claude-sonnet-4-5 (high)` when thinking is active, or just `claude-sonnet-4-5` when it's off.

#### Variables

Variables are lazy-evaluated — only variables referenced by the format string trigger data lookups.

**Config state:**

| Variable      | Example                 | Description                                    |
| ------------- | ----------------------- | ---------------------------------------------- |
| `#{model}`    | `claude-sonnet-4-6`     | Current model name                             |
| `#{provider}` | `anthropic`             | Current provider name                          |
| `#{thinking}` | `high`, `medium`, `low` | Thinking/reasoning level (empty when inactive) |

**Session totals** (cumulative across all requests in this Neovim session):

| Variable                   | Example | Description                   |
| -------------------------- | ------- | ----------------------------- |
| `#{session.cost}`          | `$1.23` | Total session cost            |
| `#{session.requests}`      | `5`     | Number of completed requests  |
| `#{session.tokens.input}`  | `15K`   | Total input tokens (compact)  |
| `#{session.tokens.output}` | `2.5M`  | Total output tokens (compact) |

**Last request:**

| Variable                | Example | Description                              |
| ----------------------- | ------- | ---------------------------------------- |
| `#{last.cost}`          | `$0.38` | Cost of the most recent request          |
| `#{last.tokens.input}`  | `100K`  | Input tokens of the most recent request  |
| `#{last.tokens.output}` | `5K`    | Output tokens of the most recent request |

All session/request variables return empty when no requests have been made, so they work naturally with conditionals.

#### Syntax

| Syntax                           | Purpose                         | Example                                           |
| -------------------------------- | ------------------------------- | ------------------------------------------------- |
| `#{name}`                        | Variable expansion              | `#{model}` → `o3`                                 |
| `#{?cond,true,false}`            | Ternary conditional             | `#{?#{thinking},yes,no}`                          |
| `#{==:a,b}`                      | String equality (returns 1/0)   | `#{==:#{provider},anthropic}`                     |
| `#{!=:a,b}`                      | String inequality (returns 1/0) | `#{!=:#{provider},openai}`                        |
| `#{&&:a,b}`                      | Logical AND (returns 1/0)       | `#{&&:#{thinking},#{model}}`                      |
| <code>#{&#124;&#124;:a,b}</code> | Logical OR (returns 1/0)        | <code>#{&#124;&#124;:#{model},#{provider}}</code> |
| `#,`                             | Literal comma                   | `a#,b` → `a,b`                                    |

A value is **truthy** if it is non-empty and not `"0"`. Expressions nest freely — each branch of a conditional is expanded recursively.

#### Examples

```lua
-- Default: "claude-sonnet-4-5 (high)" or "claude-sonnet-4-5"
format = '#{model}#{?#{thinking}, (#{thinking}),}'

-- Provider prefix: "anthropic:claude-sonnet-4-5"
format = '#{provider}:#{model}'

-- Square brackets for thinking: "o3 [high]" or "o3"
format = '#{model}#{?#{thinking}, [#{thinking}],}'

-- Provider-conditional label: "A: claude-sonnet-4-5" or "O: o3"
format = '#{?#{==:#{provider},anthropic},A,O}: #{model}'

-- Running session cost: "claude-sonnet-4-5 $1.23" or "claude-sonnet-4-5"
format = '#{model}#{?#{session.cost}, #{session.cost},}'

-- Full dashboard: "claude-sonnet-4-5 (high) $1.23 [5]"
format = '#{model}#{?#{thinking}, (#{thinking}),}#{?#{session.cost}, #{session.cost},}#{?#{session.requests}, [#{session.requests}],}'
```

The component only shows data in `chat` buffers and respects per-buffer overrides from `flemma.opt` — if frontmatter changes the thinking level, the statusline reflects it.

## Bufferline

Show a busy indicator on `.chat` tabs while a request or tool execution is in-flight:

```lua
require("bufferline").setup({
  options = {
    get_element_icon = require("flemma.integrations.bufferline").get_element_icon,
  },
})
```

When a buffer is busy, its tab icon changes to `󰔟` (highlighted with `FlemmaBusy`, which defaults to `DiagnosticWarn`). When idle, the icon falls through to nvim-web-devicons as normal.

### Custom icon

Pass `{ icon = "..." }` to use a different character:

```lua
get_element_icon = require("flemma.integrations.bufferline").get_element_icon({ icon = "+" })
```

### How it works

The module listens to four Flemma hooks via User autocmds:

| Event                   | Effect                 |
| ----------------------- | ---------------------- |
| `FlemmaRequestSending`  | Increment busy counter |
| `FlemmaToolExecuting`   | Increment busy counter |
| `FlemmaRequestFinished` | Decrement busy counter |
| `FlemmaToolFinished`    | Decrement busy counter |

A buffer shows the busy icon while its counter is above zero. This handles overlapping request and tool lifecycles naturally. When a buffer is wiped, its counter is cleared.

### Highlight

The `FlemmaBusy` highlight group is configurable via `highlights.busy` in your Flemma setup:

```lua
require("flemma").setup({
  highlights = {
    busy = "DiagnosticWarn",  -- default; any highlight group, hex color, or expression
  },
})
```
