# Flemma – Messages

Externalized text fragments that Flemma injects into the conversation buffer. Loaded by `flemma.messages` and rendered through the templating engine, so templates support full `{{ expression }}` syntax.

## When to externalize

- **MUST:** User-facing messages injected into the conversation (tool result placeholders, status text, abort notices). These are visible to the user and intended to be customizable in the future.
- **MAY:** LLM-internal strings (tool schema descriptions, parameter descriptions). These are opaque to the user and sent only to the provider API. Externalizing is optional and only warranted if the string is unwieldy inline.

## Naming convention

```
{subject}-{state}[--{modifier}].chat
```

- **subject** — the entity the message is about (`job`, `tool`, `request`)
- **state** — what happened or is happening (`executing`, `denied`, `rejected`, `aborted`)
- **modifier** — optional, BEM-style `--` prefix, distinguishes variants of the same subject-state (`--tracked`, `--untracked`)

Separators are **dashes**, not underscores — these are data files, not Lua modules.

### Examples

```
job-executing--tracked.chat      # background job placeholder when job ID is available
job-executing--untracked.chat    # background job placeholder without job tracking
tool-denied.chat                 # tool denied by policy
tool-rejected.chat               # tool rejected by user
request-aborted.chat             # response interrupted by user
```

### Usage in code

```lua
local messages = require("flemma.messages")

messages.render("job-executing--tracked", { job_id = job_id })
messages.render("tool-denied", {})
```

## Adding a new message

1. Create a `.chat` file following the naming convention above.
2. Use `{{ variable }}` for interpolation — variables are passed as the second argument to `messages.render()`.
3. Update the call site to use `messages.render("name", variables)` instead of an inline string.
