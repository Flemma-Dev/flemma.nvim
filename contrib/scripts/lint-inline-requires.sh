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
# ast/init.lua:      dump is lazy-required via metatable __index to break the
#                    ast↔dump circular dependency (ast imports dump, dump imports
#                    parser, parser imports ast) — see the file's header note.
ALLOWED_INLINE=(
  "lua/flemma/commands.lua=*"
  "lua/flemma/config/schema.lua=*"
  "lua/flemma/tools/init.lua=flemma.tools.executor"
  "lua/flemma/ast/init.lua=flemma.ast.dump"
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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pass 1: an inline require is a require("flemma.…") inside a function body.
# ast-grep matches this structurally (inline-require.yml) — correctly catching
# the assignment/anonymous-style functions the old line-position heuristic
# skipped — and emits each match as JSON. We pull file + line + module out with
# jq and apply the ALLOWED_INLINE allowlist here; whatever is left is a violation.
violations=0

# Run detection up front and capture it. A process substitution (< <(…)) hides
# the pipeline's exit status from the parent shell even under pipefail, so an
# ast-grep/jq failure (missing or malformed rule, a crash) would yield no output
# and be silently reported as "no violations". Capturing lets pipefail + || turn
# any such tooling failure into a gate error instead of a false pass.
if ! matches=$(
  ast-grep scan --rule "${script_dir}/inline-require.yml" --json=compact lua/flemma/ |
    jq -r '.[] | [.file, (.range.start.line + 1), .metaVariables.single.ARG.text] | @tsv'
); then
  echo "ERROR: inline-require detection failed (ast-grep or jq errored above)." >&2
  exit 1
fi

while IFS=$'\t' read -r file line module; do
  [ -z "$file" ] && continue
  # metaVariables.single.ARG.text arrives as the quoted string literal, e.g.
  # "flemma.foo"; strip the surrounding quotes to match the allowlist format.
  module="${module#\"}"
  module="${module%\"}"

  if is_allowed "$file" "$module"; then
    continue
  fi

  # Print the whole source statement: ast-grep's match text is just the
  # require(...) call, but the house format shows the full line (e.g. the
  # enclosing assignment). Keep sed: a leading-only whitespace strip can't
  # anchor to ^ with ${var//search/replace}.
  # shellcheck disable=SC2001
  echo "  $file:$line: $(sed -n "${line}p" "$file" | sed 's/^[[:space:]]*//')"
  violations=$((violations + 1))
done <<<"$matches"

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "ERROR: Found $violations inline require(\"flemma.*\") call(s)."
  echo "Move them to the top of the file, before any function definitions."
  exit 1
fi

echo "lint-inline-requires: OK"
exit 0
