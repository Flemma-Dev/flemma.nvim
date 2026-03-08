package.loaded["flemma.core.bridge"] = nil

local bridge = require("flemma.core.bridge")

describe("flemma.core.bridge", function()
  before_each(function()
    package.loaded["flemma.core.bridge"] = nil
    bridge = require("flemma.core.bridge")
  end)

  it("raises error when calling unregistered callback", function()
    assert.has_error(function()
      bridge.send_or_execute({ bufnr = 1 })
    end)
  end)

  it("dispatches send_or_execute after registration", function()
    local called_with = nil
    bridge.register("send_or_execute", function(opts)
      called_with = opts
    end)
    bridge.send_or_execute({ bufnr = 42 })
    assert.are.same({ bufnr = 42 }, called_with)
  end)

  it("dispatches cancel_request after registration", function()
    local called = false
    bridge.register("cancel_request", function()
      called = true
    end)
    bridge.cancel_request()
    assert.is_true(called)
  end)

  it("dispatches update_ui after registration", function()
    local called_bufnr = nil
    bridge.register("update_ui", function(bufnr)
      called_bufnr = bufnr
    end)
    bridge.update_ui(7)
    assert.are.equal(7, called_bufnr)
  end)
end)
