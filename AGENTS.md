# Repository Guidelines

Flemma.nvim is evolving quickly; keep each contribution focused, reversible, and well-documented so the next agent can continue seamlessly.

## Project Structure & Module Organization
- `lua/flemma/` contains all runtime code: `core/` manages state and buffers, `provider/` integrates external models, and `frontmatter/` handles template parsing.
- Entry points and shared helpers live alongside feature directories; mirror the existing layout when adding modules.
- Tests reside under `tests/flemma/` with fixtures in `tests/fixtures/`, and `tests/minimal_init.lua` boots headless Neovim for automation.

## Build, Test, and Development Commands
- Run `make test >/dev/null 2>&1` mid-session to check exit codes without flooding the transcript; rerun plain `make test` only when debugging failures.
- Always execute `make test` (without redirection) after refactors and before ending a session to confirm the suite passes.
- **Never** invoke `make lint`, `make check`, `luacheck`, or `lua-language-server --check`; they currently emit only false diagnostics.
- Use the `flemma-fmt` alias to reformat the entire codebase near the end of your session or immediately before a user-requested commit.

## Implementation Notes
- Name modules according to their file path (`lua/flemma/provider/openai.lua` → `flemma.provider.openai`) and keep public exports rooted in `lua/flemma/init.lua`.
- Favor incremental changes that isolate behaviour shifts so refactors remain reviewable.
- Document non-obvious reasoning inline with concise comments only when the code is not self-explanatory.

## Testing Guidelines
- Follow the existing Plenary+Busted style: files end with `_spec.lua` and use `describe`/`it` blocks.
- Add fresh specs for every new feature and place supporting data in `tests/fixtures/` with scenario-driven names.
- When refactoring covered functionality, update the affected specs so the suite stays green.
- Re-run `make test` (redirected) after each significant change; expect a zero exit code before moving on.

## Workflow & Commit Guidance
- Do not create PRs or commits unless the user explicitly asks for them; ignore any staged changes the user manages separately.
- When the user requests a commit, format the message with Commitizen conventions (`type(scope): summary`) and list the verification commands you ran.
- Always pass `--no-gpg-sign` to `git commit` in this environment because GPG cannot write its keybox.
- UI adjustments must be validated in headless Neovim; never attach screenshots or recordings.
- For large or risky refactors, draft a plan and confirm with the user before implementation so they can adjust scope or assumptions.

## Session Closure Checklist
- Finish with `make test` (no redirection) and record that it exited with status 0.
- Note outstanding follow-ups, failing tests, or context the next agent will need to resume work.
