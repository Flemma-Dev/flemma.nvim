--- Parameter normalization for provider construction.
--- Consolidates flatten, max_tokens resolution, and thinking resolution
--- into a single module. All functions are pure — no instance state.
---@class flemma.provider.Normalize
local M = {}

local log = require("flemma.logging")
local notify = require("flemma.notify")
local presets = require("flemma.presets")
local registry = require("flemma.provider.registry")

local FALLBACK_MAX_TOKENS = 4000
local MIN_MAX_TOKENS = 1024

-- ============================================================================
-- resolve_preset
-- ============================================================================

---Resolve a model preset reference in a materialized config.
---If config.model starts with "$", looks up the preset and returns a modified
---copy with the resolved provider, model, and merged parameters. Returns the
---original config unmodified when no preset reference is found or lookup fails.
---@param config table Materialized config (NOT mutated)
---@return table config Resolved config (may be a shallow copy)
function M.resolve_preset(config)
  if type(config.model) ~= "string" or not vim.startswith(config.model, "$") then
    return config
  end
  local preset = presets.get(config.model)
  if not preset then
    return config
  end
  local resolved = vim.tbl_deep_extend("force", config, {
    provider = preset.provider,
    model = preset.model,
  })
  if preset.parameters and next(preset.parameters) then
    resolved.parameters = vim.tbl_deep_extend("force", resolved.parameters or {}, preset.parameters)
  end
  return resolved
end

-- ============================================================================
-- merge_parameters
-- ============================================================================

---Merge provider parameters from a materialized config into a single table.
---Copies general parameters from `config.parameters` (skipping provider
---sub-tables identified via registry), overlays provider-specific parameters
---from `config.parameters[provider_name]` with deep merge for table values,
---and adds `model`.
---@param provider_name string Resolved provider name
---@param config table Materialized config from config_facade.materialize()
---@return table<string, any> flat Merged parameter table for provider.new()
function M.merge_parameters(provider_name, config)
  local flat = {}
  local params = config.parameters or {}
  -- Copy general parameters (skip provider sub-tables)
  for k, v in pairs(params) do
    if not registry.has(k) then
      flat[k] = v
    end
  end
  -- Overlay provider-specific parameters (highest specificity wins)
  local specific = params[provider_name]
  if type(specific) == "table" then
    for k, v in pairs(specific) do
      if type(v) == "table" and type(flat[k]) == "table" then
        flat[k] = vim.tbl_deep_extend("force", flat[k], v)
      else
        flat[k] = v
      end
    end
  end
  flat.model = config.model
  return flat
end

-- ============================================================================
-- resolve_max_tokens
-- ============================================================================

---Resolve percentage-based or over-limit max_tokens to an integer.
---Mutates parameters.max_tokens in place.
---@param provider_name string
---@param model_name string
---@param parameters table<string, any>
function M.resolve_max_tokens(provider_name, model_name, parameters)
  local value = parameters.max_tokens
  if value == nil then
    return
  end

  if type(value) == "string" then
    local pct_str = value:match("^(%d+)%%$")
    if pct_str then
      local pct = tonumber(pct_str)
      local model_info = registry.get_model_info(provider_name, model_name)
      if model_info and model_info.max_output_tokens then
        local resolved = math.floor(model_info.max_output_tokens * pct / 100)
        local floor = math.max(MIN_MAX_TOKENS, model_info.min_output_tokens or 0)
        parameters.max_tokens = math.max(resolved, floor)
        log.debug(
          "resolve_max_tokens(): "
            .. value
            .. " of "
            .. tostring(model_info.max_output_tokens)
            .. " → "
            .. tostring(parameters.max_tokens)
        )
      else
        parameters.max_tokens = FALLBACK_MAX_TOKENS
        log.debug(
          "resolve_max_tokens(): No model data for "
            .. provider_name
            .. "/"
            .. model_name
            .. ", falling back to "
            .. tostring(FALLBACK_MAX_TOKENS)
        )
      end
    else
      parameters.max_tokens = FALLBACK_MAX_TOKENS
      log.warn(
        "resolve_max_tokens(): Invalid max_tokens string '"
          .. value
          .. "', falling back to "
          .. tostring(FALLBACK_MAX_TOKENS)
      )
    end
    return
  end

  if type(value) == "number" then
    local model_info = registry.get_model_info(provider_name, model_name)
    if model_info then
      local max = model_info.max_output_tokens
      local min = model_info.min_output_tokens
      if max and value > max then
        notify.warn(string.format("max_tokens %d exceeds %s limit (%d), clamping.", value, model_name, max))
        parameters.max_tokens = max
      elseif min and value < min then
        notify.warn(string.format("max_tokens %d below %s minimum (%d), raising.", value, model_name, min))
        parameters.max_tokens = min
      end
    end
  end
end

-- ============================================================================
-- resolve_thinking
-- ============================================================================

---@class flemma.provider.ThinkingResolution
---@field enabled boolean Whether thinking/reasoning is active
---@field explicit? boolean True when the user explicitly disabled thinking (false/0), absent when thinking was simply not configured
---@field budget? integer Token budget for budget-based providers (Anthropic, Vertex)
---@field effort? string Effort level for effort-based providers (OpenAI): "minimal"|"low"|"medium"|"high"|"max"
---@field level? string Canonical Flemma level: "minimal"|"low"|"medium"|"high"|"max" (always set when enabled)
---@field mapped_effort? string Provider-specific API value from thinking_effort_map (nil when model has no map)
---@field foreign "preserve"|"drop" Whether to include foreign thinking blocks in requests

--- Map a numeric budget to the closest named effort level
---@param budget number
---@return string effort "minimal"|"low"|"medium"|"high"|"max"
local function budget_to_effort(budget)
  if budget <= 256 then
    return "minimal"
  elseif budget <= 4096 then
    return "low"
  elseif budget <= 12288 then
    return "medium"
  elseif budget <= 24576 then
    return "high"
  else
    return "max"
  end
end

--- Map a named effort level to a thinking budget, using per-model data when available
---@param level string "minimal"|"low"|"medium"|"high"|"max"
---@param model_info? flemma.models.ModelInfo
---@return integer budget
local function effort_to_budget(level, model_info)
  if model_info and model_info.thinking_budgets then
    ---@cast model_info -nil
    local budgets = model_info.thinking_budgets --[[@as table<string, integer>]]
    if level == "max" then
      if model_info.max_thinking_budget then
        return model_info.max_thinking_budget
      end
      return budgets.high or 32768
    end
    local model_budget = budgets[level]
    if model_budget then
      return model_budget
    end
  end
  -- Hardcoded fallback (current behavior)
  if level == "minimal" then
    return 128
  elseif level == "low" then
    return 2048
  elseif level == "medium" then
    return 8192
  elseif level == "high" then
    return 16384
  else -- "max"
    return 32768
  end
end

--- Map an effort level through model_info.thinking_effort_map, returning nil
--- when the model has no effort map. Providers use this to decide whether to
--- use effort-based or budget-based API parameters.
---@param level string The canonical Flemma effort level
---@param model_info? flemma.models.ModelInfo
---@return string|nil mapped Provider API value, or nil when no map exists
local function map_effort_from_model(level, model_info)
  if not model_info or not model_info.thinking_effort_map then
    return nil
  end
  return model_info.thinking_effort_map[level]
end

--- Map an effort level through model_info.thinking_effort_map if available.
--- Falls back to the input level when no map exists.
---@param effort string The canonical Flemma effort level
---@param model_info? flemma.models.ModelInfo
---@return string mapped_effort The provider-specific API value
local function map_effort(effort, model_info)
  return map_effort_from_model(effort, model_info) or effort
end

--- Resolve the unified `thinking` parameter into provider-appropriate values.
---
--- Priority: provider-specific param > thinking > provider defaults.
--- For budget-based providers (Anthropic, Vertex), resolves to a token budget.
--- For effort-based providers (OpenAI), resolves to an effort level string.
---
---@param params flemma.provider.Parameters The parameter proxy
---@param caps flemma.provider.Capabilities The provider's capabilities
---@param model_info? flemma.models.ModelInfo Per-model metadata for budget/clamping
---@return flemma.provider.ThinkingResolution
function M.resolve_thinking(params, caps, model_info)
  local thinking_table = params.thinking
  ---@type "preserve"|"drop"
  local foreign
  if thinking_table and thinking_table.foreign then
    foreign = thinking_table.foreign
  else
    foreign = "preserve"
  end

  -- For budget-based providers (Anthropic, Vertex)
  if caps.supports_thinking_budget then
    local min = (model_info and model_info.min_thinking_budget) or caps.min_thinking_budget or 1
    local max = model_info and model_info.max_thinking_budget

    -- Priority: provider-specific thinking_budget > unified thinking
    local raw_budget = params.thinking_budget
    if raw_budget ~= nil then
      if type(raw_budget) == "number" and raw_budget > 0 then
        local budget = math.max(math.floor(raw_budget), min)
        if max then
          budget = math.min(budget, max)
        end
        local level = budget_to_effort(budget)
        return {
          enabled = true,
          budget = budget,
          level = level,
          mapped_effort = map_effort_from_model(level, model_info),
          foreign = foreign,
        }
      else
        return { enabled = false, foreign = foreign }
      end
    end

    -- Fall back to unified `thinking` parameter
    -- Use explicit if/else because `thinking_table.level` can be `false`,
    -- which breaks the `a and b or c` ternary idiom.
    local thinking
    if thinking_table then
      thinking = thinking_table.level
    end
    if thinking == nil or thinking == false or thinking == 0 then
      return { enabled = false, foreign = foreign }
    end
    if type(thinking) == "string" then
      local budget = math.max(effort_to_budget(thinking, model_info), min)
      if max then
        budget = math.min(budget, max)
      end
      -- Preserve the original string as level (avoid budget_to_effort roundtrip
      -- which loses precision, e.g., "max" → budget 24576 → "high").
      return {
        enabled = true,
        budget = budget,
        level = thinking,
        mapped_effort = map_effort_from_model(thinking, model_info),
        foreign = foreign,
      }
    end
    if type(thinking) == "number" and thinking > 0 then
      local budget = math.max(math.floor(thinking), min)
      if max then
        budget = math.min(budget, max)
      end
      local level = budget_to_effort(budget)
      local mapped_effort = map_effort_from_model(level, model_info)
      return { enabled = true, budget = budget, level = level, mapped_effort = mapped_effort, foreign = foreign }
    end
    return { enabled = false, foreign = foreign }
  end

  -- For effort-based providers (OpenAI)
  if caps.supports_reasoning then
    -- Priority: provider-specific reasoning > unified thinking
    local raw_reasoning = params.reasoning
    if raw_reasoning ~= nil and raw_reasoning ~= "" then
      local mapped = map_effort(raw_reasoning, model_info)
      return { enabled = true, effort = mapped, level = raw_reasoning, foreign = foreign }
    end

    -- Fall back to unified `thinking` parameter
    -- Use explicit if/else because `thinking_table.level` can be `false`,
    -- which breaks the `a and b or c` ternary idiom.
    local thinking
    if thinking_table then
      thinking = thinking_table.level
    end
    if thinking == nil then
      return { enabled = false, foreign = foreign }
    end
    if thinking == false or thinking == 0 then
      return { enabled = false, explicit = true, foreign = foreign }
    end
    if type(thinking) == "string" then
      local mapped = map_effort(thinking, model_info)
      return { enabled = true, effort = mapped, level = thinking, foreign = foreign }
    end
    if type(thinking) == "number" and thinking > 0 then
      local canonical = budget_to_effort(thinking)
      local mapped = map_effort(canonical, model_info)
      return { enabled = true, effort = mapped, level = canonical, foreign = foreign }
    end
    return { enabled = false, foreign = foreign }
  end

  -- Provider supports neither
  return { enabled = false, foreign = foreign }
end

return M
