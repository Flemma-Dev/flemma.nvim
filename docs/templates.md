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

### Custom frontmatter parsers

Lua and JSON parsers ship with Flemma. You can register additional parsers (e.g., YAML) with:

```lua
require("flemma.codeblock.parsers").register("yaml", function(code, context)
  -- `code` is the raw fenced block content (string)
  -- `context` is an optional table with __filename, __dirname, and user variables
  -- Must return a table of variables; errors are caught and reported as diagnostics
  return vim.fn.json_decode(vim.fn.system("yq -o json", code))
end)
```

Parsers are lazy-loaded on first use and cached for the session. See `lua/flemma/codeblock/parsers.lua` for the built-in implementations.

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
flemma.opt.tools:set({ "calculator", "read" })

-- Add or remove individual tools
flemma.opt.tools:append("bash")
flemma.opt.tools:remove("write")
flemma.opt.tools:prepend("calculator")

-- Operator shorthand: + (append), - (remove), ^ (prepend)
flemma.opt.tools = flemma.opt.tools + "bash" - "write" ^ "calculator"
```
````

**Per-buffer auto-approval:** Override the global approval policy for this buffer:

````lua
```lua
-- List form: auto-approve these tools, require approval for the rest
flemma.opt.tools.auto_approve = { "calculator", "read" }

-- Function form: full control over the decision
flemma.opt.tools.auto_approve = function(tool_name, input, context)
  if tool_name == "calculator" then return true end
  return nil  -- defer to global config
end
```
````

If you misspell a tool name, Flemma suggests the closest match: `"flemma.opt: unknown value 'calulator'. Did you mean 'calculator'?"`.

Only options you actually touch appear in the resolved overrides — unmodified settings fall through to your global config. See [docs/tools.md](tools.md) for more on tool approval and the resolver API.

## Inline expressions

Use `{{ expression }}` inside any `@System:` or `@You:` message. Expressions run in a sandboxed environment that includes standard Lua libraries, select Neovim APIs, and variables from frontmatter. The full list of available functions is defined in `lua/flemma/eval.lua` (`create_safe_env`).

Key built-ins:

- `__filename` – the absolute path to the current `.chat` file.
- `__dirname` – the directory containing the current file.
- `include()` – inline another file (see below).

```markdown
@You: Draft a short update for {{recipient}} covering:
{{notes}}
```

### Evaluation rules

- Expressions without an explicit `return` are auto-wrapped: `{{ 1 + 1 }}` becomes `return 1 + 1` internally.
- `nil` results produce no output (empty string).
- Tables are automatically JSON-encoded via `vim.fn.json_encode()`.
- Errors are downgraded to warnings. The request still sends, and the literal `{{ expression }}` remains in the prompt so you can see what failed.

## `include()` helper

Call `include("relative/or/absolute/path")` inside frontmatter or an expression to inline another template fragment. Includes support two modes:

**Text mode** (default) – the included file is parsed for `{{ }}` expressions and `@./` file references, which are evaluated recursively. The result is inlined as text. Each included file gets its own `__filename` and `__dirname`, isolated from the parent's variables — the parent's frontmatter variables are not inherited.

```markdown
@System: {{ include("system-prompt.md") }}
```

**Binary mode** – the file is read as raw bytes and attached as a structured content part (image, PDF, etc.), just like `@./path`:

```lua
-- In frontmatter:
screenshot = include('./latest.png', { binary = true })
```

```markdown
@You: What do you see? {{ screenshot }}
```

The `binary` flag and an optional `mime` override are passed as a second argument:

```lua
include('./data.bin', { binary = true, mime = 'text/csv' })
```

### Safety guards

- Relative paths resolve against the directory of the file that called `include()`.
- Circular includes are detected via an immutable stack threaded through each call. The error message includes the full include chain: `"Circular include for 'c.md' (requested by 'b.md'). Include stack: a.chat -> b.md -> c.md"`.
- Missing files or read errors raise diagnostics that block the request.
- Binary includes skip circular detection since they don't recurse.

## Diagnostics at a glance

Flemma groups diagnostics by type in the notification shown before sending:

- **Frontmatter errors** (blocking) – malformed code, unknown parser, include failures.
- **Expression warnings** (non-blocking) – runtime errors during `{{ }}` evaluation. The original expression text is preserved in the output.
- **File reference warnings** (non-blocking) – missing files, unsupported MIME types, read errors.

All diagnostics include position information (line and column) for precise error location. If any blocking error occurs the buffer becomes modifiable again and the request is cancelled before hitting the network.

## Referencing local files

Embed local context with `@./relative/path` (or `@../up-one/path`). Flemma handles:

1. Resolving the path against the `.chat` file's directory.
2. Detecting the MIME type via the `file` CLI or the extension fallback (see `lua/flemma/mime.lua` for the full extension map).
3. Formatting the attachment in the provider-specific structure.

```markdown
@You: Critique @./patches/fix.lua;type=text/x-lua.
@You: OCR this screenshot @./artifacts/failure.png.
@You: Compare these specs: @./specs/v1.pdf and @./specs/v2.pdf.
```

### Syntax details

- **Trailing punctuation** (`.`, `)`, `,`, etc.) is stripped automatically so you can write natural prose around references.
- **MIME override:** append `;type=<mime>` to force a specific MIME type, as in the Lua example above.
- **URL-encoded paths:** percent-encoded characters are decoded before file resolution. `@./my%20report.txt` resolves to `my report.txt`.

> [!TIP]
> Under the hood, `@./path` desugars to an `include()` call in binary mode. This means `@./file.png` and `{{ include('./file.png', { binary = true }) }}` are equivalent – you can use whichever reads better in context.

### Provider support matrix

| Provider  | Text files                   | Images                                     | PDFs                   | Behaviour when unsupported                             |
| --------- | ---------------------------- | ------------------------------------------ | ---------------------- | ------------------------------------------------------ |
| Anthropic | Embedded as plain text parts | Uploaded as base64 image parts             | Sent as document parts | The literal `@./path` is kept and a warning is shown.  |
| OpenAI    | Embedded as text parts       | Sent as `image_url` entries with data URLs | Sent as `file` objects | Unsupported types become plain text with a diagnostic. |
| Vertex AI | Embedded as text parts       | Sent as `inlineData`                       | Sent as `inlineData`   | Falls back to text with a warning.                     |

If a file cannot be read or the provider refuses its MIME type, Flemma warns you (including line number) and continues with the raw reference so you can adjust your prompt.
