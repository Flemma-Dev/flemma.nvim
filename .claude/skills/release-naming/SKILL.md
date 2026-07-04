---
name: release-naming
description: Use when naming or cutting a Flemma minor release — picking a codename, running `pnpm changeset version`, or writing GitHub release notes. Assigns a single-word typographic codename matched to the release's headline work and logs it in the ledger so names are never reused. Trigger on "release name", "codename", "name the release", "cut a release", "changeset version", "release notes".
---

# Release Naming — the Flemma codex

Every Flemma **minor** release earns a single-word codename drawn from the world of type, printing, and bookmaking — chosen fresh to fit _that_ release, never pre-generated, never reused. The name goes in the **GitHub release title** (e.g. `v0.13.0 — Ascender`) and is logged in [`used-names.md`](used-names.md) (titled _Incipit_), the one source of truth for what's been taken.

Patch releases are not named.

## Invariants

- **One single word**, from the typographic / bookbinding vocabulary.
- **Free pick, story-matched** — choose the term whose literal meaning rhymes with the release's headline work. The name is a label that means something, not a serial number.
- **Inoffensive, apolitical, hard to misconstrue, easy to say and tag.**
- **No reserve list.** Do not keep or invent a palette of candidates — forage the vocabulary fresh each time.
- **Never reuse.** Every name in `used-names.md` is spent. Check it before you pick.
- **Always record.** A release isn't named until its entry lands in the ledger.
- **No riff, no marketing prose.** The name earns a single-line "headline it fit" in the ledger — nothing more. The release notes are factual and developer-facing (see below); never open them with flowery paragraphs about the codename.

## How to name a release

1. **Read what's in the release.** The headline work, not the trivia — scan `.changeset/*.md` (the pending bump entries) and/or `git log <last-tag>..HEAD`. One or two themes usually dominate.
2. **Read the ledger.** Open `used-names.md` and note every name already spent.
3. **Forage the vocabulary and pick one.** Range across the territory of type and books:
   - **letterform anatomy** — the parts of a glyph,
   - **page & layout geometry** — how type sits on a sheet and a sheet in a book,
   - **printer's & proofreader's marks** — the symbols of the trade,
   - **manuscript, printing & codex terms** — how books are set, gathered, and bound.

   Choose the single **unused** term whose meaning best fits this release's headline. Don't settle for the first word that comes to mind — find the one that _earns_ the release.

4. **Record it.** Append one row to the **Ledger** table in `used-names.md`: `version`, `codename`, and a one-line "headline it fit". That is the entire record — no riff, no prose entry.

## Writing the release notes

The codename's only footprint in the release is the **title**. The notes body follows Flemma's established format — mirror the previous releases on GitHub (v0.12.0, v0.11.0, …). Author this content **before** the auto-generated `### Minor Changes` / `### Patch Changes` sections (which come from `pnpm changeset version` — never hand-edit them):

- `### The gist…` — one paragraph, **features first** (users want features, not incremental improvements); bug fixes come second or are omitted. Bold the feature names inline.
- `#### New Feature: <Name>` — one short section per major feature: what it does, how to use it (a small code block), a link to the relevant `docs/*.md`, and any associated **Breaking:** notes inline.
- `#### New Models` — if models changed, list them with IDs / pricing and any removals.
- `#### Polish and Bug Fixes` — free text, bold lead-ins for notable polish, then a run-on `**Bug fixes:**` list for the long tail.

Keep it factual and developer-facing. No riff, no marketing gibberish.

## Where the name goes (and doesn't)

- ✅ The **GitHub release title** (`vX.Y.Z — Codename`), and `used-names.md`.
- ❌ **Not** the release-notes body, `CHANGELOG.md`, or `package.json` — the changelog and version are managed by `pnpm changeset version`; never hand-edit them.

## Worked example — 0.13.0 "Ascender"

The release where Flemma gained reach — the experimental Codex provider, new models, the `flemma.hl` highlight builder, the tool-result store, and the inline approval/rejection flow. The pick isn't tied to a single feature: the ascender is the stroke that climbs above the x-height, so the name marks the _stature_ of the release rather than any one item. One row in the ledger, the codename in the title — that's the whole ceremony.
