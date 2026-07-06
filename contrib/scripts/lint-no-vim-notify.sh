#!/usr/bin/env bash
# contrib/scripts/lint-no-vim-notify.sh
# Detect direct vim.notify / vim.notify_once calls in production code.
# All user-facing notifications must go through flemma.notify (see lua/flemma/notify.lua).
# The structural match lives in no-vim-notify.yml (ast-grep); the two files
# allowed to call vim.notify directly are listed there as `ignores`.
# Exits 0 if clean, 1 if violations found.
set -euo pipefail

rule="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/no-vim-notify.yml"

if ! ast-grep scan --rule "${rule}" lua/flemma/; then
  echo ""
  echo "ERROR: found direct vim.notify call(s) in production code."
  echo "Use flemma.notify instead (see lua/flemma/notify.lua)."
  exit 1
fi

echo "lint-no-vim-notify: OK (no direct vim.notify calls found)"
exit 0
