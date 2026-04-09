#!/usr/bin/env bash
set -euo pipefail

# sync-version.sh — Reads version from package.json and writes lua/flemma/version.lua.
# Usage: sync-version.sh [--dev]
#
# Flags:
#   --dev   Append "-dev" suffix to the version string.

cd "$(git rev-parse --show-toplevel)"

version=$(grep '"version"' package.json | head -1 | sed 's/.*"\([0-9][0-9.]*[0-9]\)".*/\1/')

if [ -z "$version" ]; then
  echo "error: could not extract version from package.json" >&2
  exit 1
fi

if [ "${1:-}" = "--dev" ]; then
  version="${version}-dev"
fi

cat > lua/flemma/version.lua << EOF
---@class flemma.Version
local M = {}

---@type string
M.VERSION = "${version}"

return M
EOF

echo "sync-version: wrote lua/flemma/version.lua → ${version}"
