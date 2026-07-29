# Roadmap

What's coming in the next milestone. Items are listed in no particular order — priorities shift as the project evolves.

## Next milestone

### Personalities as `.chat` templates

Personalities today are Lua modules with a `render()` function. This works, but it means authoring a personality requires writing Lua code when really you just want to write a prompt.

The plan is to migrate personalities to `.chat` files that use the same `{{ expression }}` and `{% code %}` template syntax that regular `.chat` buffers already support. The built-in `coding-assistant` personality will be the first to move. Since `include()` already handles `.chat` files, the existing builder/registry indirection can be stripped away — a personality becomes a file you can read, edit, and share without touching Lua.

### Slash commands

A full slash-command engine for `.chat` buffers. The scope includes:

- **Registration** — a registry for built-in and user-defined commands, with each command declaring its accepted arguments and behaviour.
- **Parsing** — slash commands recognised at the AST level so they participate in syntax highlighting, diagnostics, and completion.
- **Preprocessing** — commands fire as preprocessor rewriters before the request is sent, allowing them to modify the document (inject system prompts, toggle config, expand macros).
- **Namespacing** — commands are namespaced (e.g., `/flemma:thinking`) with automatic short-form resolution when unambiguous (just `/thinking`), so community plugins can define their own top-level commands without collisions.
- **Config integration** — commands that map to config values (like `/thinking off` or `/thinking budget=2048`) are validated and coerced through the existing config schema, giving type-checked inline configuration for free.
- **Personality wiring** — activating a personality via slash command (e.g., `/coding-assistant language=php`), with promotion from `@You` to `@System` so users don't have to manage role placement manually.
- **Completion** — a completion source that triggers on `/` at line start and enumerates available commands and their arguments.

### User-overridable buffer messages

Flemma injects short text fragments into the conversation buffer — tool result placeholders, abort notices, job status text. These messages now live as flat keyed entries in gettext PO catalogues — `po/flemma-harness.po` for model-facing strings, `po/flemma.po` for user-facing UI strings — behind the `flemma.messages` module, and render through the templating engine.

What's still missing is the user-facing override surface: letting users merge a supplemental `.po` file over the base catalogue to replace individual entries by key. This would allow customising the text the model sees when a tool is denied, a request is aborted, or a background job is lost — without forking the plugin.

---

This roadmap reflects current intentions and is subject to change. Follow the [changelog](CHANGELOG.md) for what has shipped.
