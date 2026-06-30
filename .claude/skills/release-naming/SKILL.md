---
name: release-naming
description: Use when naming or cutting a Flemma minor release — picking a codename, running `pnpm changeset version`, or writing GitHub release notes. Assigns a single-word typographic codename matched to the release's headline work and logs it in the ledger so names are never reused. Trigger on "release name", "codename", "name the release", "cut a release", "changeset version", "release notes".
---

# Release Naming — the Flemma codex

Every Flemma **minor** release earns a single-word codename drawn from the world of type, printing, and bookmaking — chosen fresh to fit _that_ release, never pre-generated, never reused. The name heads the GitHub release notes and is logged in [`used-names.md`](used-names.md) (titled _Incipit_), the one source of truth for what's been taken.

Patch releases are not named.

## Invariants

- **One single word**, from the typographic / bookbinding vocabulary.
- **Free pick, story-matched** — choose the term whose literal meaning rhymes with the release's headline work. The name is a label you can _write about_, not a serial number.
- **Inoffensive, apolitical, hard to misconstrue, easy to say and tag.**
- **No reserve list.** Do not keep or invent a palette of candidates — forage the vocabulary fresh each time.
- **Never reuse.** Every name in `used-names.md` is spent. Check it before you pick.
- **Always record.** A release isn't named until its entry lands in the ledger.

## How to name a release

1. **Read what's in the release.** The headline work, not the trivia — scan `.changeset/*.md` (the pending bump entries) and/or `git log <last-tag>..HEAD`. One or two themes usually dominate.
2. **Read the ledger.** Open `used-names.md` and note every name already spent.
3. **Forage the vocabulary and pick one.** Range across the territory of type and books:
   - **letterform anatomy** — the parts of a glyph,
   - **page & layout geometry** — how type sits on a sheet and a sheet in a book,
   - **printer's & proofreader's marks** — the symbols of the trade,
   - **manuscript, printing & codex terms** — how books are set, gathered, and bound.

   Choose the single **unused** term whose meaning best fits this release's headline. Don't settle for the first word that comes to mind — find the one that _earns_ the release.

4. **Write the riff.** ~60–100 words connecting the term's literal meaning to what the release actually shipped. This is the opening of the GitHub release notes.
5. **Record it** (below).

## Record it

Append to `used-names.md`:

- a row in the **Ledger** table — `version`, `codename`, a one-line "headline it fit",
- the full riff under **Entries**.

The ledger is version-controlled, so the history travels with the repo and every future release agent sees what's spent. This skill holds no list of its own — the ledger _is_ the memory.

## Where the name goes (and doesn't)

- ✅ The **GitHub release** title / notes, and `used-names.md`.
- ❌ **Not** `CHANGELOG.md` or `package.json` — those are managed by `pnpm changeset version`; never hand-edit them.

## Worked example — 0.13.0 "Ascender"

The release where Flemma gained reach (new models, the declarative colorscheme subsystem, the tool-result store, the approval/rejection flow). The pick isn't tied to a single feature — it's the _stature_ of the release.

> **0.13 "Ascender."** In type, the ascender is the upward stroke that climbs above the x-height — the reach on a _b_, _d_, _h_, _k_, _l_ — the part of a letterform that breaks the line's ceiling and gives a face its height and rhythm. A fitting mark for the release where Flemma gains reach: new models to draw on, a colorscheme subsystem that brings the harness into full view, a result store and approval flow that let it stretch further without losing its footing. The first name in the book — Flemma, rising above the line.
