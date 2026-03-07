---
description: Update models and pricing in models.lua using models.dev API and provider documentation
disable-model-invocation: true
---

# Update Models and Pricing

Update the following file (and only this file!): `lua/flemma/models.lua` — with up-to-date information about the models and pricing of Google Gemini (via Vertex AI), Anthropic Claude, and OpenAI.

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

### Provider-level cache multipliers

Keep these on the provider blocks (NOT per-model):
- Anthropic: `cache_read_multiplier = 0.1`, `cache_write_multipliers = { short = 1.25, long = 2.0 }`
- Vertex: `cache_read_multiplier = 0.1` (implicit caching, no per-model cache pricing)
- OpenAI: `cache_read_multiplier = 0.5`

### Per-model cache_read is mandatory (OpenAI)

**Every OpenAI model MUST have an explicit `cache_read` value in its pricing block.** When a provider pricing page shows "-" (no cache discount) for a model, set `cache_read` equal to the input price (1x = no discount). Do NOT omit `cache_read` — the cost calculation code falls back to the provider-level `cache_read_multiplier` (0.5) when per-model `cache_read` is absent, which would incorrectly halve the cache read cost for models that have no discount.

## Phase 4: Generate models.lua

Update `lua/flemma/models.lua` with the merged data. Follow the existing structure exactly:

- Preserve the file header comment block and type annotations unchanged
- Group models by family with comments
- Include deprecation/retirement comments where applicable
- Today's date is !`date +%Y-%m-%d` — use this for assessing retirement dates

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
4. **Update `lua/flemma/models.lua`**.
5. **Run `make test`** to check for tests that may reference retired models.
