#!/usr/bin/env bash
set -euo pipefail

# version-packages.sh — Custom version command for the changesets action.
# Runs changeset version (bumps package.json, CHANGELOG, deletes changesets)
# then regenerates lua/flemma/version.lua with the clean release version.

cd "$(git rev-parse --show-toplevel)"

pnpm changeset version

contrib/scripts/sync-version.sh
