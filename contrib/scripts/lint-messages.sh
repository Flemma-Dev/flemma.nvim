#!/usr/bin/env bash
# contrib/scripts/lint-messages.sh
# PO catalogue integrity — validates shipped catalogues and source↔key consistency.
#   Pass 1: msgfmt --check on every po/*.po (PO syntax, format-string consistency)
#   Pass 2: every messages["key"] in source resolves to a PO entry (ERROR — runtime crash)
#   Pass 3: every PO entry is referenced in source (WARNING — dead key, wasted translator effort)
#   Pass 4: variable consistency — call-site {vars} vs msgstr {{ placeholders }},
#           #. Variables: comments, and pure-formatting entries (no translatable words)
#   Pass 5: messages import naming via ast-grep (must be `local messages`)
#   Pass 6: user-facing notify.* must route through messages, not inline literals
#   Pass 7: translations may only be joined by newlines, never punctuation
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

# --- Pass 4: variable consistency ---
# For each messages["key"]{ var = ... } call, extract the variable names
# passed at the call site and compare against {{ var }} placeholders in the
# PO msgstr. Mismatches are warnings (call-site typo or missing template var).

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

call_site_rule="${script_dir}/messages-call-variables.yml"
if [ -f "$call_site_rule" ]; then
  # Build key→call-site-variables map from ast-grep matches.
  declare -A call_vars
  while IFS=$'\t' read -r raw_key match_text; do
    [ -z "$raw_key" ] && continue
    key="${raw_key#\"}"
    key="${key%\"}"
    # Strip the messages["..."]{ prefix, then extract word = field names.
    # The jq output already has newlines replaced with spaces.
    body="${match_text#*\{}"
    vars=$(echo "$body" | grep -oP '\b\w+(?=\s*=\s)' | sort -u | tr '\n' ',' | sed 's/,$//' || true)
    if [ -n "$vars" ]; then
      call_vars["$key"]="$vars"
    fi
  done < <(ast-grep scan --rule "$call_site_rule" --json=compact lua/ tests/ 2>/dev/null |
    jq -r '.[] | .metaVariables.single.KEY.text + "\t" + (.text | gsub("\n"; " "))')

  # Build key→template-variables map from PO msgstr {{ var }} placeholders.
  # Also track whether each entry's comment block includes `#. Variables:`.
  # Plural entries implicitly accept `count` for the Plural-Forms selector.
  declare -A tmpl_vars
  declare -A plural_keys
  declare -A has_var_comment
  current_key=""
  current_str=""
  current_has_var_comment=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^"#." ]] && [[ "$line" =~ "Variables:" ]]; then
      current_has_var_comment=1
    elif [[ "$line" =~ ^"#." ]]; then
      : # other extracted comment lines — keep current_has_var_comment
    elif [[ "$line" =~ ^"#" ]]; then
      # Translator comments (#, #:, #,, #~) are not extracted comments —
      # reset the Variables flag so it doesn't bleed into the next entry.
      current_has_var_comment=""
    elif [[ "$line" =~ ^msgid\ \"(.+)\"$ ]]; then
      current_key="${BASH_REMATCH[1]}"
      current_str=""
      if [ -n "$current_has_var_comment" ]; then
        has_var_comment["$current_key"]=1
      fi
      current_has_var_comment=""
    elif [[ "$line" =~ ^msgid_plural ]]; then
      plural_keys["$current_key"]=1
    elif [[ "$line" =~ ^msgstr(\[[0-9]+\])?\ \"(.*)\"$ ]]; then
      current_str="${current_str}${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^\"(.*)\"$ ]]; then
      current_str="${current_str}${BASH_REMATCH[1]}"
    elif [[ -z "$line" || "$line" =~ ^# ]] && [ -n "$current_key" ]; then
      if [ -n "$current_str" ]; then
        # Pure-formatting check: strip {{ vars }} and every non-letter. If
        # nothing remains, the entry has no translatable words — it's pure
        # formatting (e.g. "{{ path }}: {{ message }}") and should be composed
        # in code, not catalogued. Letters from any script count (Unicode-aware).
        stripped=$(echo "$current_str" | sed 's/{{[^}]*}}//g' | grep -oP '[[:alpha:]]' || true)
        if [ -z "$stripped" ]; then
          echo "  ERROR: msgid \"${current_key}\" is pure formatting (no translatable words): \"${current_str}\""
          errors=$((errors + 1))
        fi
        vars=$(echo "$current_str" | grep -oP '\{\{\s*\K\w+(?=\s*\}\})' | sort -u | tr '\n' ',' | sed 's/,$//' || true)
        # Plural entries implicitly accept `count` for the Plural-Forms selector.
        if [ -n "${plural_keys[$current_key]:-}" ]; then
          if [ -n "$vars" ]; then
            vars=$(echo "$vars,count" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
          else
            vars="count"
          fi
        fi
        if [ -n "$vars" ]; then
          tmpl_vars["$current_key"]="$vars"
        fi
      fi
      current_key=""
      current_str=""
    fi
  done < <(
    cat po/*.po
    echo ""
  )

  # Entries with {{ }} placeholders must have a #. Variables: comment.
  for key in "${!tmpl_vars[@]}"; do
    if [ -z "${has_var_comment[$key]:-}" ]; then
      echo "  ERROR: msgid \"${key}\" has {{ }} placeholders but no #. Variables: comment"
      errors=$((errors + 1))
    fi
  done

  # Compare: call-site variables vs template variables.
  for key in "${!call_vars[@]}"; do
    cv="${call_vars[$key]}"
    tv="${tmpl_vars[$key]:-}"
    if [ -n "$cv" ] && [ -z "$tv" ]; then
      echo "  WARNING: messages[\"${key}\"] passes variables (${cv}) but msgstr has no {{ }} placeholders"
      warnings=$((warnings + 1))
    elif [ -n "$cv" ] && [ -n "$tv" ]; then
      # Normalize for comparison (sorted comma-separated).
      cv_sorted=$(echo "$cv" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')
      tv_sorted=$(echo "$tv" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')
      if [ "$cv_sorted" != "$tv_sorted" ]; then
        echo "  WARNING: messages[\"${key}\"] variable mismatch — call site: ${cv_sorted}, template: ${tv_sorted}"
        warnings=$((warnings + 1))
      fi
    fi
  done

  # Reverse: template has {{ }} but call site passes no variables.
  for key in "${!tmpl_vars[@]}"; do
    if [ -z "${call_vars[$key]:-}" ]; then
      # Only warn if this key appears in source at all (dead keys handled above).
      if echo "$source_keys" | grep -qxF "$key"; then
        echo "  WARNING: msgid \"${key}\" has {{ }} placeholders but no call site passes variables"
        warnings=$((warnings + 1))
      fi
    fi
  done
fi

# --- Pass 5: messages import naming (ast-grep) ---

naming_rule="${script_dir}/messages-import-name.yml"
naming_output=$(ast-grep scan --rule "${naming_rule}" lua/ 2>&1) || true
if [ -n "$naming_output" ]; then
  echo "$naming_output"
  errors=$((errors + 1))
fi

# --- Pass 6: user-facing notify.* must route through messages ---
# A string literal (two or more letters) spliced into notify.warn/error/info
# is untranslated prose. Catalogue keys (messages["ui.x"]) are excluded by the
# rule; only direct literals match. Reported as errors — the whole point of the
# catalogue is that the user-facing surface is translatable.

notify_rule="${script_dir}/notify-string-literal.yml"
while IFS= read -r match_line; do
  [ -z "$match_line" ] && continue
  echo "  ERROR: user-facing notify with an inline string literal (route through messages):"
  echo "    ${match_line}"
  errors=$((errors + 1))
done < <(ast-grep scan --rule "${notify_rule}" --json=compact lua/ 2>/dev/null |
  jq -r '.[] | "\(.file):\(.range.start.line + 1): \(.text | gsub("\n";" ") | .[0:80])"')

# --- Pass 7: translations may only be joined by newlines ---
# A self-append that pulls in a message (msg = msg .. SEP .. messages[...]) is
# fine when SEP is a newline (layout) but not when it is language-specific
# punctuation like ". " or " " (grammar) — the joiner would be wrong in scripts
# that don't end sentences with a period/space. Each catalogue string must stay
# a complete, independently translatable unit joined only by "\n".

self_append_rule="${script_dir}/messages-self-append.yml"
while IFS=$'\t' read -r loc text; do
  [ -z "$loc" ] && continue
  bad=""
  while IFS= read -r lit; do
    lit="${lit#\"}"
    lit="${lit%\"}"
    # Skip catalogue keys (lowercase dotted identifiers) — not joiners.
    [[ "$lit" =~ ^[a-z][a-z0-9_.]*$ ]] && continue
    # Allowed joiner: newline-only. Strip every \n; anything left is grammar.
    [ -z "${lit//\\n/}" ] && continue
    bad="${bad}'${lit}' "
  done < <(printf '%s' "$text" | grep -oP '"[^"]*"')
  if [ -n "$bad" ]; then
    echo "  ERROR: ${loc} joins a translation with a non-newline separator: ${bad}"
    printf '    translations may only be joined by "\\n" — use a fuller message or newline layout\n'
    errors=$((errors + 1))
  fi
done < <(ast-grep scan --rule "${self_append_rule}" --json=compact lua/ 2>/dev/null |
  jq -r '.[] | "\(.file):\(.range.start.line + 1)\t\(.text | gsub("\n"; " "))"')

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
