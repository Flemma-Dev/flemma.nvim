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
  ]
}' /tmp/models-dev.json
```

Review the extracted data before proceeding.

## Phase 2: Cross-reference provider documentation

Fetch provider docs to verify freshness, find deprecation dates, and catch models not in models.dev. Use WebFetch first, then `links -dump` as fallback, then ask the user.

### Anthropic Claude

- https://docs.claude.com/en/docs/about-claude/models/overview
- https://docs.claude.com/en/docs/about-claude/pricing
- https://docs.claude.com/en/docs/about-claude/model-deprecations

### Google Gemini (via Vertex AI)

- https://cloud.google.com/vertex-ai/generative-ai/docs/learn/model-versions
- https://cloud.google.com/vertex-ai/generative-ai/docs/provisioned-throughput/supported-models
- https://cloud.google.com/vertex-ai/generative-ai/pricing

### OpenAI

- https://platform.openai.com/docs/pricing?latest-pricing=standard
- https://platform.openai.com/docs/deprecations
- https://platform.openai.com/docs/models — scan "Frontier models" section and follow links for the full list.

**IMPORTANT!** Some providers (notably OpenAI) block AI-agent web fetchers. If WebFetch returns a 403, a bot-detection challenge, or empty content — fall back to the `links` text-mode browser:

```bash
links -dump 'https://example.com/page'
```

## Phase 3: Apply hardcoded overrides

These values come from provider documentation and API error messages, NOT from models.dev. Apply them after merging the API data.

### Thinking budgets

| Provider | Model family | minimal | low | medium | high | min | max |
|----------|-------------|---------|-----|--------|------|-----|-----|
| Anthropic | All thinking models | 1024 | 2048 | 8192 | 16384 | 1024 | (max_tokens - 1) |
| Vertex | gemini-2.5-pro | 128 | 2048 | 8192 | 32768 | 1 | 32768 |
| Vertex | gemini-2.5-flash | 128 | 2048 | 8192 | 24576 | 1 | 24576 |
| Vertex | gemini-2.5-flash-lite | 512 | 2048 | 8192 | 24576 | 512 | 24576 |
| Vertex | gemini-3-flash-preview | 128 | 2048 | 8192 | 24576 | 1 | 24576 |
| Vertex | gemini-3-pro-preview | 128 | 2048 | 8192 | 32768 | 1 | 32768 |
| Vertex | gemini-3.1-pro-preview | 128 | 2048 | 8192 | 32768 | 1 | 32768 |
| Vertex | gemini-2.0-flash* | — | — | — | — | — | — (no thinking) |
| OpenAI | o-series / gpt-5* | — | — | — | — | — | — (effort-based, not budget) |

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
- **Anthropic**: Models with adaptive thinking (`thinking.type = "adaptive"`) need a map + `supports_adaptive_thinking = true`. Check which effort levels each model accepts (e.g., `max` may be restricted to certain models). Models using only budget-based thinking do not need a map.
- **Vertex**: Gemini models using `thinkingLevel` (discrete enum like `MINIMAL`, `LOW`, `MEDIUM`, `HIGH`) need a map. Check which enum values each model family supports — some may lack `MINIMAL` or `MEDIUM`. Budget-based models (`thinkingBudget`) do not need a map.

#### Rules

- Budget-only models (no effort/level API parameter) should NOT have `thinking_effort_map`.
- When Pi and provider docs disagree, prefer the provider docs (Pi may lag behind API changes).
- When provider docs are ambiguous or silent, Pi's mappings are authoritative.

### Cache minimums (Anthropic only)

| Model | min_cache_tokens |
|-------|-----------------|
| claude-3-haiku-20240307 | 1024 |
| claude-haiku-4-5* | 4096 |
| claude-sonnet-* | 2048 |
| claude-opus-* | 2048 |

### OpenAI reasoning effort

Models with `supports_reasoning_effort = true`:
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
- Today's date is !`date +%Y-%m-%d` — use this for assessing retirement dates
- **Reassess `high_cost_threshold`**: Check whether the combined (input + output) price boundary still sits in a natural gap. The threshold lives in `lua/flemma/config/schema.lua` under `pricing.high_cost_threshold` (currently `30`), with strict `>` so Claude Opus itself doesn't warn. If Opus pricing changes or the gap shifts, update the default value in the schema.

## Rules

- **Every addition, removal, or price change must be traceable** to the models.dev API or a specific line on a listed provider page.
- Do NOT use WebSearch at any point.
- Do NOT use training data to add, remove, or price models.
- If a model appears on these sources, it goes in. If it doesn't, it stays out.
- If a model is retired or past its deprecation date, drop it.
- If a model is deprecated but not yet retired, keep it with a retirement date comment.
- If a model is in the local file but absent from all sources, ask the user before removing it.
- If any model names imply non-text capabilities (vision, image, video, audio, tts, embedding, moderation), exclude them.

## Special Handling for New Sonnet Versions

If you discover a newer Sonnet version during the update, scan the codebase for references to the previous Sonnet version and update them accordingly. Search with a flexible pattern like `/sonnet.?4(.?0)?/i`.

## Workflow

1. **Fetch models.dev API** and extract data via jq.
2. **Fetch provider docs** for cross-referencing.
3. **Merge data**, applying hardcoded overrides.
4. **Update per-provider files** under `lua/flemma/models/`.
5. **Run `make test`** to check for tests that may reference retired models.
