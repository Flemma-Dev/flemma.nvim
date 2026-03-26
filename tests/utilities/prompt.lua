---@class flemma.test.utilities.Prompt
local M = {}

--- Build a Prompt table from a simple message format.
--- Converts `{type="You", content="Hello"}` shorthand into the canonical
--- `flemma.provider.Prompt` structure that `build_request` expects.
---@param messages { type: string, content: string }[]
---@return flemma.provider.Prompt
function M.make_prompt(messages)
  local history = {}
  local system = nil
  for _, msg in ipairs(messages) do
    if msg.type == "System" then
      system = vim.trim(msg.content or "")
    end
  end
  for _, msg in ipairs(messages) do
    local role = nil
    if msg.type == "You" then
      role = "user"
    elseif msg.type == "Assistant" then
      role = "assistant"
    end
    if role then
      table.insert(history, {
        role = role,
        parts = { { kind = "text", text = vim.trim(msg.content or "") } },
      })
    end
  end
  return { history = history, system = system }
end

return M
