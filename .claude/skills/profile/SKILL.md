---
name: profile
description: Use when asked to profile Flemma performance, compare keystroke latency between branches, or run the profiling harness. Trigger on "profile", "perf", "benchmark", "keystroke latency", or "InsertCharPre".
---

# Profile: main vs HEAD

Compare per-keystroke performance between `main` (latest stable) and the current working tree using `contrib/profile/run.sh`.

## Prerequisites

- **tmux session must be active** — the harness drives edits via `tmux send-keys`
- The tmux socket is typically outside the sandbox allowlist — commands that touch tmux need sandbox bypass
- Each run takes ~40 seconds (typing simulation + data collection)

## Procedure

Run these steps sequentially. All `bash` commands that touch tmux need `dangerouslyDisableSandbox: true`.

### 1. Verify tmux

```bash
tmux has-session 2>&1 && echo "ready" || echo "no tmux"
```

If no tmux, stop and tell the user to start a tmux session first.

### 2. Ensure the fixture exists

```bash
ls contrib/profile/fixture.chat 2>/dev/null && echo "exists" || echo "missing"
```

If missing, generate it:

```bash
nvim --headless --noplugin -u NONE --cmd 'set rtp^=.' -l contrib/profile/generate-fixture.lua
```

### 3. Create a worktree for `main`

```bash
git worktree remove --force $TMPDIR/flemma-profile-main 2>&1; git worktree add $TMPDIR/flemma-profile-main main 2>&1
```

### 4. Replace harness in worktree with HEAD's copy

**Always purge and replace** — even if `main` already has `contrib/profile/`, its harness may be outdated. The HEAD version of the harness is the single source of truth for instrumentation. Using `main`'s own harness would mean each branch is measured with different instrumentation code, invalidating the comparison.

```bash
rm -rf $TMPDIR/flemma-profile-main/contrib/profile
mkdir -p $TMPDIR/flemma-profile-main/contrib/profile
cp contrib/profile/{run.sh,init.lua,instrument.lua,generate-fixture.lua,GUIDE.md} \
   $TMPDIR/flemma-profile-main/contrib/profile/
cp contrib/profile/fixture.chat $TMPDIR/flemma-profile-main/contrib/profile/
```

Both runs must use **identical instrumentation** (same `instrument.lua`, same `run.sh`) and **identical input** (same `fixture.chat`) for a fair comparison. Only the Flemma runtime code differs.

### 5. Run profiling on `main`

```bash
cd $TMPDIR/flemma-profile-main && bash contrib/profile/run.sh 2>&1
```

Timeout: 300000ms. Capture the full output.

### 6. Run profiling on HEAD

Run from the primary working directory (the repo root where the conversation started):

```bash
bash contrib/profile/run.sh 2>&1
```

Timeout: 300000ms. Capture the full output.

### 7. Clean up

```bash
git worktree remove --force $TMPDIR/flemma-profile-main 2>&1
```

### 8. Present results

Extract `InsertCharPre` rows from both runs and build a comparison table:

```
| Branch    | Avg ms/key | Max ms | Baseline (md) |
|-----------|-----------|--------|---------------|
| main      | X.XXX     | XX.XX  | X.XXX         |
| HEAD      | X.XXX     | XX.XX  | X.XXX         |
```

Below the headline table, include:

- **Function timings** side-by-side (parser, bridge.update_ui, folding — from the `chat-flemma` variant of each run)
- **Parser cache hit rate** for each (`parse_lines` calls / `get_parsed_document` calls`)
- **Notable differences** in the jit.p profiles or autocmd event distribution
- A brief interpretation: where time moved, what improved/regressed, and whether the delta is within noise

If the user passed arguments to `/profile`, treat them as a custom input file path for the harness (both runs use the same file).

## Interpreting Results

See `contrib/profile/GUIDE.md` for the full methodology — event timing semantics, function timing interpretation, jit.p reading, and isolation techniques. That document is the reference for diagnosing specific bottlenecks once the comparison identifies a regression.
