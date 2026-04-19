# Template System and Automation

Flemma's prompt pipeline runs through three stages: parse, evaluate, and send. Errors at any stage surface via diagnostics before the request leaves your editor.

> For an overview of the `.chat` buffer format (role markers, frontmatter placement, thinking blocks), see the [Understanding `.chat` Buffers](../README.md#understanding-chat-buffers) section in the README.

## Frontmatter

Place a fenced block on the very first line of the buffer (` ```lua ` or ` ```json `). The block returns a table of variables that become available in `{{ expressions }}` throughout the file.

````lua
```lua
recipient = "QA team"
notes = [[
- Verify presets list before providers.
- Check spinner no longer triggers spell checking.
- Confirm logging commands live under :Flemma logging:*.
]]
```
````

Errors (syntax problems, unknown parser) block the request and show in a detailed notification with filename and line number.

### Passive evaluation

Frontmatter is re-evaluated automatically whenever the buffer content changes — on `InsertLeave`, `TextChanged`, and `BufEnter`. This means integrations like lualine see up-to-date config values (model, thinking level, etc.) as you edit, without waiting for a send.

If a frontmatter edit introduces an error, the last successful parse is preserved — you can experiment freely without breaking your session mid-edit. Errors surface as diagnostics on the next `:Flemma send` or in the `:Flemma status` window.

Passive evaluation is skipped while a request is in flight (the active send owns the frontmatter state).

### Custom frontmatter parsers

Lua and JSON parsers ship with Flemma. You can register additional parsers (e.g., YAML) with:

```lua
require("flemma.codeblock.parsers").register("yaml", function(code, context)
  -- `code` is the raw fenced block content (string)
  -- `context` is an optional table with __filename, __dirname, and user variables
  -- Must return a table of variables; errors are caught and reported as diagnostics
  return require("flemma.utilities.json").decode(vim.fn.system("yq -o json", code))
end)
```

Parsers are lazy-loaded on first use and cached for the session. See `lua/flemma/codeblock/parsers/` for the built-in implementations.

### Per-buffer overrides with `flemma.opt`

Lua frontmatter has access to a special `flemma.opt` proxy that lets you override configuration for the current buffer without touching your global setup. Changes made through `flemma.opt` only affect the request sent from that buffer.

**Parameter overrides:**

````lua
```lua
flemma.opt.thinking = "medium"
flemma.opt.temperature = 0.3
flemma.opt.max_tokens = 8000
flemma.opt.cache_retention = "none"
```
````

**Provider-specific overrides:**

````lua
```lua
flemma.opt.anthropic.thinking_budget = 20000
flemma.opt.openai.reasoning = "high"
flemma.opt.vertex.thinking_budget = 4096
```
````

**Tool selection:** The `flemma.opt.tools` proxy supports list operations and operator overloads for concise tool management:

````lua
```lua
-- Replace the tool list entirely
flemma.opt.tools:set({ "bash", "read" })

-- Add or remove individual tools
flemma.opt.tools:append("grep")
flemma.opt.tools:remove("write")
flemma.opt.tools:prepend("bash")

-- Operator shorthand: + (append), - (remove), ^ (prepend)
flemma.opt.tools = flemma.opt.tools + "grep" - "write" ^ "bash"
```
````

**Per-buffer auto-approval:** Override the global approval policy for this buffer. Presets, tool names, and ListOption operations all work here:

````lua
```lua
-- Preset form: read-only access for this buffer
flemma.opt.tools.auto_approve = { "$readonly" }

-- List form: auto-approve these tools, require approval for the rest
flemma.opt.tools.auto_approve = { "bash", "read" }

-- ListOption operations: modify the default policy incrementally
flemma.opt.tools.auto_approve = { "$standard" }
flemma.opt.tools.auto_approve:remove("write")       -- exclude write from $standard
flemma.opt.tools.auto_approve:append("bash")        -- add bash on top

-- Operator shorthand: + (append), - (remove)
flemma.opt.tools.auto_approve = flemma.opt.tools.auto_approve + "bash" - "write"

-- Function form: full control over the decision
flemma.opt.tools.auto_approve = function(tool_name, input, context)
  if tool_name == "grep" then return true end
  return nil  -- defer to global config
end
```
````

Removing a tool that lives inside a preset (e.g., `"write"` from `{ "$standard" }`) creates an exclusion – the tool is filtered out when the preset expands, without affecting other tools in the preset.

**Per-buffer autopilot:** Disable (or force-enable) autopilot for a specific buffer:

````lua
```lua
flemma.opt.tools.autopilot = false  -- manual three-phase Ctrl-] for this buffer
```
````

If you misspell a tool name, Flemma suggests the closest match: `"flemma.opt: unknown value 'raed'. Did you mean 'read'?"`.

Only options you actually touch appear in the resolved overrides – unmodified settings fall through to your global config. See [docs/tools.md](tools.md) for more on tool approval and the resolver API.

### JSON frontmatter with config operators

JSON frontmatter blocks can override Flemma configuration through a `flemma` key. Plain values set the option directly; for list-type options (tools, auto_approve), MongoDB-style operators give precise control over how the list is modified:

| Operator   | Effect                                  | Example                                 |
| ---------- | --------------------------------------- | --------------------------------------- |
| `$set`     | Replace the value (same as no operator) | `"tools": { "$set": ["bash", "read"] }` |
| `$append`  | Add item(s) to a list                   | `"tools": { "$append": "bash" }`        |
| `$remove`  | Remove item(s) from a list              | `"tools": { "$remove": "write" }`       |
| `$prepend` | Prepend item(s) to a list               | `"tools": { "$prepend": "bash" }`       |

Operators accept both single values and arrays: `"$append": ["bash", "grep"]`.

````json
```json
{
  "flemma": {
    "provider": "openai",
    "model": "gpt-5",
    "parameters": {
      "thinking": "medium",
      "temperature": 0.3
    },
    "tools": {
      "$append": "bash",
      "auto_approve": {
        "$append": "bash",
        "$remove": "write"
      }
    }
  },
  "recipient": "QA team"
}
```
````

Regular (non-`$`) keys navigate into child objects: `"parameters": { "thinking": "medium" }` descends into the `parameters` node and sets `thinking` to `"medium"` without touching other parameters. Operators and child keys can coexist on the same node — in the example above, `"tools"` both appends `"bash"` to the tool list and navigates into `auto_approve` for further operations.

Plain values and arrays without operators default to `$set`. The `flemma` key is reserved for configuration; all other top-level keys become template variables available in `{{ expressions }}`, just like Lua frontmatter.

> [!NOTE]
> JSON frontmatter operators are the equivalent of Lua frontmatter's `flemma.opt` proxy. Both write to the same per-buffer config layer. Use whichever syntax you prefer — Lua frontmatter for full programmatic control, JSON frontmatter for quick declarative overrides.

Frontmatter config values are validated against the schema. Unknown keys produce an error; misspelled tool names get a "did you mean?" suggestion.

## Inline expressions

Use `{{ expression }}` inside any `@System:` or `@You:` message. Expressions run in an environment built from registered populators that includes standard Lua libraries, select Neovim APIs, and variables from frontmatter. The built-in populators are defined in `lua/flemma/templating/builtins/`.

Key built-ins:

- `__filename` – the absolute path to the current `.chat` file.
- `__dirname` – the directory containing the current file.
- `include()` – inline another file (see below).
- `string`, `table`, `math`, `utf8` – standard Lua libraries (safe subsets).
- `os.date`, `os.time`, `os.clock`, `os.difftime` – read-only time functions (no `execute`, `exit`, `getenv`, etc.).

```markdown
@You:
Draft a short update for {{recipient}} covering:
{{notes}}
```

### Evaluation rules

- Expressions without an explicit `return` are auto-wrapped: `{{ 1 + 1 }}` becomes `return 1 + 1` internally.
- `nil` results produce no output (empty string) — but note that **accessing an undefined variable is an error**, not nil (see [strict variable checking](#strict-variable-checking) below). Only variables that are explicitly defined with a nil value produce no output.
- Tables are automatically JSON-encoded via `flemma.utilities.json.encode()`.
- Errors (including undefined variable access) are downgraded to warnings. The request still sends, and the literal `{{ expression }}` remains in the prompt so you can see what failed.

## Template code blocks

Use `{% code %}` to embed Lua statements directly in your messages. Unlike `{{ expressions }}`, which output a value, code blocks execute statements -- control flow, variable assignment, loops -- without emitting output themselves. Use `print()` or `__emit()` inside code blocks when you need to output text.

```markdown
@System:
{% if task == "review" then %}
You are a code reviewer. Be concise and direct.
{% else %}
You are a helpful assistant.
{% end %}
```

### Control flow

Standard Lua `if`/`elseif`/`else`/`end` and `for`/`while`/`repeat` loops all work. Each `{% %}` block is a fragment of the same Lua chunk, so you can open a block in one tag and close it in another:

```markdown
@You:
{% for item, loop in each(items) do %}

- Item {{loop.index}}: {{item}}
  {% end %}
```

### Variable assignment

Assign variables in code blocks and reference them in later expressions or code blocks within the same message:

```markdown
@You:
{% label = string.upper(project) %}
Project: {{label}}
```

Use `local` when the variable is only needed within the current message. Without `local`, the variable is set on the shared environment and accessible from subsequent messages:

```markdown
@System:
{% mode = "strict" %}

@You:
Mode is {{mode}}
```

### Strict variable checking

The template environment errors when you access a variable that was never defined. This catches typos early — `{{ mane }}` when you meant `{{ name }}` will produce a diagnostic instead of silently inserting nothing.

The checking applies to all variable access: `{{ mane }}`, `{{ string.upper(mane) }}`, and `{% if mane then %}` all error if `mane` was never defined. Variables are considered "defined" if they were set by frontmatter, passed as `include()` arguments, or provided by a populator (the standard library, iterators, etc.).

In `{{ expressions }}`, undefined variable errors degrade gracefully like any other expression error — the raw `{{ mane }}` text is preserved in the output and a warning diagnostic is shown. In `{% code %}` blocks, undefined variable errors are fatal (just like any other code block error).

### Error behaviour

Code block errors are **fatal** -- they block the request with a diagnostic showing the file and line number. This is different from `{{ expressions }}`, which degrade gracefully by emitting the raw expression text and sending the request with a warning. The distinction is intentional: a broken expression produces ugly but usable output, while a broken control flow structure (e.g., an `if` without `end`) would produce nonsensical output.

## Whitespace trimming

By default, the literal text between template tags is preserved exactly -- including the newlines around `{% %}` and `{{ }}` tags. This often produces unwanted blank lines in the output. Trimming modifiers strip whitespace adjacent to a tag:

- `{%-` or `{{-` trims whitespace **before** the tag (back to and including the nearest newline).
- `-%}` or `-}}` trims whitespace **after** the tag (up to and including the nearest newline).

Combine both for fully clean output.

### Before and after

Without trimming:

```markdown
@System:
{% if verbose then %}
Include full details.
{% end %}
```

Output (when `verbose` is true):

```
\n
Include full details.
\n
```

With trimming:

```markdown
@System:
{%- if verbose then -%}
Include full details.
{%- end -%}
```

Output:

```
Include full details.
```

Trimming works on `{{ }}` expressions too. `{{- value -}}` strips surrounding whitespace, useful when an expression sits on its own line but the output should join adjacent text.

## `include()` helper

Call `include("relative/or/absolute/path")` inside frontmatter or an expression to inline another template fragment. Includes support two modes:

**Text mode** (default) -- the included file is parsed for `{{ }}` expressions, `{% %}` code blocks, and `@./` file references, which are evaluated recursively. The result is inlined as text. Each included file gets its own `__filename` and `__dirname`, isolated from the parent's variables -- the parent's frontmatter variables are not inherited.

```markdown
@System:
{{ include("system-prompt.md") }}
```

**Binary mode** -- the file is read as raw bytes and attached as a structured content part (image, PDF, etc.), just like `@./path`. Use the `symbols.BINARY` and `symbols.MIME` keys to control include mode:

```lua
-- In frontmatter:
screenshot = include('./latest.png', { [symbols.BINARY] = true })
```

```markdown
@You:
What do you see? {{ screenshot }}
```

The `symbols.BINARY` flag and an optional `symbols.MIME` override are passed as symbol keys in the second argument:

```lua
include('./data.bin', { [symbols.BINARY] = true, [symbols.MIME] = 'text/csv' })
```

`symbols.BINARY` and `symbols.MIME` are opaque table references (not strings), so they never collide with user-defined string keys. All string keys in the second argument are template variables passed to the included file. The `symbols` table is a reserved environment key and must not be overwritten by frontmatter variables.

### Argument passing

Pass variables to included files through the second argument. Keys become local variables in the child environment:

```markdown
@System:
{{ include("greeting.md", { name = "Alice", role = "reviewer" }) }}
```

Inside `greeting.md`:

```markdown
Hello {{name}}, you are acting as a {{role}}.
```

Included files have full template support at any nesting depth -- `{% %}` code blocks, `{{ }}` expressions, and nested `include()` calls all work. The child environment is isolated: it receives only the variables you pass (plus `__filename` and `__dirname`), not the parent's frontmatter variables.

### Safety guards

- Relative paths resolve against the directory of the file that called `include()`.
- Circular includes are detected via an immutable stack threaded through each call. The error message includes the full include chain: `"Circular include for 'c.md' (requested by 'b.md'). Include stack: a.chat -> b.md -> c.md"`.
- Missing files or read errors raise diagnostics that block the request.
- Binary includes skip circular detection since they don't recurse.

### Iterator Helpers

Flemma provides two iterator helpers for concise array iteration in templates:

**`values(t)`** — iterate over array values without the index variable:

```
{% for item in values(items) do %}
- {{ item }}
{% end %}
```

**`each(t)`** — iterate with a loop metadata context:

```
{% for item, loop in each(items) do %}
- Item {{ loop.index }} of {{ loop.length }}: {{ item }}
{% end %}
```

The `loop` table provides:

| Field    | Description                  |
| -------- | ---------------------------- |
| `index`  | 1-based position             |
| `index0` | 0-based position             |
| `first`  | `true` for the first element |
| `last`   | `true` for the last element  |
| `length` | Total number of elements     |

### Extending the Environment

The template environment is built from registered populators — functions that receive a table and populate it with globals. Flemma ships two built-in populators (`stdlib` at priority 100, `iterators` at priority 200).

Third-party populators are registered via `templating.modules` in setup:

```lua
require("flemma").setup({
  templating = {
    modules = { "my.custom.templating" },
  },
})
```

Each module returns a table with `name`, `priority`, and `populate`:

```lua
-- my/custom/templating.lua
return {
  name = "custom",
  priority = 300,
  populate = function(env)
    env.my_helper = function() return "hello" end
    env.os = nil -- remove something from an earlier populator
  end,
}
```

Populators run in priority order (lower first). Later populators can override or remove anything set by earlier ones.

## Diagnostics at a glance

Flemma groups diagnostics by type in the notification shown before sending:

- **Frontmatter errors** (blocking) – malformed code, unknown parser, include failures.
- **Expression warnings** (non-blocking) – undefined variables, runtime errors, or type errors during `{{ }}` evaluation. The original expression text is preserved in the output.
- **File reference warnings** (non-blocking) – missing files, unsupported MIME types, read errors.

All diagnostics include position information (line and column) for precise error location. If any blocking error occurs the buffer becomes modifiable again and the request is cancelled before hitting the network.

## Referencing local files

Embed local context with `@./relative/path` (or `@../up-one/path`). Flemma handles:

1. Resolving the path against the `.chat` file's directory.
2. Detecting the MIME type via the `file` CLI or the extension fallback (see `lua/flemma/mime.lua` for the full extension map).
3. Formatting the attachment in the provider-specific structure.

```markdown
@You:
Critique @./patches/fix.lua;type=text/x-lua.

@You:
OCR this screenshot @./artifacts/failure.png.

@You:
Compare these specs: @./specs/v1.pdf and @./specs/v2.pdf.
```

### Syntax details

- **Trailing punctuation** (`.`, `)`, `,`, etc.) is stripped automatically so you can write natural prose around references.
- **MIME override:** append `;type=<mime>` to force a specific MIME type, as in the Lua example above.
- **URL-encoded paths:** percent-encoded characters are decoded before file resolution. `@./my%20report.txt` resolves to `my report.txt`.

> [!TIP]
> Under the hood, `@./path` desugars to an `include()` call in binary mode. This means `@./file.png` and `{{ include('./file.png', { [symbols.BINARY] = true }) }}` are equivalent – you can use whichever reads better in context.

### Provider support matrix

| Provider  | Text files                   | Images                                     | PDFs                   | Behaviour when unsupported                             |
| --------- | ---------------------------- | ------------------------------------------ | ---------------------- | ------------------------------------------------------ |
| Anthropic | Embedded as plain text parts | Uploaded as base64 image parts             | Sent as document parts | The literal `@./path` is kept and a warning is shown.  |
| OpenAI    | Embedded as text parts       | Sent as `image_url` entries with data URLs | Sent as `file` objects | Unsupported types become plain text with a diagnostic. |
| Vertex AI | Embedded as text parts       | Sent as `inlineData`                       | Sent as `inlineData`   | Falls back to text with a warning.                     |

If a file cannot be read or the provider refuses its MIME type, Flemma warns you (including line number) and continues with the raw reference so you can adjust your prompt.
