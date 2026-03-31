#!/usr/bin/env nix-shell
#! nix-shell -i bash -p typst

# Sets up .vapor/aurora/ — a fake Go project used as the scene for
# the VHS demo recording.  Run from the repo root:
#
#   ./contrib/vhs/setup-aurora.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
AURORA_DIR="$ROOT_DIR/.vapor/aurora"

# ── Date helpers ─────────────────────────────────────────────────
# All dates are computed relative to "now" so the demo always looks fresh.

NOW="$(date +%s)"
days_ago() { date -u -d "@$((NOW - $1 * 86400))" "+%Y-%m-%d" 2>/dev/null ||
	date -u -r "$((NOW - $1 * 86400))" "+%Y-%m-%d"; }
ts_ago() { date -u -d "@$((NOW - $1 * 86400 + $2 * 3600))" "+%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null ||
	date -u -r "$((NOW - $1 * 86400 + $2 * 3600))" "+%Y-%m-%dT%H:%M:%S+00:00"; }
month_ago() { date -u -d "@$((NOW - $1 * 86400))" "+%B %Y" 2>/dev/null ||
	date -u -r "$((NOW - $1 * 86400))" "+%B %Y"; }

# ── Clean slate ──────────────────────────────────────────────────

rm -rf "$AURORA_DIR"
mkdir -p "$AURORA_DIR"
cd "$AURORA_DIR"

# ── Git repository ───────────────────────────────────────────────

git init -q
git branch -m main

commit() {
	local date="$1" name="$2" email="$3" msg="$4"
	shift 4
	git add "$@"
	GIT_AUTHOR_NAME="$name" GIT_AUTHOR_EMAIL="$email" \
		GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" \
		GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
		git commit -q -m "$msg"
}

# ── Project skeleton ─────────────────────────────────────────────

mkdir -p cmd/server internal/{router,auth,middleware,tls,pool} docs

cat >go.mod <<'EOF'
module github.com/Aurora-Dev/aurora

go 1.21

require (
	golang.org/x/net v0.21.0
	golang.org/x/crypto v0.19.0
)
EOF
touch go.sum main.go cmd/server/main.go LICENSE
touch internal/router/router.go internal/pool/pool.go

cat >.gitignore <<'EOF'
/bin/
/dist/
*.test
*.out
EOF

cat >README.md <<'EOF'
# Aurora

A lightweight, high-performance HTTP framework for Go.

```go
app := aurora.New()
app.Get("/hello", func(c *aurora.Context) {
    c.JSON(200, aurora.Map{"message": "hello"})
})
app.Listen(":8080")
```
EOF

cat >CHANGELOG.md <<EOF
# Changelog

## v0.3.0 ($(days_ago 105))

### Features
- WebSocket upgrade support
- Middleware chaining with \`Use()\` API
- Graceful shutdown with configurable timeout

### Fixes
- Fix panic on nil context in error handler
- Fix Content-Type sniffing for multipart uploads

## v0.2.0 ($(days_ago 210))

### Features
- Route groups with shared middleware
- Built-in CORS middleware
- Request/response logging middleware

### Fixes
- Fix memory leak in connection pool
- Fix incorrect 404 on trailing slash routes

## v0.1.0 ($(days_ago 300))

Initial release.
EOF

commit "$(ts_ago 21 9)" \
	"Jordan Lee" "jordan@auroradev.io" \
	"feat: initial project structure for v0.4 cycle" \
	.

# ── Feature commits ──────────────────────────────────────────────

touch internal/auth/oauth.go internal/auth/pkce.go
commit "$(ts_ago 17 14)" \
	"Sam Rivera" "sam@auroradev.io" \
	"feat(auth): add OAuth2 PKCE flow support" \
	internal/auth/

touch internal/router/params.go
commit "$(ts_ago 13 10)" \
	"Jordan Lee" "jordan@auroradev.io" \
	"fix(router): resolve path parameter collision on nested routes" \
	internal/router/params.go

touch internal/middleware/ratelimit.go internal/middleware/sliding_window.go
commit "$(ts_ago 9 16)" \
	"Sam Rivera" "sam@auroradev.io" \
	"feat(middleware): add request rate limiting with sliding window" \
	internal/middleware/

touch docs/api-reference.md
commit "$(ts_ago 6 11)" \
	"Jordan Lee" "jordan@auroradev.io" \
	"docs: update API reference for v0.4 endpoints" \
	docs/api-reference.md

touch internal/tls/certs.go internal/tls/system_store_linux.go
commit "$(ts_ago 4 9)" \
	"Sam Rivera" "sam@auroradev.io" \
	"fix(tls): honor system cert store on Linux" \
	internal/tls/

cat >go.mod <<'EOF'
module github.com/Aurora-Dev/aurora

go 1.22

require (
	golang.org/x/net v0.21.0
	golang.org/x/crypto v0.19.0
)
EOF
commit "$(ts_ago 2 13)" \
	"Jordan Lee" "jordan@auroradev.io" \
	"chore: bump minimum Go version to 1.22" \
	go.mod

# ── PDF: Architecture document ───────────────────────────────────

TYPST_SRC="$(mktemp)"
PDF_DATE="$(month_ago 0)"

# Header with date substitution (unquoted heredoc).
cat >"$TYPST_SRC" <<TYPST_HEAD
#set document(title: "Aurora Architecture Overview", author: "Aurora Team")
#set page(margin: (x: 2.5cm, y: 2.5cm), numbering: "1")
#set text(size: 11pt)
#set heading(numbering: "1.1")

#align(center)[
  #text(size: 20pt, weight: "bold")[Aurora Architecture Overview]
  #v(4pt)
  #text(size: 12pt, fill: luma(100))[Version 0.4.0 · ${PDF_DATE}]
]
TYPST_HEAD

# Body (quoted heredoc — no expansion needed).
cat >>"$TYPST_SRC" <<'TYPST_BODY'

#v(1em)

= Introduction

Aurora is a lightweight HTTP framework for Go, designed for high throughput
and low latency in microservice deployments. This document describes the
core architectural decisions in the v0.4 release.

= Concurrency Model

Aurora handles concurrent requests through a *managed goroutine pool* with
adaptive sizing. The pool maintains a baseline of warm goroutines
proportional to `GOMAXPROCS`, scaling up under load and draining idle
workers after a configurable cooldown (default: 30 seconds).

Each inbound connection is assigned to a pooled goroutine, which owns the
full request lifecycle — parsing, middleware execution, handler dispatch,
and response serialization. This avoids per-request allocation overhead and
provides natural backpressure: when the pool is saturated, new connections
queue at the listener level rather than spawning unbounded goroutines.

The pool implementation lives in `internal/pool` and exposes a
`Submit(func())` interface consumed by the server loop.

= Routing

The router uses a compressed radix tree with support for path parameters
(`:id`), wildcards (`*path`), and static segments. Route registration is
O(k) in the length of the path. Lookup is O(k) with early termination on
mismatch.

Route groups share middleware chains via pointer — adding a group does not
copy the parent middleware slice, keeping memory flat for applications with
many nested groups.

= Middleware Pipeline

Middleware functions conform to the `func(next Handler) Handler` signature.
The pipeline is compiled once at startup into a single function chain. At
request time, the chain executes without allocations beyond the initial
context.

Built-in middleware includes logging, CORS, recovery, and — new in v0.4 —
request rate limiting with a sliding window algorithm.

= Security

TLS configuration is handled by the standard library's `crypto/tls`
package. Aurora v0.4 adds automatic detection of the system certificate
store on Linux via `crypto/x509.SystemCertPool()`, removing the need to
manually specify CA bundles in containerized deployments.

OAuth2 PKCE support is provided through the `internal/auth` package,
implementing RFC 7636 for public clients.
TYPST_BODY

typst compile "$TYPST_SRC" "$AURORA_DIR/docs/architecture.pdf"
rm -f "$TYPST_SRC"

commit "$(ts_ago 1 10)" \
	"Jordan Lee" "jordan@auroradev.io" \
	"docs: add v0.4 architecture overview" \
	docs/architecture.pdf

# ── Done ─────────────────────────────────────────────────────────

echo "aurora demo ready: $AURORA_DIR"
echo "  $(git -C "$AURORA_DIR" log --oneline | wc -l) commits"
echo "  $(find "$AURORA_DIR" -name '*.pdf' | wc -l) PDF"
