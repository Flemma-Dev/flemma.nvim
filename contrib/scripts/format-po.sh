#!/usr/bin/env bash
# contrib/scripts/format-po.sh
# treefmt formatter for gettext PO catalogues. Normalizes each file to
# `msgcat --no-wrap` canonical form — one msgstr per line, no 79-column
# wrapping — so full catalogue strings stay greppable back to source (the
# same greppability the inline flemma.logging strings preserve). Formats
# each argument in place; treefmt passes the matched *.po paths.
#
# A per-file loop is required: msgcat CONCATENATES when handed several input
# files, so it must never see more than one at a time. In-place `-o FILE FILE`
# is safe — msgcat buffers the whole input before writing.
set -euo pipefail

if ! command -v msgcat >/dev/null 2>&1; then
  echo "ERROR: msgcat not found — run from within the 'nix develop' shell (gettext)." >&2
  exit 1
fi

for file in "$@"; do
  msgcat --no-wrap -o "$file" "$file"
done
