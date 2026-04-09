#!/usr/bin/env bash
# tests/fixtures/mcporter/mock-mcporter.sh
# Mock mcporter CLI for testing. Routes based on subcommand/args.
# Set MCPORTER_FIXTURE_DIR to point at the fixture directory.
# Set MCPORTER_EXIT_CODE to simulate non-zero exits.
# Set MCPORTER_DELAY to simulate slow responses (seconds).
set -euo pipefail

FIXTURE_DIR="${MCPORTER_FIXTURE_DIR:?MCPORTER_FIXTURE_DIR must be set}"
EXIT_CODE="${MCPORTER_EXIT_CODE:-0}"
DELAY="${MCPORTER_DELAY:-0}"

if [ "$DELAY" != "0" ]; then
  sleep "$DELAY"
fi

if [ "$EXIT_CODE" != "0" ]; then
  echo "mcporter: simulated error" >&2
  exit "$EXIT_CODE"
fi

CMD="${1:-}"
shift || true

case "$CMD" in
  list)
    # Check if a server name is provided (not a flag)
    SERVER=""
    for arg in "$@"; do
      case "$arg" in
        --*) ;; # skip flags
        *) SERVER="$arg" ;;
      esac
    done

    if [ -n "$SERVER" ]; then
      FIXTURE_FILE="$FIXTURE_DIR/list-${SERVER}.json"
    else
      FIXTURE_FILE="$FIXTURE_DIR/list.json"
    fi

    if [ -f "$FIXTURE_FILE" ]; then
      cat "$FIXTURE_FILE"
    else
      echo "{\"mode\":\"list\",\"counts\":{\"ok\":0},\"servers\":[]}"
    fi
    ;;
  call)
    # Parse selector: server.tool -> server__tool
    SELECTOR="${1:-}"
    shift || true
    # Convert dot to double underscore for fixture lookup
    FIXTURE_NAME="${SELECTOR//./__}"
    FIXTURE_FILE="$FIXTURE_DIR/call-${FIXTURE_NAME}.json"

    if [ -f "$FIXTURE_FILE" ]; then
      cat "$FIXTURE_FILE"
    else
      echo '{"content":[{"type":"text","text":"mock: no fixture for '"$SELECTOR"'"}]}' >&2
      exit 1
    fi
    ;;
  *)
    echo "mock-mcporter: unknown command '$CMD'" >&2
    exit 1
    ;;
esac
