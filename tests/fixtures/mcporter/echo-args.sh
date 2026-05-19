#!/usr/bin/env bash
# Echoes all arguments as a JSON MCP response so tests can inspect the command line.
set -euo pipefail
printf '{"content":[{"type":"text","text":"%s"}]}' "$*"
