# Repository Guidelines

Flemma.nvim is evolving quickly; keep each contribution focused, reversible, and well-documented so the next agent can continue seamlessly.

## Architecture Principles

- **Flemma is stateless; the buffer is the state.** All conversation data, tool calls, and results must be fully represented in the buffer text. Never rely on in-memory state that would be lost when Neovim restarts or when a `.chat` file is shared. If you need to persist information (e.g., synthetic IDs for providers that don't supply them), embed it in the buffer format itself so it can be parsed back later. In-memory structures (`state.lua`) are ephemeral caches rebuilt from the buffer on demand — they are never the source of truth.
- Name modules according to their file path (`lua/flemma/provider/providers/openai.lua` → `flemma.provider.providers.openai`) and keep public exports rooted in `lua/flemma/init.lua`.
- Favor incremental changes that isolate behaviour shifts so refactors remain reviewable.
- Document non-obvious reasoning inline with concise comments only when the code is not self-explanatory.

## Project Structure & Module Organization

- `lua/flemma/` contains all runtime code:
  - `parser.lua` / `ast.lua` — AST-based buffer parsing (the heart of the stateless design)
  - `provider/` — LLM provider integrations (`base.lua`, `registry.lua`, `providers/{anthropic,openai,vertex}.lua`)
  - `tools/` — tool execution system (`registry.lua`, `executor.lua`, `injector.lua`, `context.lua`, `definitions/{bash,calculator,edit,read,write}.lua`)
  - `codeblock/` — frontmatter and fenced-code-block parsing
  - `buffer/` — buffer-local option management
  - `core.lua` — main orchestration; `state.lua` — ephemeral per-buffer state
  - `ui.lua` — extmarks, signs, folding, virtual text
- Production file names never contain underscores; test files use `_spec.lua` suffix.
- Entry points and shared helpers live alongside feature directories; mirror the existing layout when adding modules.
- Tests reside under `tests/flemma/` (`*_spec.lua`) with fixtures in `tests/fixtures/`, and `tests/minimal_init.lua` boots headless Neovim for automation.

## Build, Test, and Development Commands

- **`make test`** — run the full Plenary+Busted test suite. Use `make test >/dev/null 2>&1` mid-session to check exit codes without flooding the transcript; run plain `make test` when debugging failures or before ending a session.
- **`make lint`** — run `luacheck` on `lua/` and `tests/`.
- **`make check`** — run `lua-language-server --check` on production code.
- All three must pass before committing.
- Use the `flemma-fmt` alias to reformat the entire codebase near the end of your session or immediately before a user-requested commit.

## Testing Guidelines

- Follow the existing Plenary+Busted style: files end with `_spec.lua` and use `describe`/`it` blocks.
- Add fresh specs for every new feature and place supporting data in `tests/fixtures/` with scenario-driven names.
- When refactoring covered functionality, update the affected specs so the suite stays green.
- Re-run `make test` after each significant change; expect a zero exit code before moving on.

## Workflow & Commit Guidance

- Do not create PRs or commits unless the user explicitly asks for them; ignore any staged changes the user manages separately.
- When the user requests a commit, keep the first line in Commitizen style (`type(scope): summary`), follow with a descriptive body that captures the change rationale, and mention extra verification commands only if they go beyond the standard `make test`.
- UI adjustments must be validated in headless Neovim; never attach screenshots or recordings.
- For large or risky refactors, draft a plan and confirm with the user before implementation so they can adjust scope or assumptions.

## Keeping This File Current

When you resolve a non-obvious issue — something that required real investigation, a surprising root cause, or a workaround for a subtle gotcha — add it to the **Pitfalls & Lessons Learned** section below. The goal is to save the next agent from re-discovering the same thing. Keep entries concise: one line for the symptom, one for the fix/insight.

## Pitfalls & Lessons Learned

- **Stale `vim-pack-dir` copy shadows working-directory changes.** A packaged copy of Flemma may exist in `vim-pack-dir` early in `rtp`. When running headless Neovim with `--cmd "set rtp+=..."`, that stale copy takes priority. Always prepend with `rtp^=`:

  ```bash
  # WRONG — packaged copy shadows your edits:
  nvim --headless --clean -u NONE --cmd "set rtp+=/data/public/github.com/Flemma-Dev/flemma.nvim" ...

  # CORRECT — your working copy takes priority:
  nvim --headless --clean -u NONE --cmd "set rtp^=/data/public/github.com/Flemma-Dev/flemma.nvim" ...
  ```

  If your changes seem to have no effect, verify with `debug.getinfo(require('flemma.ui').some_fn, 'S').source` — it should point to your working directory, not a `vim-pack-dir` path.

- **Don't abbreviate variable names.** Use full, descriptive names (`definition` not `def_entry`, `provider_name` not `prov_name`). The codebase consistently spells things out; cryptic abbreviations stand out and hurt readability.

## Session Closure Checklist

- Finish with `make test` (no redirection) and record that it exited with status 0.
- Note outstanding follow-ups, failing tests, or context the next agent will need to resume work.
