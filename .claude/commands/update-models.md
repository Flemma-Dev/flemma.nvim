---
description: Update models and pricing in per-provider model files using models.dev API and provider documentation
disable-model-invocation: true
---

# Update Models and Pricing

Update the per-provider model data files under `lua/flemma/models/` with up-to-date information about the models and pricing of Google Gemini (via Vertex AI), Anthropic Claude, OpenAI, and Moonshot AI.

**Target files:**

- `lua/flemma/models/anthropic.lua`
- `lua/flemma/models/openai.lua`
- `lua/flemma/models/vertex.lua`
- `lua/flemma/models/moonshot.lua`

Each file is a pure data module returning `{ default = "...", models = { ... } }`. Type annotations live in `lua/flemma/models/types.lua` (do not modify).

## Phase 1: Fetch models.dev API data

Download the models.dev API and extract relevant data using jq:

```bash
curl -sL 'https://models.dev/api.json' -o /tmp/models-dev.json
```

Then extract what we need:

```bash
jq '
{
  anthropic: [.anthropic.models | to_entries[]
    | select(.value.tool_call == true)
    | {
        id: .key,
        name: .value.name,
        input: .value.cost.input,
        output: .value.cost.output,
        cache_read: .value.cost.cache_read,
        cache_write: .value.cost.cache_write,
        context: .value.limit.context,
        max_input: .value.limit.input,
        max_output: .value.limit.output,
        reasoning: .value.reasoning
      }
  ],
  google: [.google.models | to_entries[]
    | select(.value.tool_call == true)
    | {
        id: .key,
        name: .value.name,
        input: .value.cost.input,
        output: .value.cost.output,
        cache_read: .value.cost.cache_read,
        cache_write: .value.cost.cache_write,
        context: .value.limit.context,
        max_input: .value.limit.input,
        max_output: .value.limit.output,
        reasoning: .value.reasoning
      }
  ],
  openai: [.openai.models | to_entries[]
    | select(.value.tool_call == true)
    | {
        id: .key,
        name: .value.name,
        input: .value.cost.input,
        output: .value.cost.output,
        cache_read: .value.cost.cache_read,
        cache_write: .value.cost.cache_write,
        context: .value.limit.context,
        max_input: .value.limit.input,
        max_output: .value.limit.output,
        reasoning: .value.reasoning
      }
  ],
  moonshotai: [.moonshotai.models | to_entries[]
    | select(.value.tool_call == true)
    | {
        id: .key,
        name: .value.name,
        input: .value.cost.input,
        output: .value.cost.output,
        cache_read: .value.cost.cache_read,
        cache_write: .value.cost.cache_write,
        context: .value.limit.context,
        max_input: .value.limit.input,
        max_output: .value.limit.output,
        reasoning: .value.reasoning
      }
  ]
}' /tmp/models-dev.json
```

Review the extracted data before proceeding.

**models.dev caveats (learned the hard way):**

- **Provider keys:** Anthropic is `anthropic`, Gemini is `google`, OpenAI is `openai`, Moonshot is `moonshotai` (the `moonshotai-cn` variant mirrors the global catalog). Moonshot was previously omitted from this extraction even though `moonshot.lua` is a target file — don't drop it.
- **models.dev lags on retirements.** It keeps listing models with `tool_call == true` for weeks after they retire (it still listed `claude-opus-4-0` / `claude-sonnet-4-0` after their 2026-06-15 retirement). Never treat a models.dev listing as proof a model is still active — confirm against the provider's deprecation page in Phase 2.
- **Absent from models.dev ≠ retired.** Some legacy/provider-specific lines are simply not tracked (the `moonshot-v1-*` models are entirely absent yet still sold). Confirm against the provider's own docs before removing, and keep them if the docs still list them.

## Phase 2: Cross-reference provider documentation

Fetch provider docs to verify freshness, find deprecation dates, and catch models not in models.dev. Fetch order: WebFetch → `links -dump` → the site's `llms.txt` index → ask the user.

**Fetching tips (learned this session):**

- **Follow host redirects.** `docs.claude.com/*` 302-redirects to `platform.claude.com/*`, and `platform.moonshot.ai/*` 301-redirects to `platform.kimi.ai/*`. WebFetch reports the redirect target instead of following it — re-fetch the target URL. Prefer the canonical host directly, and append `.md` to any docs page for clean markdown (e.g. `…/models/overview.md`).
- **When a page is JS-rendered and the table won't extract** (WebFetch returns "links only, can't read the table", or `links -dump` comes back empty), fetch the site's **`llms.txt`** index — e.g. `https://platform.kimi.ai/docs/llms.txt`. It lists the `.md` URL for every doc page; fetch those `.md` pages directly to get the raw pricing tables. This is how the Kimi pricing tables were recovered when the rendered pages were unreadable.

### Anthropic Claude

(Canonical host is `platform.claude.com`; the `docs.claude.com` URLs redirect there. The `.md` suffix returns clean markdown.)

- https://platform.claude.com/docs/en/about-claude/models/overview.md
- https://platform.claude.com/docs/en/pricing.md
- https://platform.claude.com/docs/en/about-claude/model-deprecations.md — the **authoritative** retirement source. Its "Model status" table marks each model Active / Deprecated / Retired; drop anything marked Retired (or past its retirement date) even if models.dev still lists it.

### Google Gemini (via Vertex AI)

- https://cloud.google.com/vertex-ai/generative-ai/docs/learn/model-versions
- https://cloud.google.com/vertex-ai/generative-ai/docs/provisioned-throughput/supported-models
- https://cloud.google.com/vertex-ai/generative-ai/pricing

### OpenAI

- https://platform.openai.com/docs/pricing?latest-pricing=standard
- https://platform.openai.com/docs/deprecations
- https://platform.openai.com/docs/models — scan "Frontier models" section and follow links for the full list.

### Moonshot AI (Kimi)

Docs live at `platform.kimi.ai` (the old `platform.moonshot.ai` redirects there). The pages are JS-rendered, so go through the `llms.txt` index and fetch the `.md` URLs it lists:

- https://platform.kimi.ai/docs/llms.txt — index; the current pricing/model `.md` URLs are here (they change as the lineup evolves, e.g. `pricing/chat-k27-code.md`, `pricing/chat-k26.md`, `pricing/chat-v1.md`)
- https://platform.kimi.ai/docs/models.md — current chat model list (context window, thinking toggle)
- https://platform.kimi.ai/docs/pricing/chat.md — pricing index linking the per-tier pages

Mapping notes: pricing tables read **"Input (Cache Hit)" → `cache_read`** and **"Input (Cache Miss)" → `input`**; Moonshot uses automatic caching with **no `cache_write`**. The K2 family (`kimi-k2.5` / `k2.6` / `k2.7*`) takes `meta = { thinking_mode = "optional" }` (toggleable thinking — see `lua/flemma/provider/adapters/moonshot.lua` for the accepted modes); legacy `moonshot-v1-*` models have no thinking and uniform pricing (`cache_read == input`). Exclude `*-vision-preview` variants (non-text).

**IMPORTANT!** Some providers (notably OpenAI) block AI-agent web fetchers. If WebFetch returns a 403, a bot-detection challenge, or empty content — fall back to the `links` text-mode browser:

```bash
links -dump 'https://example.com/page'
```

## Phase 3: Apply hardcoded overrides

These values come from provider documentation and API error messages, NOT from models.dev. Apply them after merging the API data.

### Thinking budgets

| Provider  | Model family           | minimal | low  | medium | high  | min  | max                          |
| --------- | ---------------------- | ------- | ---- | ------ | ----- | ---- | ---------------------------- |
| Anthropic | All thinking models    | 1024    | 2048 | 8192   | 16384 | 1024 | (max_tokens - 1)             |
| Vertex    | gemini-2.5-pro         | 128     | 2048 | 8192   | 32768 | 1    | 32768                        |
| Vertex    | gemini-2.5-flash       | 128     | 2048 | 8192   | 24576 | 1    | 24576                        |
| Vertex    | gemini-2.5-flash-lite  | 512     | 2048 | 8192   | 24576 | 512  | 24576                        |
| Vertex    | gemini-3-flash-preview | 128     | 2048 | 8192   | 24576 | 1    | 24576                        |
| Vertex    | gemini-3-pro-preview   | 128     | 2048 | 8192   | 32768 | 1    | 32768                        |
| Vertex    | gemini-3.1-pro-preview | 128     | 2048 | 8192   | 32768 | 1    | 32768                        |
| Vertex    | gemini-2.0-flash\*     | —       | —    | —      | —     | —    | — (no thinking)              |
| OpenAI    | o-series / gpt-5\*     | —       | —    | —      | —     | —    | — (effort-based, not budget) |

### Thinking effort maps

Models that use effort/level-based thinking (not budget-based) need a `thinking_effort_map` field that maps Flemma's canonical levels (`minimal`, `low`, `medium`, `high`, `max`) to the provider's accepted API values. Discover valid values from two sources:

#### Source 1: Pi source code (ground truth)

Clone the Pi mono-repo if it doesn't already exist:

```bash
[ -d contrib/pi-mono.git ] || git clone --depth 1 https://github.com/badlogic/pi-mono.git contrib/pi-mono.git
```

Launch a sub-agent to search `contrib/pi-mono.git` for how Pi maps thinking/reasoning levels internally. Look for effort maps, thinking level enums, reasoning effort tables, and per-model level restrictions. Report back the exact mappings Pi uses for each model family across all three providers.

#### Source 2: Provider documentation

Cross-reference the Pi findings with provider docs:

- **OpenAI**: Check the reasoning effort docs for each model family — which values (`minimal`, `low`, `medium`, `high`, `xhigh`) each model accepts. Map Flemma levels to valid API values, clamping unsupported ones to the nearest valid value.
- **Anthropic**: Models with adaptive thinking (`thinking.type = "adaptive"`) need a map + `meta = { adaptive_thinking = true }`. Check which effort levels each model accepts (e.g., `max` may be restricted to certain models). Models using only budget-based thinking do not need a map.
- **Vertex**: Gemini models using `thinkingLevel` (discrete enum like `MINIMAL`, `LOW`, `MEDIUM`, `HIGH`) need a map. Check which enum values each model family supports — some may lack `MINIMAL` or `MEDIUM`. Budget-based models (`thinkingBudget`) do not need a map.

#### Rules

- Budget-only models (no effort/level API parameter) should NOT have `thinking_effort_map`.
- When Pi and provider docs disagree, prefer the provider docs (Pi may lag behind API changes).
- When provider docs are ambiguous or silent, Pi's mappings are authoritative.

### Cache minimums (Anthropic only)

| Model                   | min_cache_tokens |
| ----------------------- | ---------------- |
| claude-3-haiku-20240307 | 1024             |
| claude-haiku-4-5\*      | 4096             |
| claude-sonnet-\*        | 2048             |
| claude-opus-\*          | 2048             |

### OpenAI reasoning effort

Models with `meta = { reasoning_effort = true }`:

- All gpt-5.x models (except gpt-5-pro variants)
- o1, o3, o3-mini, o4-mini, o4-mini-deep-research, o3-deep-research

### Per-model cache pricing is mandatory

**Every model MUST have an explicit `cache_read` value in its pricing block.** The cost calculation code falls back to the full input price when `cache_read` is absent, which would overcharge for cached reads. When a provider pricing page shows "-" (no cache discount) for a model, set `cache_read` equal to the input price (1× = no discount).

For Anthropic models, also set `cache_write` (the short/5-minute TTL price). The code automatically adjusts for long retention.

For Vertex models, `cache_read` is typically 10% of the input price (implicit caching discount).

## Phase 4: Update per-provider model files

Update each file under `lua/flemma/models/` with the merged data. Follow the existing structure exactly:

- Preserve the file header comment block unchanged
- Group models by family with comments
- Include deprecation/retirement comments where applicable
- **Mirror the prior version for same-surface successors.** When the provider's migration guide says a new model keeps the previous version's request surface (e.g. "Opus 4.8 keeps the same request surface as 4.7 — no new breaking changes"), copy the previous model's entry and change only the id, pricing, and limits. Don't re-derive `thinking_budgets` / `thinking_effort_map` / `min_cache_tokens` / `meta` from scratch.
- Today's date is !`date +%Y-%m-%d` — use this for assessing retirement dates
- **Reassess `high_cost_threshold`**: Check whether the combined (input + output) price boundary still sits in a natural gap. The threshold lives in `lua/flemma/config/schema.lua` under `pricing.high_cost_threshold` (currently `30`), with strict `>` so Claude Opus itself doesn't warn. If Opus pricing changes or the gap shifts, update the default value in the schema.

## Rules

- **Every addition, removal, or price change must be traceable** to the models.dev API or a specific line on a listed provider page.
- Do NOT use WebSearch at any point.
- Do NOT use training data to add, remove, or price models.
- If a model appears on these sources, it goes in. If it doesn't, it stays out.
- If a model is retired or past its deprecation date, drop it.
- If a model is deprecated but not yet retired, keep it with a retirement date comment.
- If a model is absent from models.dev but still listed on the provider's own docs, keep it — models.dev does not track every legacy line (e.g. `moonshot-v1-*`). Only when a model is absent from **all** sources should you ask the user before removing it.
- **A models.dev listing is not proof a model is live.** Confirm retirement against the provider's deprecation page, not models.dev (which lags). Conversely, confirm a models.dev _absence_ against the provider docs before removing.
- If any model names imply non-text capabilities (vision, image, video, audio, tts, embedding, moderation), exclude them.

## Special Handling for New Sonnet Versions

If you discover a newer Sonnet version during the update, scan the codebase for references to the previous Sonnet version and update them accordingly. Search with a flexible pattern like `/sonnet.?4(.?0)?/i`.

## Workflow

1. **Fetch models.dev API** and extract data via jq.
2. **Fetch provider docs** for cross-referencing.
3. **Merge data**, applying hardcoded overrides.
4. **Update per-provider files** under `lua/flemma/models/`.
5. **Run `make qa`** to check for tests that may reference retired models.
