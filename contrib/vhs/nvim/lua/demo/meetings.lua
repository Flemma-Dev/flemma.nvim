--- Demo meeting-transcript tool for the VHS hero screencast.
---
--- Registers `meetings.get_transcript`, an async tool that always returns the
--- same canned standup transcript after a short, deterministic delay. It stands
--- in for a real calendar / notes integration so the screencast renders an
--- identical tool call every take, while the model's output stays live. Loaded
--- via the demo Flemma config's `tools.modules = { "demo.meetings" }` (resolves
--- because `contrib/vhs` is the screencast's `XDG_CONFIG_HOME`).
---
--- Mirrors the async pattern of `extras.flemma.tools.calculator`'s
--- `calculator_async` — a `vim.uv` timer drives the callback and the returned
--- cancel function stops the timer.
---@class demo.meetings
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

--- Deterministic execution delay, in milliseconds. Long enough for the
--- "Executing…" spinner to read on screen, short enough to keep the demo brisk.
---@type integer
local DELAY_MS = 4000

--- Load the canned transcript that ships next to the demo tape.
---
--- Resolved relative to this module (`contrib/vhs/nvim/lua/demo/meetings.lua` →
--- `contrib/vhs/northwind-standup.txt`), not the editor's cwd, because the tape
--- records from `.vapor/northwind`.
---@return string transcript The full meeting transcript text.
local function load_transcript()
  local source = debug.getinfo(1, "S").source:sub(2)
  -- .../contrib/vhs/nvim/lua/demo/meetings.lua → .../contrib/vhs
  local base_dir = vim.fn.fnamemodify(source, ":p:h:h:h:h")
  local path = base_dir .. "/northwind-standup.txt"
  return table.concat(vim.fn.readfile(path), "\n")
end

--- The canned transcript, read once at load — the tool is deterministic.
---@type string
local TRANSCRIPT = load_transcript()

M.definitions = {
  {
    name = "meetings.get_transcript",
    description = "Fetches the transcript of a team meeting for a given date. "
      .. "Returns the full verbatim transcript, including timestamps and speaker labels.",
    input_schema = {
      type = "object",
      properties = {
        date = {
          type = "string",
          description = "The meeting date to fetch. Accepts an ISO 8601 date "
            .. "(e.g. '2026-06-09') or a relative expression (e.g. 'last Friday', 'yesterday').",
        },
      },
      required = { "date" },
      additionalProperties = false,
    },
    async = true,
    ---@param input table<string, any>
    ---@return flemma.StructuredToolPreview
    format_preview = function(input)
      return {
        label = "meeting transcript",
        detail = input.date,
      }
    end,
    ---@param input table<string, any>
    ---@param _ flemma.tools.ExecutionContext
    ---@param callback fun(result: flemma.tools.ExecutionResult)
    ---@return fun()|nil cancel
    execute = function(input, _, callback)
      ---@cast callback -nil
      local timer = vim.uv.new_timer()
      if not timer then
        callback({ success = true, output = TRANSCRIPT })
        return nil
      end
      timer:start(DELAY_MS, 0, function()
        timer:stop()
        timer:close()
        callback({ success = true, output = TRANSCRIPT })
      end)
      return function()
        timer:stop()
        timer:close()
      end
    end,
  },
}

return M
