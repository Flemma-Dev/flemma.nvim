#!/usr/bin/env bash
# contrib/scripts/run-flemma-specs.sh
# Run every tests/flemma/**/*_spec.lua in its own headless child nvim (like
# :PlenaryBustedDirectory) but capped at $JOBS concurrent processes, so the
# suite doesn't oversubscribe the CPU and lock up the machine. Plenary's own
# directory runner starts one child per file with no concurrency limit; on a
# machine with N cores that means ~(file count) processes at once.
#
# Usage: run-flemma-specs.sh <nvim_bin> <vimruntime> <plenary_path>
# Env:
#   PROJECT_ROOT   (required) repo root; prepended to rtp by tests/minimal_init.lua
#   JOBS           max concurrent child nvims (default: nproc)
#   SPEC_TIMEOUT   per-file timeout in seconds (default: 120)
# Exits 0 if all spec files pass, non-zero if any fail (or time out).
set -uo pipefail

nvim_bin=$1
vimruntime=$2
plenary_path=$3

: "${PROJECT_ROOT:?PROJECT_ROOT must be set (run via 'make qa' from the nix develop shell)}"
jobs=${JOBS:-$(nproc)}
spec_timeout=${SPEC_TIMEOUT:-120}

export VIMRUNTIME="$vimruntime"
export PLENARY_TEST_TIMEOUT=$((spec_timeout * 1000))

# One child nvim per spec file, mirroring plenary's own child invocation
# (plenary/test_harness.lua): put plenary on the runtimepath, load
# tests/minimal_init.lua, then run the file via plenary.busted (which exits
# 0cq on pass / 1cq on fail). `xargs -P` caps how many run concurrently; it
# returns 123 if any child exits non-zero, which propagates as the gate result.
find "$PROJECT_ROOT/tests/flemma" -type f -name '*_spec.lua' -print0 |
  xargs -0 -P "$jobs" -I{} \
    timeout "$spec_timeout" "$nvim_bin" --headless \
    -c "set rtp+=.,$plenary_path | runtime plugin/plenary.vim" \
    --noplugin -u tests/minimal_init.lua \
    -c "lua require('plenary.busted').run('{}')"

exit "${PIPESTATUS[1]}"
