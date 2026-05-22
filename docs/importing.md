# Importing from Claude Workbench

Flemma can turn Claude Workbench exports into ready-to-send `.chat` buffers.

**Quick steps:** Export the TypeScript snippet in Claude Workbench, paste it into Neovim, then run `:Flemma import`.

---

## Before you start

- `:Flemma import` delegates to the current provider. Keep Anthropic active (`:Flemma switch anthropic`) so the importer knows how to interpret the snippet.
- Use an empty scratch buffer – `Flemma import` overwrites the entire buffer with the converted chat.

## Export from Claude Workbench

1. Navigate to <https://console.anthropic.com/workbench> and open the saved prompt you want to migrate.
2. Click **Get code** in the top-right corner. The importer looks for any `anthropic.messages.create({ ... })` call; either the JavaScript or TypeScript variant works — the call body is the same.
3. Press **Copy code**; Claude Workbench copies the whole example (including the `import Anthropic from "@anthropic-ai/sdk"` header).

## Convert inside Neovim

1. In Neovim, paste the snippet into a new buffer (or delete any existing text first).
2. Run `:Flemma import`. The command:
   - Scans the buffer for `anthropic.messages.create(...)`.
   - Normalises the JavaScript object syntax and decodes it as JSON.
   - Emits a system message (if present) and rewrites every Workbench message as `@You:` / `@Assistant:` lines.
   - Switches the buffer's filetype to `chat` so folds, highlights, and keymaps activate immediately.
   - Writes the buffer to disk if `editing.auto_write = true` is set — so if you pasted into a named file, the converted contents are persisted right away.

> [!NOTE]
> The importer is lossy. Only `model`/`max_tokens`/`temperature` and the text bodies of user/assistant turns are preserved. Tool uses, tool results, image content blocks, and any non-text segments in the original Workbench export are silently dropped. If your prompt depends on those, you'll need to add them back by hand.

## Troubleshooting

- If the snippet does not contain an `anthropic.messages.create` call, the importer aborts with "No Anthropic API call found".
- JSON decoding errors write both the original snippet and the cleaned JSON to `flemma_import_debug.log` under the temporary directory chosen by `os.tmpname()` (e.g. `/tmp/` on Linux, `/var/folders/.../T/` on macOS). Open that file to spot mismatched brackets or truncated copies.
- Nothing happens? Confirm Anthropic is the active provider – other providers currently do not ship an importer.
