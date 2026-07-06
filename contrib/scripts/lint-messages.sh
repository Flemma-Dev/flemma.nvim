#!/usr/bin/env bash
# contrib/scripts/lint-messages.sh
# PO catalogue integrity — validates shipped catalogues and source↔key consistency.
#   Pass 1: msgfmt --check on every po/*.po (PO syntax, format-string consistency)
#   Pass 2: every messages["key"] in source resolves to a PO entry (ERROR — runtime crash)
#   Pass 3: every PO entry is referenced in source (WARNING — dead key, wasted translator effort)
#   Pass 4: messages import naming via ast-grep (must be `local messages`)
# Exits 0 if clean (warnings are reported but non-fatal), 1 on errors.
set -euo pipefail

if ! command -v msgfmt >/dev/null 2>&1; then
  echo "ERROR: msgfmt not found — run from within the 'nix develop' shell (gettext)." >&2
  exit 1
fi

# Keys that exist only in test error-path assertions — intentionally absent from PO.
ALLOWED_MISSING=(
  "does.not.exist"
)

is_allowed_missing() {
  local key="$1"
  for allowed in "${ALLOWED_MISSING[@]}"; do
    if [ "$key" = "$allowed" ]; then
      return 0
    fi
  done
  return 1
}

errors=0
warnings=0

# --- Pass 1: msgfmt --check ---

for file in po/*.po; do
  if ! output=$(msgfmt --check -o /dev/null "$file" 2>&1); then
    echo "  $file:"
    echo "    ${output//$'\n'/$'\n'    }"
    errors=$((errors + 1))
  fi
done

# --- Pass 2 + 3: source↔PO key consistency ---

# All messages["..."] references in production + test code, excluding comment lines.
source_keys=$(
  grep -rn --include='*.lua' 'messages\["[^"]*"\]' lua/ tests/ |
    grep -v '^\([^:]*:[^:]*:\)\s*--' |
    grep -oh 'messages\["[^"]*"\]' |
    sed 's/^messages\["//;s/"\]$//' |
    sort -u
)

# All msgid values from PO files (skip the empty header msgid).
po_keys=$(
  grep '^msgid "' po/*.po |
    grep -v ':msgid ""$' |
    sed 's/^.*:msgid "//;s/"$//' |
    sort -u
)

# Source keys not in PO (ERROR — would crash at runtime).
missing=$(comm -23 <(echo "$source_keys") <(echo "$po_keys"))
if [ -n "$missing" ]; then
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    if is_allowed_missing "$key"; then
      continue
    fi
    locations=$(grep -rn --include='*.lua' "messages\[\"${key}\"\]" lua/ tests/ | head -3)
    echo "  ERROR: messages[\"${key}\"] not found in any PO file"
    # Keep sed: SC2001's ${var//search/replace} does a global strip and can't
    # anchor to ^, so it can't express this leading-only indent.
    # shellcheck disable=SC2001
    echo "$locations" | sed 's/^/    /'
    errors=$((errors + 1))
  done <<<"$missing"
fi

# PO keys not in source (WARNING — dead key).
unused=$(comm -13 <(echo "$source_keys") <(echo "$po_keys"))
if [ -n "$unused" ]; then
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    echo "  WARNING: msgid \"${key}\" in PO but not referenced in source"
    warnings=$((warnings + 1))
  done <<<"$unused"
fi

# --- Pass 4: messages import naming (ast-grep) ---

naming_rule="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/messages-import-name.yml"
naming_output=$(ast-grep scan --rule "${naming_rule}" lua/ 2>&1) || true
if [ -n "$naming_output" ]; then
  echo "$naming_output"
  errors=$((errors + 1))
fi

# --- Summary ---

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "ERROR: Found ${errors} PO/messages error(s)."
  exit 1
fi

if [ "$warnings" -gt 0 ]; then
  echo ""
  echo "lint-messages: OK (with ${warnings} warning(s) — dead PO keys)"
  exit 0
fi

echo "lint-messages: OK"
exit 0
