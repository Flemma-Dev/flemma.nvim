#!/usr/bin/env bash
# contrib/scripts/format-messages-brace-call.sh
# Post-stylua formatter: rewrite `messages["key"]({ ... })` to the brace-call
# house style `messages["key"]{ ... }`.
#
# stylua's default call_parentheses ("Always") re-adds the parentheses on every
# run, and .stylua.toml deliberately does not override it — flipping it globally
# would touch every single-table call in the repo, not just messages[...] sites.
# So this step runs AFTER stylua on every `make format`, stripping the
# parentheses back off the messages[...] call sites specifically. The heavy
# lifting is an ast-grep structural rewrite (see messages-brace-call.yml); it
# only matches the parenthesized form, so re-running is a no-op.
#
# Usage: format-messages-brace-call.sh [path ...]   (default: lua tests)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rule="${script_dir}/ast-grep/rules/messages-brace-call.yml"

if [ "$#" -eq 0 ]; then
  set -- lua tests
fi

ast-grep scan --rule "${rule}" --update-all "$@"
