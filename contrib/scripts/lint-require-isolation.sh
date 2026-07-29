#!/usr/bin/env bash
# Require-isolation gate: every module under lua/ must be require()-able in a
# bare Neovim (no user config, no packages, no flemma.setup()/config.init()),
# mirroring nixpkgs' nvimRequireCheck.
#
# A module that self-registers into global state as a require()-time side effect
# — and asserts that init has already run — crashes a bare `require`. That breaks
# nixpkgs packaging and any tool that loads modules in isolation, yet slips past
# the normal test suite (which always establishes config via setup() first). This
# gate closes that gap. The skip-list of modules that legitimately extend an
# external plugin lives in contrib/scripts/require-isolation-check.lua.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v nvim >/dev/null 2>&1; then
  echo "lint-require-isolation: ERROR — nvim not found on PATH" >&2
  exit 1
fi

# -u NONE + empty packpath → only this checkout's lua/ is reachable; rtp^= keeps
# it ahead of any stale copy (per the headless-runtime convention). Wrapped in
# timeout so an unexpected prompt can never hang the gate.
timeout 120 nvim --headless -u NONE -i NONE \
  --cmd "set packpath=" \
  --cmd "set rtp^=${root_dir}" \
  -l "${root_dir}/contrib/scripts/require-isolation-check.lua"
