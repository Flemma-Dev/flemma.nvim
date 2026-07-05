#!/usr/bin/env bash
# contrib/scripts/lint-po.sh
# Validate every shipped gettext PO catalogue with GNU msgfmt.
# Each po/*.po file must pass `msgfmt --check` — PO syntax, format-string
# consistency, and header well-formedness — by gettext's own judgement.
# This complements the flemma.utilities.po parser tests: the gate runs
# standalone and fast, so broken catalogue syntax fails before the Neovim
# test harness even starts, and independently of it.
# Exits 0 if all catalogues are valid, 1 otherwise.
set -euo pipefail

if ! command -v msgfmt >/dev/null 2>&1; then
  echo "ERROR: msgfmt not found — run from within the 'nix develop' shell (gettext)." >&2
  exit 1
fi

status=0

for file in po/*.po; do
  # --check validates the PO; the compiled .mo is discarded to /dev/null.
  # Warnings (e.g. missing translator-workflow header fields, irrelevant to a
  # monolingual key-based catalogue) exit 0 and are swallowed here; only a
  # non-zero exit — a real structural or format error — fails the gate.
  if ! output=$(msgfmt --check -o /dev/null "$file" 2>&1); then
    echo "  $file:"
    # Indent each line of msgfmt's report under the filename (bash-native, no sed).
    echo "    ${output//$'\n'/$'\n'    }"
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  echo ""
  echo "ERROR: one or more PO catalogues failed msgfmt --check."
  exit 1
fi

echo "lint-po: OK (po/*.po valid by msgfmt --check)"
exit 0
