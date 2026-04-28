local notify = require("flemma.notify")

describe("core.send_to_provider suspense handling", function()
  local readiness, state, secrets_cache

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.commands"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.readiness"] = nil
    package.loaded["flemma.secrets"] = nil
    package.loaded["flemma.secrets.cache"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil

    local flemma = require("flemma")
    flemma.setup({ parameters = { thinking = false } })

    readiness = require("flemma.readiness")
    state = require("flemma.state")
    secrets_cache = require("flemma.secrets.cache")

    readiness._reset_for_tests()
    secrets_cache.invalidate_all()
  end)

  after_each(function()
    notify._reset_impl()
    require("flemma.client").clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  it("re-raises suspense from get_api_key past the prep pcall", function()
    local boundary = readiness.get_or_create_boundary("test:suspense", function(done)
      done()
    end)
    local raised = false
    local ok, err = pcall(function()
      local prep_ok, prep_result = pcall(function()
        error(readiness.Suspense.new("test", boundary))
      end)
      if not prep_ok then
        if readiness.is_suspense(prep_result) then
          raised = true
          error(prep_result)
        end
        error(prep_result)
      end
    end)
    assert.is_true(raised)
    assert.is_false(ok)
    assert.is_true(readiness.is_suspense(err))
  end)

  it("queues send behind suspense when credentials are uncached", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })
    vim.bo[bufnr].filetype = "chat"

    notify._set_impl(function(n)
      return n
    end)

    require("flemma.core").send_to_provider()

    local buffer_state = state.get_buffer_state(bufnr)
    assert.is_not_nil(buffer_state.pending_send, "expected pending_send to be set after suspense")
    assert.is_not_nil(buffer_state.pending_send.subscription, "expected subscription on pending_send")
  end)

  it("cancels pending_send on Ctrl+C", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })
    vim.bo[bufnr].filetype = "chat"

    notify._set_impl(function(n)
      return n
    end)
    require("flemma.core").send_to_provider()

    local buffer_state = state.get_buffer_state(bufnr)
    assert.is_not_nil(buffer_state.pending_send)
    local sub = buffer_state.pending_send.subscription

    require("flemma.core").cancel_request({ bufnr = bufnr })

    assert.is_nil(buffer_state.pending_send)
    assert.is_true(sub.cancelled)
    assert.is_false(buffer_state.locked)
  end)

  it("cleans up pending_send via cleanup_buffer_state", function()
    require("flemma.core")

    local bufnr = vim.api.nvim_create_buf(false, false)
    state.get_buffer_state(bufnr)

    local boundary = readiness.get_or_create_boundary("test:wipe", function() end)
    local sub = boundary:subscribe(function() end)
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_send = { subscription = sub, opts = {} }

    state.cleanup_buffer_state(bufnr)

    assert.is_true(sub.cancelled)
  end)
end)
