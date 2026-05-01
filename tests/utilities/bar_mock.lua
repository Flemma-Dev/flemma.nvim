--- Reusable mock for flemma.ui.bar, injectable via package.loaded.
--- Records constructor options and every method call so driver tests can
--- assert on the wire without opening real floating windows.
---@class tests.utilities.BarMock
local M = {}

---@class tests.utilities.BarMock.Handle
---@field opts table Constructor opts as received
---@field calls { method: string, args: any[] }[] Recorded method calls
---@field dismissed boolean
---@field _shown boolean
---@field on_shown? fun()
---@field on_dismiss? fun()

---@class tests.utilities.BarMock.Module
---@field new fun(opts: table): tests.utilities.BarMock.Handle
---@field _handles tests.utilities.BarMock.Handle[]
---@field _last tests.utilities.BarMock.Handle|nil
---@field fire_on_shown fun(handle: tests.utilities.BarMock.Handle)
---@field reset fun()

---Build a fresh mock module. Each `install()` call returns a new instance
---with an empty `_handles` list.
---@return tests.utilities.BarMock.Module
function M.install()
  local mod = {
    _handles = {},
    _last = nil,
  }

  local function record(handle, method, args)
    if handle.dismissed then
      return handle
    end
    table.insert(handle.calls, { method = method, args = args })
    return handle
  end

  ---@param opts table
  function mod.new(opts)
    ---@type tests.utilities.BarMock.Handle
    local handle = {
      opts = opts,
      calls = {},
      dismissed = false,
      _shown = false,
      on_shown = opts.on_shown,
      on_dismiss = opts.on_dismiss,
    }

    function handle:set_icon(icon)
      return record(self, "set_icon", { icon })
    end
    function handle:set_segments(segments)
      return record(self, "set_segments", { segments })
    end
    function handle:set_highlight(hl)
      return record(self, "set_highlight", { hl })
    end
    function handle:update(partial)
      return record(self, "update", { partial })
    end
    function handle:dismiss()
      if self.dismissed then
        return self
      end
      table.insert(self.calls, { method = "dismiss", args = {} })
      self.dismissed = true
      if self.on_dismiss then
        pcall(self.on_dismiss)
      end
      return self
    end
    function handle:is_dismissed()
      return self.dismissed
    end

    table.insert(mod._handles, handle)
    mod._last = handle
    return handle
  end

  ---Simulate the `on_shown` callback firing (the real Bar fires this
  ---the first time a float opens). Tests call this explicitly to drive
  ---the driver's deferred timer-start logic.
  ---@param handle tests.utilities.BarMock.Handle
  function mod.fire_on_shown(handle)
    if handle._shown then
      return
    end
    handle._shown = true
    if handle.on_shown then
      handle.on_shown()
    end
  end

  function mod.reset()
    mod._handles = {}
    mod._last = nil
  end

  return mod
end

---Convenience: install into package.loaded so `require("flemma.ui.bar")`
---returns the mock inside a test. Returns the mock module for assertions.
---Callers are responsible for clearing package.loaded in before_each.
---@return tests.utilities.BarMock.Module
function M.install_as_flemma_ui_bar()
  local mod = M.install()
  package.loaded["flemma.ui.bar"] = mod
  return mod
end

return M
