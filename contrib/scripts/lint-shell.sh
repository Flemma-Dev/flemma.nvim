#!/usr/bin/env bash
# contrib/scripts/lint-shell.sh
# Lint and format-check every shell script tracked in the repo: shellcheck
# (correctness and style) plus `shfmt -d` (formatting must match the treefmt
# config — the same -i 2 -ci `make format` applies). Scope is the tracked
# `*.sh` files minus tests/fixtures, mirroring treefmt's excludes; vendored
# third-party checkouts are excluded for free because they aren't tracked.
# `make format` writes the shfmt formatting — this gate verifies it stuck and
# adds shellcheck on top.
# Exits 0 if every script is clean, 1 otherwise.
set -euo pipefail

for tool in shellcheck shfmt; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: $tool not found — run from within the 'nix develop' shell." >&2
    exit 1
  fi
done

mapfile -t files < <(git ls-files '*.sh' | grep -v '^tests/fixtures/')
if [ "${#files[@]}" -eq 0 ]; then
  echo "lint-shell: OK (no shell scripts)"
  exit 0
fi

status=0
shellcheck "${files[@]}" || status=1
shfmt -d -i 2 -ci "${files[@]}" || status=1

if [ "$status" -ne 0 ]; then
  echo ""
  echo "ERROR: shell scripts failed shellcheck and/or shfmt."
  echo "Run 'make format' to fix formatting; address shellcheck findings by hand."
  exit 1
fi

echo "lint-shell: OK (${#files[@]} scripts pass shellcheck + shfmt)"
exit 0
