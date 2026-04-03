# MCP Support via MCPorter

Flemma supports the [Model Context Protocol](https://modelcontextprotocol.io) (MCP) through [MCPorter](https://github.com/steipete/mcporter), a standalone CLI toolkit that handles server discovery, connection management, and OAuth. Flemma discovers MCPorter's servers at startup and registers each tool as a native Flemma tool definition -- the model sees them alongside built-in tools like `bash` and `read`.

## Why MCPorter?

MCP is a large, evolving protocol with OAuth flows, multiple transports (HTTP, stdio, SSE), connection pooling, and credential management. Rather than reimplement all of that inside a Neovim plugin, Flemma delegates to MCPorter:

- **OAuth and credentials** -- MCPorter handles browser-based OAuth flows, token caching, and auto-refresh. Flemma never touches credentials for MCP servers.
- **Server management** -- MCPorter auto-discovers servers from your config and from editor configs (Claude Code, Cursor, VS Code, etc.). Add a server once and it's available everywhere.
- **Stable CLI interface** -- Flemma talks to MCPorter through `mcporter list --json` and `mcporter call`, both machine-readable. The integration is a thin shell around well-defined commands.
- **Maintained separately** -- MCPorter tracks MCP protocol changes, transport updates, and server quirks independently. Flemma gets those fixes for free.

## Setup

### 1. Install MCPorter

```bash
# Homebrew
brew tap steipete/tap && brew install steipete/tap/mcporter

# npm (global)
npm install -g mcporter
```

### 2. Configure your MCP servers

MCPorter reads from `~/.mcporter/mcporter.json` (global) and `config/mcporter.json` (per-project). It also auto-imports servers from Claude Code, Cursor, Windsurf, and VS Code.

```json
// ~/.mcporter/mcporter.json
{
  "mcpServers": {
    "linear": {
      "baseUrl": "https://mcp.linear.app/mcp"
    },
    "slack": {
      "command": "npx",
      "args": ["slack-mcp-server"],
      "env": {
        "SLACK_MCP_XOXC_TOKEN": "${SLACK_MCP_XOXC_TOKEN}",
        "SLACK_MCP_XOXD_TOKEN": "${SLACK_MCP_XOXD_TOKEN}"
      }
    }
  },
  "imports": ["claude-code", "cursor"]
}
```

Verify your servers are reachable:

```bash
mcporter list
```

### 3. Enable in Flemma

```lua
require("flemma").setup({
  tools = {
    mcporter = {
      enabled = true,
      include = { "slack:*", "linear:*" },
    },
  },
})
```

That's it. On the next Neovim startup, Flemma discovers the servers, fetches their tool schemas, and registers them. You'll see them in `:Flemma status verbose` under the tools section.

---

## Configuration

All MCPorter settings live under `tools.mcporter`:

```lua
tools = {
  mcporter = {
    enabled = false,             -- master switch (default: off)
    path = "mcporter",           -- binary path or command
    timeout = 60,                -- per-operation timeout in seconds
    startup = {
      concurrency = 4,           -- max parallel schema fetches
    },
    include = {},                -- glob patterns: matching tools are enabled
    exclude = {},                -- glob patterns: matching tools are skipped entirely
  },
}
```

### Include / exclude

Glob patterns use `*` as a wildcard. Both match against the full tool name (`server:tool_name`).

1. **Exclude** runs first -- matching tools are not registered at all.
2. **Include** runs second -- matching tools are marked `enabled = true`.
3. **Remainder** -- tools that survive exclude but don't match include are registered with `enabled = false` (available for per-file opt-in).

| Goal                                | Config                                       |
| ----------------------------------- | -------------------------------------------- |
| Enable all Slack tools              | `include = { "slack:*" }`                    |
| Enable Slack + Linear search        | `include = { "slack:*", "linear:search_*" }` |
| Enable everything                   | `include = { "*" }`                          |
| Discover everything, enable nothing | `include = {}` (default)                     |
| Skip GitHub entirely                | `exclude = { "github:*" }`                   |

### Per-file opt-in

Tools registered with `enabled = false` (discovered but not included) can be enabled in individual `.chat` files via frontmatter:

````markdown
```lua
flemma.opt.tools:append({"slack:channels_list", "slack:conversations_unreads"})
```

@System:
You are a Slack assistant.

@You:
List the public channels and my unread messages.
````

This lets you discover all available tools at startup but only pay the token cost for tools relevant to each conversation.

---

## How it works

### Discovery (startup)

When `tools.mcporter.enabled` is `true`, Flemma runs a three-phase discovery at startup:

1. **Gate check** -- verify the `mcporter` binary is on `$PATH` (or at the configured path).
2. **Server manifest** -- run `mcporter list --json` to get all configured servers and their health status. Unhealthy servers are skipped.
3. **Schema fanout** -- for each healthy server, run `mcporter list <server> --json --schema` to fetch tool names, descriptions, and input schemas. Up to `startup.concurrency` (default 4) fetches run in parallel.

Tools from fast servers become available immediately -- you don't have to wait for every server to respond. If a server times out or fails, its tools are skipped and the rest proceed normally.

### Tool naming

Each discovered tool is named `server:tool_name` using a colon separator. Dots in server names are replaced with hyphens (dots are reserved for Lua module paths in Flemma).

| MCPorter server + tool          | Flemma tool name            |
| ------------------------------- | --------------------------- |
| `slack` + `channels_list`       | `slack:channels_list`       |
| `github` + `search_code`        | `github:search_code`        |
| `my.custom.server` + `do_thing` | `my-custom-server:do_thing` |

On the wire (in API requests to LLM providers), the colon is encoded to `__` to satisfy provider name constraints (`[a-zA-Z0-9_-]+`). This encoding is transparent -- you always use colons in config and frontmatter.

### Execution

When the model invokes an MCP tool, Flemma runs:

```
mcporter call <server>.<tool> --args '<json>' --output json
```

The response is parsed as an MCP [`CallToolResult`](https://modelcontextprotocol.io/specification/2025-11-25/schema#calltoolresult). Only text content blocks are extracted -- image and resource blocks are not representable in the `.chat` buffer format and are dropped with a log warning. If the MCP server returns a tool-level error (`isError: true`), it surfaces as a tool error in the conversation.

### Timeouts

| Scope                                    | Default | Config                                  |
| ---------------------------------------- | ------- | --------------------------------------- |
| Per-operation (list, schema fetch, call) | 60s     | `tools.mcporter.timeout`                |
| Global discovery                         | 120s    | Framework limit -- partial results kept |

---

## Troubleshooting

Run `:Flemma status verbose` to see all registered tools, their source, and enabled state.

| Problem                        | Fix                                                                                                                                   |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| No MCP tools appear            | Check `tools.mcporter.enabled = true`. Run `mcporter list` in your terminal to verify servers are healthy.                            |
| Tool shows as disabled         | It wasn't matched by your `include` patterns. Add the pattern or enable it per-file via frontmatter.                                  |
| "Binary not found" in logs     | `mcporter` isn't on `$PATH`. Set `tools.mcporter.path` to the full path, or install it globally.                                      |
| Tool call fails                | Run `mcporter call <server>.<tool> --args '{}' --output json` manually to debug. Check `mcporter auth <server>` if OAuth is required. |
| Discovery is slow              | Reduce the number of servers, or increase `startup.concurrency`. Servers that time out are skipped after `timeout` seconds.           |
| "Waiting for tool definitions" | Discovery is still running. This clears automatically once all servers respond or time out.                                           |

---

## Further reading

- [MCPorter documentation](https://github.com/steipete/mcporter) -- server configuration, OAuth, ad-hoc servers, daemon mode
- [tools.md](tools.md) -- Flemma's tool system, approval policies, custom tools
- [configuration.md](configuration.md) -- full config reference
- [templates.md](templates.md) -- per-file settings and frontmatter
