#!/usr/bin/env bash
# scripts/lint-inline-requires.sh
# Detect inline require("flemma.*") calls that should be at the top of the file.
# Exits 0 if clean, 1 if violations found.
set -euo pipefail

# Files with intentional lazy loading (require at point of use)
# definition.lua: DISCOVER callbacks lazy-require tools/provider registries
#                 to avoid coupling the schema definition to heavy modules at load time
LAZY_LOAD_FILES="lua/flemma/commands.lua lua/flemma/config/schema/definition.lua"

violations=0

for file in $(find lua/flemma -name '*.lua' -type f | sort); do
  # Skip files with intentional lazy loading
  for lazy_file in $LAZY_LOAD_FILES; do
    if [ "$file" = "$lazy_file" ]; then
      continue 2
    fi
  done
  # Find line number of first function definition
  first_fn=$(grep -n -m1 -E '^\s*(local\s+)?function\s' "$file" || true)
  if [ -z "$first_fn" ]; then
    continue
  fi
  first_fn=$(echo "$first_fn" | cut -d: -f1)

  # Search for require("flemma. after the first function
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    line_num=$(echo "$match" | cut -d: -f1)
    content=$(echo "$match" | cut -d: -f2-)
    abs_line=$((first_fn + line_num - 1))

    # Skip vim string-context requires (inside single-quoted strings)
    if echo "$content" | grep -qE "^[^']*'[^']*require\(\"flemma\." ; then
      continue
    fi

    # Skip dynamic requires (no string literal — require(variable))
    if echo "$content" | grep -qE 'require\([^"'"'"']' ; then
      continue
    fi

    echo "  $file:$abs_line: $(echo "$content" | sed 's/^[[:space:]]*//')"
    violations=$((violations + 1))
  done < <(tail -n +"$first_fn" "$file" | grep -n 'require("flemma\.' || true)
done

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "ERROR: Found $violations inline require(\"flemma.*\") call(s)."
  echo "Move them to the top of the file, before any function definitions."
  echo "See docs/plans/2026-03-08-top-level-requires-design.md for exceptions."
  exit 1
fi

echo "lint-inline-requires: OK (no inline requires found)"
exit 0
