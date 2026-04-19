#!/usr/bin/env bash
# contrib/scripts/lint-no-vim-notify.sh
# Detect direct vim.notify / vim.notify_once calls in production code.
# All user-facing notifications must go through flemma.notify (see lua/flemma/notify.lua).
# Exits 0 if clean, 1 if violations found.
set -euo pipefail

# Files allowed to call vim.notify directly:
# notify.lua: the flemma.notify module itself; default_impl IS a vim.notify call
# init.lua:   pre-Neovim-0.11 fallback that bypasses flemma.notify because the
#             module needs vim.uv (0.11+) and would fail to load on older versions
ALLOW_FILES="lua/flemma/notify.lua lua/flemma/init.lua"

violations=0

for file in $(find lua/flemma -name '*.lua' -type f | sort); do
  # Skip allow-listed files
  for allow_file in $ALLOW_FILES; do
    if [ "$file" = "$allow_file" ]; then
      continue 2
    fi
  done

  # Find vim.notify( and vim.notify_once( call sites, ignoring comment-only matches
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    line_num=$(echo "$match" | cut -d: -f1)
    content=$(echo "$match" | cut -d: -f2-)

    # Strip Lua line comment (everything from -- onwards) and re-check
    # NB: this naive strip false-positives on `--` inside string literals,
    # but the codebase has no such cases today; if one appears, the script
    # can be extended or the line can be split to avoid the false match.
    pre_comment="${content%%--*}"
    if ! echo "$pre_comment" | grep -qE 'vim\.notify(_once)?\('; then
      continue
    fi

    echo "  $file:$line_num: $(echo "$content" | sed 's/^[[:space:]]*//')"
    violations=$((violations + 1))
  done < <(grep -n -E 'vim\.notify(_once)?\(' "$file" || true)
done

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "ERROR: Found $violations direct vim.notify call(s) in production code."
  echo "Use flemma.notify instead (see lua/flemma/notify.lua)."
  exit 1
fi

echo "lint-no-vim-notify: OK (no direct vim.notify calls found)"
exit 0
</content>
</invoke>