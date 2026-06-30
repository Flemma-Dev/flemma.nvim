# Flemma as a Harness

Flemma is not just a chat interface — it is a **harness** that mediates between a human user, a language model, and the local environment. Every outgoing request is a product of _(conversation, environment)_: the `.chat` buffer determines what was said; the harness determines what the model can see, what it can do, and how its actions are gated.

This document maps the harness surfaces across three axes. Each item is a brief orientation — follow the deep link for the full reference.

---

## Model-facing surface

What the harness injects into or exposes to the LLM at request time.

- **`flemma.background` and `flemma.save_to`** — harness parameters auto-injected into tool schemas. `flemma.background` lets the model move a tool execution to background; `flemma.save_to` lets it redirect output to a file instead of consuming context window. See [Harness parameters](tools.md#harness-parameters) in tools.md.

- **`flemma.jobs.status`** — a harness-only tool (not a user tool) that lets the model poll the state of background jobs. The harness cross-checks the model's query against the buffer AST so the model cannot invent job IDs. See [`flemma.jobs.status` tool](tools.md#flemmajobsstatus-tool) in tools.md.

- **Tool/job status suffixes** — `(pending)`, `(approved)`, `(denied)`, `(rejected)`, `(aborted)`, `(error)` on `**Tool Result:**` and `**Job Result:**` headers. These are the harness's structured feedback to the model about what happened to each tool call. See [Tool status suffix](tools.md#tool-status-suffix) in tools.md.

- **Tool-result placeholders** — when a tool is blocked or deferred, the harness injects a placeholder with a status suffix so the model sees structured feedback rather than silence. See [The three-phase cycle](tools.md#the-three-phase-cycle) in tools.md.

- **Output truncation** — large tool outputs are automatically truncated to protect the context window. The full output is saved to the [tool result store](tools.md#tool-result-store), and the model is told where to find it. The model can also pre-emptively redirect output via `flemma.save_to`. See [Tool result store](tools.md#tool-result-store) in tools.md.

- **Strict-schema rewriting** — for providers that require strict JSON schemas, the harness rewrites tool schemas to make harness parameters nullable and appends them to `required`, ensuring the model always includes them. See [Strict mode for tool schemas](tools.md#strict-mode-for-tool-schemas) in tools.md.

---

## Environment-shaping surface

The "environment" half of _(conversation, environment)_ — what the harness assembles around the conversation before the request leaves the editor.

- **Personalities** — dynamic system prompt generators that assemble identity, a capability-gated tool listing, behavioral guidelines, and ambient context (`cwd`, `git_branch`, `date`, `time`) into the model's system prompt. The most direct way the harness augments what the model knows. See [personalities.md](personalities.md).

- **Project-context discovery** — the personality scans for `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, and similar files and includes them in the system prompt. This is automatic environment enrichment — the user doesn't reference these files; the harness finds and injects them. See [Project Context Discovery](personalities.md#project-context-discovery) in personalities.md.

- **Template expressions and `include()`** — `{{ expressions }}` and `{% code %}` blocks in `@System` and `@You` messages let the harness evaluate Lua at send time. `include("urn:flemma:personality:...")` dispatches through the personality registry. These shape what the model sees before the request leaves the editor. See [templates.md](templates.md).

- **Prompt-caching determinism** — the harness actively engineers for byte-identical request prefixes: tools sorted alphabetically, JSON keys canonicalized, date/time cached per buffer. A model-invisible economics optimization that follows from the _(conversation, environment)_ principle — the environment must be deterministic. See [prompt-caching.md](prompt-caching.md).

---

## Gating and coordination surface

How the harness controls what the model may do and when.

- **Approval resolver chain** — a priority-ordered chain of resolvers that decides whether each tool call is auto-approved, requires human review, or is denied outright. The chain is the harness's primary gating mechanism. See [Tool approval](tools.md#tool-approval) and [Approval resolvers](tools.md#approval-resolvers) in tools.md.

- **Capability tags** — tool definitions can declare tags like `disables_background`, `disables_save_to`, `auto_approves_if_sandboxed`, and `emits_template` that modify how the harness treats them. Tags are the harness's per-tool policy knobs. See [Capability tags](tools.md#capability-tags) in tools.md.

- **Sandbox** — the harness's filesystem boundary. Shell commands run inside a constrained environment (Bubblewrap on Linux) with read-only root and explicit write allowlists. The sandbox also enables capability-gated auto-approval (`auto_approves_if_sandboxed`) and backs the durable tool result store (`urn:flemma:store`). See [sandbox.md](sandbox.md).

- **Background-job lifecycle** — tools can run asynchronously without blocking the conversation. The harness assigns job IDs, queues completions, and drains results at conversation idle. Combined with autopilot, this creates a fully autonomous agent loop. See [Background jobs](tools.md#background-jobs) in tools.md and [Autopilot](configuration.md#autopilot) in configuration.md.

- **Output truncation as context-budget management** — the harness truncates oversized tool output and persists the full result to a durable store next to the `.chat` file. This is active context-window management, not just formatting. See [Tool result store](tools.md#tool-result-store) in tools.md.
