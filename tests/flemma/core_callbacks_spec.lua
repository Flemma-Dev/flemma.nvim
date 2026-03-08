package.loaded["flemma.core.callbacks"] = nil

local callbacks = require("flemma.core.callbacks")

describe("flemma.core.callbacks", function()
  before_each(function()
    package.loaded["flemma.core.callbacks"] = nil
    callbacks = require("flemma.core.callbacks")
  end)

  it("raises error when calling unregistered callback", function()
    assert.has_error(function()
      callbacks.send_or_execute({ bufnr = 1 })
    end)
  end)

  it("dispatches send_or_execute after registration", function()
    local called_with = nil
    callbacks.register("send_or_execute", function(opts)
      called_with = opts
    end)
    callbacks.send_or_execute({ bufnr = 42 })
    assert.are.same({ bufnr = 42 }, called_with)
  end)

  it("dispatches cancel_request after registration", function()
    local called = false
    callbacks.register("cancel_request", function()
      called = true
    end)
    callbacks.cancel_request()
    assert.is_true(called)
  end)

  it("dispatches update_ui after registration", function()
    local called_bufnr = nil
    callbacks.register("update_ui", function(bufnr)
      called_bufnr = bufnr
    end)
    callbacks.update_ui(7)
    assert.are.equal(7, called_bufnr)
  end)
end)
