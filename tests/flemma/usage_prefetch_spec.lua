--- Tests for flemma.usage.prefetch — state + lifecycle.

describe("flemma.usage.prefetch (lifecycle)", function()
  local prefetch, state
  local bufnr

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.usage.prefetch"] = nil
    package.loaded["flemma.state"] = nil
    require("flemma").setup({})
    prefetch = require("flemma.usage.prefetch")
    state = require("flemma.state")

    bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
  end)

  after_each(function()
    prefetch._reset_for_tests()
    vim.cmd("silent! %bdelete!")
  end)

  describe("start_tracking", function()
    it("is idempotent — two calls produce one state entry", function()
      prefetch.start_tracking(bufnr)
      prefetch.start_tracking(bufnr)
      assert.is_true(prefetch._is_tracked(bufnr))
      assert.equals(1, prefetch._tracked_count())
    end)

    it("creates a per-buffer augroup", function()
      prefetch.start_tracking(bufnr)
      local augroup = prefetch._get_augroup(bufnr)
      assert.is_not_nil(augroup)
    end)
  end)

  describe("get_tokens", function()
    it("returns nil before any fetch completes", function()
      prefetch.start_tracking(bufnr)
      assert.is_nil(prefetch.get_tokens(bufnr))
    end)

    it("returns nil for untracked buffers", function()
      assert.is_nil(prefetch.get_tokens(bufnr))
    end)
  end)

  describe("untrack", function()
    it("removes the state entry", function()
      prefetch.start_tracking(bufnr)
      prefetch.untrack(bufnr)
      assert.is_false(prefetch._is_tracked(bufnr))
    end)

    it("is called automatically on BufWipeout via state cleanup hook", function()
      prefetch.start_tracking(bufnr)
      -- Force the state cleanup pipeline.
      state.cleanup_buffer_state(bufnr)
      assert.is_false(prefetch._is_tracked(bufnr))
    end)
  end)
end)

describe("flemma.usage.prefetch (debounce + fetch)", function()
  local prefetch
  local client = require("flemma.client")
  local bufnr

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.usage.prefetch"] = nil
    require("flemma").setup({ parameters = { thinking = false } })
    prefetch = require("flemma.usage.prefetch")
    prefetch._DEBOUNCE_MS = 10

    bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })
    vim.bo[bufnr].filetype = "chat"
  end)

  after_each(function()
    prefetch._reset_for_tests()
    client.clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  ---@return integer count
  local function count_autocmd_fires()
    local fires = { n = 0 }
    local augroup = vim.api.nvim_create_augroup("FlemmaUsagePrefetchSpec", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      group = augroup,
      pattern = "FlemmaUsageEstimated",
      callback = function()
        fires.n = fires.n + 1
      end,
    })
    return fires
  end

  it("schedules an initial fetch on start_tracking and populates the cache", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")

    prefetch.start_tracking(bufnr)

    vim.wait(2000, function()
      return prefetch.get_tokens(bufnr) ~= nil
    end, 10)

    assert.equals(5432, prefetch.get_tokens(bufnr))
  end)

  it("emits FlemmaUsageEstimated once a fetch populates the cache", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")
    local fires = count_autocmd_fires()

    prefetch.start_tracking(bufnr)

    vim.wait(2000, function()
      return fires.n > 0
    end, 10)

    assert.is_true(fires.n >= 1)
  end)

  it("clears cache and emits hook when the adapter returns err", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_error.txt")
    local fires = count_autocmd_fires()

    prefetch.start_tracking(bufnr)

    vim.wait(2000, function()
      return fires.n > 0
    end, 10)

    assert.is_nil(prefetch.get_tokens(bufnr))
  end)

  it("does not dispatch a fetch when the provider lacks try_estimate_usage", function()
    require("flemma").setup({ provider = "openai", parameters = { thinking = false } })
    local fires = count_autocmd_fires()

    prefetch.start_tracking(bufnr)

    -- Give the deferred fetch a window to run.
    vim.wait(100, function()
      return false
    end)

    assert.is_nil(prefetch.get_tokens(bufnr))
    assert.equals(0, fires.n, "No hook should fire when the provider is unsupported")
  end)

  it("rescheduled fetch on TextChanged collapses rapid edits", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")
    prefetch.start_tracking(bufnr)
    vim.wait(2000, function()
      return prefetch.get_tokens(bufnr) ~= nil
    end, 10)

    local fires_before = count_autocmd_fires()

    -- Simulate rapid edits — should collapse into one fetch.
    for i = 1, 5 do
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "line " .. i })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })
    end

    vim.wait(300, function()
      return fires_before.n >= 1
    end, 10)

    -- With dedup, the count may be 0 if tokens matched; the key assertion is
    -- that we didn't emit five times for five edits.
    assert.is_true(
      fires_before.n <= 1,
      "Expected at most one hook emission for collapsed edits, got " .. fires_before.n
    )
  end)
end)

describe("flemma.usage.prefetch (FlemmaConfigUpdated)", function()
  local prefetch
  local client = require("flemma.client")
  local bufnr

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.usage.prefetch"] = nil
    require("flemma").setup({ parameters = { thinking = false } })
    prefetch = require("flemma.usage.prefetch")
    prefetch._DEBOUNCE_MS = 10

    bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })
    vim.bo[bufnr].filetype = "chat"
  end)

  after_each(function()
    prefetch._reset_for_tests()
    client.clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  it("wipes cache and schedules a refetch on FlemmaConfigUpdated", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")
    prefetch.start_tracking(bufnr)

    vim.wait(2000, function()
      return prefetch.get_tokens(bufnr) ~= nil
    end, 10)
    assert.equals(5432, prefetch.get_tokens(bufnr))

    vim.api.nvim_exec_autocmds("User", { pattern = "FlemmaConfigUpdated" })

    -- The wipe must happen synchronously (before the refetch lands).
    assert.is_nil(prefetch.get_tokens(bufnr))

    -- Then the rescheduled fetch repopulates.
    vim.wait(2000, function()
      return prefetch.get_tokens(bufnr) == 5432
    end, 10)
    assert.equals(5432, prefetch.get_tokens(bufnr))
  end)
end)

describe("flemma.usage.prefetch (request lifecycle)", function()
  local prefetch
  local client = require("flemma.client")
  local bufnr

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.usage.prefetch"] = nil
    require("flemma").setup({ parameters = { thinking = false } })
    prefetch = require("flemma.usage.prefetch")
    prefetch._DEBOUNCE_MS = 10

    bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })
    vim.bo[bufnr].filetype = "chat"
  end)

  after_each(function()
    prefetch._reset_for_tests()
    client.clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  ---@return flemma.session.Request
  local function make_request(input_tokens, model)
    return {
      provider = "anthropic",
      model = model or "claude-sonnet-4-6",
      input_tokens = input_tokens,
      output_tokens = 100,
      thoughts_tokens = 0,
      input_price = 3,
      output_price = 15,
      started_at = 0,
      completed_at = 1,
      output_has_thoughts = false,
      cache_read_input_tokens = 0,
      cache_creation_input_tokens = 0,
    }
  end

  it("FlemmaRequestSending sets request_active", function()
    prefetch.start_tracking(bufnr)
    assert.is_false(prefetch._is_request_active(bufnr))

    vim.api.nvim_exec_autocmds("User", {
      pattern = "FlemmaRequestSending",
      data = { bufnr = bufnr },
    })

    assert.is_true(prefetch._is_request_active(bufnr))
  end)

  it("FlemmaRequestFinished with a request payload seeds the cache", function()
    prefetch.start_tracking(bufnr)
    -- No fixture registered; initial fetch errors silently → cache stays nil.
    vim.wait(100, function()
      return false
    end)
    assert.is_nil(prefetch.get_tokens(bufnr))

    vim.api.nvim_exec_autocmds("User", {
      pattern = "FlemmaRequestFinished",
      data = {
        bufnr = bufnr,
        status = "completed",
        request = make_request(7777),
      },
    })

    assert.equals(7777, prefetch.get_tokens(bufnr))
    assert.is_false(prefetch._is_request_active(bufnr))
  end)

  it("FlemmaRequestFinished sums cached+uncached input tokens to match count_tokens semantics", function()
    prefetch.start_tracking(bufnr)
    vim.wait(100, function()
      return false
    end)

    local req = make_request(6)
    req.cache_read_input_tokens = 11591
    req.cache_creation_input_tokens = 0

    vim.api.nvim_exec_autocmds("User", {
      pattern = "FlemmaRequestFinished",
      data = { bufnr = bufnr, status = "completed", request = req },
    })

    -- Total must include cache-read tokens so the display matches what
    -- count_tokens would return (it doesn't know about cache).
    assert.equals(11597, prefetch.get_tokens(bufnr))
  end)

  it("FlemmaRequestFinished without request clears request_active but leaves cache untouched", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")
    prefetch.start_tracking(bufnr)
    vim.wait(2000, function()
      return prefetch.get_tokens(bufnr) ~= nil
    end, 10)
    assert.equals(5432, prefetch.get_tokens(bufnr))

    vim.api.nvim_exec_autocmds("User", {
      pattern = "FlemmaRequestSending",
      data = { bufnr = bufnr },
    })
    assert.is_true(prefetch._is_request_active(bufnr))

    vim.api.nvim_exec_autocmds("User", {
      pattern = "FlemmaRequestFinished",
      data = { bufnr = bufnr, status = "errored" },
    })

    assert.is_false(prefetch._is_request_active(bufnr))
    assert.equals(5432, prefetch.get_tokens(bufnr))
  end)

  it("debounced fetches are suppressed while request_active", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")
    prefetch.start_tracking(bufnr)
    vim.wait(2000, function()
      return prefetch.get_tokens(bufnr) ~= nil
    end, 10)

    -- Wipe cache + schedule a refetch via FlemmaConfigUpdated,
    -- then immediately enter request_active to cancel the pending timer.
    vim.api.nvim_exec_autocmds("User", { pattern = "FlemmaConfigUpdated" })
    assert.is_nil(prefetch.get_tokens(bufnr))

    vim.api.nvim_exec_autocmds("User", {
      pattern = "FlemmaRequestSending",
      data = { bufnr = bufnr },
    })

    -- Wait well past the debounce window; the cancelled timer must not fire.
    vim.wait(100, function()
      return false
    end)

    assert.is_nil(prefetch.get_tokens(bufnr))
    assert.is_true(prefetch._is_request_active(bufnr))
  end)
end)
