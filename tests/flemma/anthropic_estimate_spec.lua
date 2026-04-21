--- Tests for :Flemma usage:estimate (Anthropic adapter's try_estimate_usage)

local notify = require("flemma.notify")

describe("anthropic.try_estimate_usage", function()
  local client = require("flemma.client")
  local flemma, anthropic
  local captured

  before_each(function()
    -- Force a fresh setup so each test starts from known defaults.
    package.loaded["flemma"] = nil
    package.loaded["flemma.commands"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil

    flemma = require("flemma")
    anthropic = require("flemma.provider.adapters.anthropic")

    flemma.setup({ parameters = { thinking = false } })

    captured = {}
    notify._set_impl(function(notification)
      table.insert(captured, notification)
      return notification
    end)
  end)

  after_each(function()
    notify._reset_impl()
    client.clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  ---Create a chat buffer seeded with a minimal user message.
  ---@param lines? string[]
  ---@return integer bufnr
  local function make_chat_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { "@You:", "Hello" })
    return bufnr
  end

  ---Poll captured notifications for one matching the predicate.
  ---@param predicate fun(n: flemma.notify.Notification): boolean
  ---@return flemma.notify.Notification|nil
  local function wait_for_notification(predicate)
    vim.wait(2000, function()
      for _, n in ipairs(captured) do
        if predicate(n) then
          return true
        end
      end
      return false
    end, 10, false)
    for _, n in ipairs(captured) do
      if predicate(n) then
        return n
      end
    end
    return nil
  end

  it("reports input tokens, cost, model, and per-MTok pricing on success", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")
    local bufnr = make_chat_buffer()

    anthropic.try_estimate_usage(bufnr)

    local info = wait_for_notification(function(n)
      return n.level == vim.log.levels.INFO
    end)

    assert.is_not_nil(info, "Expected an INFO notification after estimate")
    -- claude-sonnet-4-6 pricing: input=3.0, output=15.0.
    -- 5432 input tokens × $3/MTok ≈ $0.016296 → "$0.016".
    local middot = "\xc2\xb7"
    local expected = "5,432 input tokens "
      .. middot
      .. " $0.016 "
      .. middot
      .. " claude-sonnet-4-6 ($3 input / $15 output per MTok)"
    assert.are.equal(expected, info.message)
  end)

  it("falls back to tokens-only output when model pricing is unavailable", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")

    -- Remove pricing from the current model to exercise the fallback branch.
    -- Every registered anthropic model has pricing, so mutate a known one and
    -- restore in the `ok,err` pcall wrapper below.
    local registry = require("flemma.provider.registry")
    local model_info = registry.get_model_info("anthropic", "claude-sonnet-4-6")
    assert.is_not_nil(model_info, "Fixture model must exist")
    local saved_pricing = model_info.pricing
    model_info.pricing = nil

    local ok, err = pcall(function()
      local bufnr = make_chat_buffer()

      anthropic.try_estimate_usage(bufnr)

      local info = wait_for_notification(function(n)
        return n.level == vim.log.levels.INFO
      end)

      assert.is_not_nil(info, "Expected an INFO notification after estimate")
      local middot = "\xc2\xb7"
      assert.are.equal("5,432 input tokens " .. middot .. " claude-sonnet-4-6", info.message)
    end)

    model_info.pricing = saved_pricing

    if not ok then
      error(err)
    end
  end)

  it("surfaces API error responses via notify.error", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_error.txt")
    local bufnr = make_chat_buffer()

    anthropic.try_estimate_usage(bufnr)

    local err = wait_for_notification(function(n)
      return n.level == vim.log.levels.ERROR and n.message:find("Estimate failed", 1, true) ~= nil
    end)

    assert.is_not_nil(err, "Expected an ERROR notification for API error")
    -- Both the error type and message should be surfaced so "not_found_error",
    -- "authentication_error", etc. make the cause legible at a glance.
    assert.is_truthy(err.message:find("authentication_error", 1, true), "Expected error type in notification")
    assert.is_truthy(err.message:find("invalid x%-api%-key"), "Expected error message in notification")
  end)

  it("warns when the buffer is empty", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    -- Intentionally do not register a fixture — the empty-buffer path
    -- must short-circuit before any HTTP call would fire.

    anthropic.try_estimate_usage(bufnr)

    local warn = wait_for_notification(function(n)
      return n.level == vim.log.levels.WARN
    end)

    assert.is_not_nil(warn, "Expected a WARN notification for empty buffer")
    assert.is_truthy(warn.message:find("Empty buffer", 1, true), "Expected empty-buffer warning text")

    -- No INFO notification should have been emitted.
    for _, n in ipairs(captured) do
      assert.are_not.equal(vim.log.levels.INFO, n.level)
    end
  end)

  it("surfaces an error when the response is not parseable JSON", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_unparseable.txt")
    local bufnr = make_chat_buffer()

    anthropic.try_estimate_usage(bufnr)

    local err = wait_for_notification(function(n)
      return n.level == vim.log.levels.ERROR
    end)

    assert.is_not_nil(err, "Expected an ERROR notification for unparseable response")
    assert.is_truthy(err.message:find("could not parse response", 1, true))
  end)
end)
