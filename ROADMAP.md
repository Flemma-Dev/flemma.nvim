# Roadmap

What's coming in the next milestone. Items are listed in no particular order — priorities shift as the project evolves.

## v0.9.0+

### Personalities as `.chat` templates

Personalities today are Lua modules with a `render()` function. This works, but it means authoring a personality requires writing Lua code when really you just want to write a prompt.

The plan is to migrate personalities to `.chat` files that use the same `{{ expression }}` and `{% code %}` template syntax that regular `.chat` buffers already support. The built-in `coding-assistant` personality will be the first to move. Since `include()` already handles `.chat` files, the existing builder/registry indirection can be stripped away — a personality becomes a file you can read, edit, and share without touching Lua.

### Template engine content emission

The `{% code %}` blocks in Flemma's template engine currently support variable assignment and control flow, but there's no way to emit content from inside them. Adding `print()` (or an equivalent) lets code blocks produce output directly, making templates more expressive without requiring workarounds like building strings in variables and interpolating them separately.

### Slash commands

A full slash-command engine for `.chat` buffers. The scope includes:

- **Registration** — a registry for built-in and user-defined commands, with each command declaring its accepted arguments and behaviour.
- **Parsing** — slash commands recognised at the AST level so they participate in syntax highlighting, diagnostics, and completion.
- **Preprocessing** — commands fire as preprocessor rewriters before the request is sent, allowing them to modify the document (inject system prompts, toggle config, expand macros).
- **Namespacing** — commands are namespaced (e.g., `/flemma:thinking`) with automatic short-form resolution when unambiguous (just `/thinking`), so community plugins can define their own top-level commands without collisions.
- **Config integration** — commands that map to config values (like `/thinking off` or `/thinking budget=2048`) are validated and coerced through the existing config schema, giving type-checked inline configuration for free.
- **Personality wiring** — activating a personality via slash command (e.g., `/coding-assistant language=php`), with promotion from `@You` to `@System` so users don't have to manage role placement manually.
- **Completion** — a completion source that triggers on `/` at line start and enumerates available commands and their arguments.

### MCP support via MCPorter

[MCPorter](https://github.com/steipete/mcporter) is a TypeScript runtime, CLI, and code-generation toolkit for the Model Context Protocol. It discovers MCP servers already configured on your system (Cursor, Claude Desktop, Codex, VS Code, and others), handles transport negotiation (stdio, HTTP, SSE), OAuth flows, connection pooling, and exposes tools through a composable API — all without requiring any MCP-specific boilerplate.

By integrating MCPorter as an external process, Flemma gains access to the entire MCP ecosystem without reimplementing the protocol. The integration surfaces MCP server tools as regular Flemma tools with JSON Schema inputs, namespaced actions (e.g., `slack.list_channels`), approval policies, and inline previews — the same experience as built-in tools. A proof-of-concept with GitHub and Slack MCP servers is already working.

---

This roadmap reflects current intentions and is subject to change. Follow the [changelog](CHANGELOG.md) for what has shipped.
