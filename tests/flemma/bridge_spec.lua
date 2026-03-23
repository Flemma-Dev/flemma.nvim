package.loaded["flemma.bridge"] = nil

local bridge = require("flemma.bridge")

describe("flemma.bridge", function()
  before_each(function()
    package.loaded["flemma.bridge"] = nil
    bridge = require("flemma.bridge")
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

  it("dispatches cancel_request with opts after registration", function()
    local called_opts = nil
    bridge.register("cancel_request", function(opts)
      called_opts = opts
    end)
    bridge.cancel_request({ bufnr = 99 })
    assert.are.same({ bufnr = 99 }, called_opts)
  end)

  it("dispatches update_ui after registration", function()
    local called_bufnr = nil
    bridge.register("update_ui", function(bufnr)
      called_bufnr = bufnr
    end)
    bridge.update_ui(7)
    assert.are.equal(7, called_bufnr)
  end)

  it("dispatches auto_prompt after registration", function()
    local called_bufnr = nil
    bridge.register("auto_prompt", function(bufnr)
      called_bufnr = bufnr
    end)
    bridge.auto_prompt(5)
    assert.are.equal(5, called_bufnr)
  end)
end)
