#!/usr/bin/env bash
# Files in the send/prefetch pipeline that contain pcall() must reference
# readiness.is_suspense — otherwise a leaf-raised Suspense would be silently
# swallowed and the editor freeze the mechanism was meant to fix returns
# without an obvious cause.
set -euo pipefail

WATCHED_FILES=(
  lua/flemma/core.lua
  lua/flemma/preprocessor/init.lua
  lua/flemma/preprocessor/runner.lua
  lua/flemma/processor.lua
  lua/flemma/provider/base.lua
  lua/flemma/templating/compiler.lua
  lua/flemma/usage/prefetch.lua
  lua/flemma/commands.lua
)

violations=0
for f in "${WATCHED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "  $f: missing (was the file moved? update WATCHED_FILES)"
    violations=$((violations + 1))
    continue
  fi

  stripped=$(sed 's/--.*$//' "$f")
  has_pcall=0
  has_is_suspense=0
  echo "$stripped" | grep -qE '\bpcall\(' && has_pcall=1
  echo "$stripped" | grep -qE '\bis_suspense\b' && has_is_suspense=1

  if [ "$has_pcall" = "1" ] && [ "$has_is_suspense" = "0" ]; then
    echo "  $f: contains pcall() but no readiness.is_suspense reference"
    violations=$((violations + 1))
  fi
done

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "ERROR: $violations file(s) in the send pipeline contain pcall() without an is_suspense check."
  echo "Add 'if readiness.is_suspense(err) then error(err) end' to the pcall handler(s)"
  echo "to propagate readiness suspense to the orchestrator (core.send_to_provider)."
  echo "If this file no longer reaches a suspense-raising leaf, remove it from WATCHED_FILES."
  exit 1
fi

echo "lint-pcall-rethrow: OK (${#WATCHED_FILES[@]} file(s) checked)"
exit 0
