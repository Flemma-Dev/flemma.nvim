---
"@flemma-dev/flemma.nvim": minor
---

Added pluggable secrets module for credential resolution. Providers now declare
what credentials they need (kind + service) and platform-aware resolvers handle
lookup from environment variables, GNOME Keyring (Linux), macOS Keychain, and
gcloud CLI. Includes TTL-aware caching with configurable freshness scaling.
Existing keyring entries stored under the previous scheme are still supported
via legacy fallback.
