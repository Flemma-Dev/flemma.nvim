--- Late-binding dispatch for breaking circular require dependencies.
---
--- Modules that form a require cycle register their functions here at load
--- time. Callers on the other side of the cycle dispatch through the bridge
--- instead of requiring the owning module directly.
---
--- Only use this when a direct require would create a circular dependency.
--- For everything else, require the owning module directly.
---
--- Registrants: flemma.core, flemma.buffer.editing
--- Callers:     flemma.autopilot, flemma.tools.executor, flemma.ui,
---              flemma.provider.adapters.anthropic
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

return M
