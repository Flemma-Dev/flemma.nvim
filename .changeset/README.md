# Changesets

This directory is used by [changesets](https://github.com/changesets/changesets) to track version bumps and changelog entries.

Each `.md` file (other than this README) represents a pending change that will be consumed by `pnpm changeset version` to update `CHANGELOG.md` and bump the version in `package.json`.

Changesets are managed by AI agents as part of the development workflow. See `.claude/CLAUDE.md` for the full protocol.
