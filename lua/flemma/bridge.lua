--- Late-binding dispatch for breaking circular require dependencies.
---
--- Modules that form a require cycle register their functions here at load
--- time. Callers on the other side of the cycle dispatch through the bridge
--- instead of requiring the owning module directly.
---
--- Only use this when a direct require would create a circular dependency.
--- For everything else, require the owning module directly.
---
--- Registrants: flemma.core, flemma.buffer.editing, flemma.tools.executor,
---              flemma.presets (get_preset, closest_match_preset)
--- Callers:     flemma.autopilot, flemma.migration, flemma.tools.executor,
---              flemma.ui, flemma.provider.adapters.{anthropic,vertex,moonshot},
---              flemma.config.listops (get_preset, closest_match_preset)
---@class flemma.Bridge
local M = {}

---@type table<string, function>
local handlers = {}

---Register a function for late-binding dispatch.
---@param name string
---@param fn function
function M.register(name, fn)
  handlers[name] = fn
end

---@param opts { bufnr: integer }
function M.send_or_execute(opts)
  assert(handlers.send_or_execute, "bridge: send_or_execute not registered")
  handlers.send_or_execute(opts)
end

---@param bufnr integer
---@param opts? { evaluated_frontmatter?: flemma.processor.EvaluatedFrontmatter }
---@return flemma.pipeline.Prompt|nil prompt
---@return flemma.Context|nil context
---@return flemma.provider.Base|nil provider
---@return flemma.processor.EvaluatedResult|nil evaluated
---@return flemma.core.BuildPromptFailure|nil failure
function M.build_prompt_and_provider(bufnr, opts)
  assert(handlers.build_prompt_and_provider, "bridge: build_prompt_and_provider not registered")
  return handlers.build_prompt_and_provider(bufnr, opts)
end

---@param opts? { bufnr: integer }
function M.cancel_request(opts)
  assert(handlers.cancel_request, "bridge: cancel_request not registered")
  handlers.cancel_request(opts)
end

---@param bufnr integer
function M.update_ui(bufnr)
  assert(handlers.update_ui, "bridge: update_ui not registered")
  handlers.update_ui(bufnr)
end

---@param bufnr integer
function M.auto_prompt(bufnr)
  assert(handlers.auto_prompt, "bridge: auto_prompt not registered")
  handlers.auto_prompt(bufnr)
end

---@param bufnr integer
function M.drain_job_completions(bufnr)
  assert(handlers.drain_job_completions, "bridge: drain_job_completions not registered")
  handlers.drain_job_completions(bufnr)
end

---@param bufnr integer
---@return integer count
function M.resolve_orphaned_jobs(bufnr)
  assert(handlers.resolve_orphaned_jobs, "bridge: resolve_orphaned_jobs not registered")
  return handlers.resolve_orphaned_jobs(bufnr)
end

---@param name string Preset name (e.g., "$standard")
---@return flemma.presets.Preset?
function M.get_preset(name)
  assert(handlers.get_preset, "bridge: get_preset not registered")
  return handlers.get_preset(name)
end

---@param name string Preset name to match against
---@return string|nil closest The closest preset name, or nil if none is close enough
function M.closest_match_preset(name)
  assert(handlers.closest_match_preset, "bridge: closest_match_preset not registered")
  return handlers.closest_match_preset(name)
end

return M
