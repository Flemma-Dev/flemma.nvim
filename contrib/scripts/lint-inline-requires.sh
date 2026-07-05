#!/usr/bin/env bash
# contrib/scripts/lint-inline-requires.sh
# Detect inline require("flemma.*") calls that should be at the top of the file.
# Exits 0 if clean, 1 if violations found.
set -euo pipefail

# Intentional inline requires: file=module pairs where lazy loading is justified.
# Format: "file=module" — the module is the require argument without quotes.
# commands.lua:      subcommand handlers lazy-require heavy modules
# config/schema.lua: DISCOVER callbacks lazy-require tools/provider/sandbox registries
#                    to avoid coupling the schema definition to heavy modules at load time
# tools/init.lua:    facade delegates to executor inline to avoid circular dependency
#                    (executor already requires tools/init)
ALLOWED_INLINE=(
  "lua/flemma/commands.lua=*"
  "lua/flemma/config/schema.lua=*"
  "lua/flemma/tools/init.lua=flemma.tools.executor"
)

# Build a lookup function from the allowlist.
# Returns 0 (true) if the file+module pair is allowed.
is_allowed() {
  local file="$1" module="$2"
  for entry in "${ALLOWED_INLINE[@]}"; do
    local allowed_file="${entry%%=*}"
    local allowed_module="${entry#*=}"
    if [ "$file" = "$allowed_file" ]; then
      if [ "$allowed_module" = "*" ] || [ "$allowed_module" = "$module" ]; then
        return 0
      fi
    fi
  done
  return 1
}

violations=0

for file in $(find lua/flemma -name '*.lua' -type f | sort); do
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
    if echo "$content" | grep -qE "^[^']*'[^']*require\(\"flemma\."; then
      continue
    fi

    # Skip dynamic requires (no string literal — require(variable))
    if echo "$content" | grep -qE 'require\([^"'"'"']'; then
      continue
    fi

    # Extract the module name from require("flemma.foo.bar")
    module=$(echo "$content" | grep -oE 'require\("flemma\.[^"]*"' | head -1 | sed 's/require("//;s/"$//')

    # Check against the allowlist
    if [ -n "$module" ] && is_allowed "$file" "$module"; then
      continue
    fi

    # Keep sed: SC2001's ${var//search/replace} does a global strip and can't anchor to ^,
    # so it can't express this leading-only whitespace strip.
    # shellcheck disable=SC2001
    echo "  $file:$abs_line: $(echo "$content" | sed 's/^[[:space:]]*//')"
    violations=$((violations + 1))
  done < <(tail -n +"$first_fn" "$file" | grep -n -E 'require\(?"flemma\.' || true)
done

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "ERROR: Found $violations inline require(\"flemma.*\") call(s)."
  echo "Move them to the top of the file, before any function definitions."
  exit 1
fi

echo "lint-inline-requires: OK (no inline requires found)"
exit 0
