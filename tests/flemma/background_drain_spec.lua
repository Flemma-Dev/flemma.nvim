describe("job completion drain", function()
  local hooks_fired = {}

  before_each(function()
    hooks_fired = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = "FlemmaConversationIdle",
      callback = function(ev)
        table.insert(hooks_fired, { name = "conversation:idle", data = ev.data })
      end,
    })
    vim.api.nvim_create_autocmd("User", {
      pattern = "FlemmaJobCompleted",
      callback = function(ev)
        table.insert(hooks_fired, { name = "job:completed", data = ev.data })
      end,
    })
  end)

  after_each(function()
    vim.api.nvim_clear_autocmds({ pattern = "FlemmaConversationIdle" })
    vim.api.nvim_clear_autocmds({ pattern = "FlemmaJobCompleted" })
  end)

  it("fires conversation:idle hook correctly", function()
    local hooks = require("flemma.hooks")
    hooks.dispatch("conversation:idle", { bufnr = 0 })
    assert.equals(1, #hooks_fired)
    assert.equals("conversation:idle", hooks_fired[1].name)
  end)

  it("fires job:completed hook correctly", function()
    local hooks = require("flemma.hooks")
    hooks.dispatch("job:completed", {
      bufnr = 0,
      job_id = "job_test1",
      tool_id = "tool_01",
      tool_name = "bash",
      success = true,
    })
    assert.equals(1, #hooks_fired)
    assert.equals("job:completed", hooks_fired[1].name)
    assert.equals("job_test1", hooks_fired[1].data.job_id)
  end)

  it("drain_and_inject_completions injects results into the buffer", function()
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.state"] = nil
    local executor = require("flemma.tools.executor")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "Done.",
      "",
      "@You:",
      "",
    })
    vim.bo[bufnr].filetype = "chat"

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_drain1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "drain test output" },
    })

    assert.is_true(executor.has_job_completions(bufnr))

    local injector = require("flemma.tools.injector")
    local items = executor.drain_job_completions(bufnr)
    for _, item in ipairs(items) do
      injector.append_job_result(bufnr, item.job_id, item.result)
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_drain1`"))
    assert.truthy(joined:match("drain test output"))
    assert.is_false(executor.has_job_completions(bufnr))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("drains multiple completions in FIFO order and injects all results", function()
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.state"] = nil
    local executor = require("flemma.tools.executor")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "Done.",
      "",
      "@You:",
      "",
    })
    vim.bo[bufnr].filetype = "chat"

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_first",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "first output" },
    })
    executor.enqueue_job_completion(bufnr, {
      job_id = "job_second",
      tool_id = "tool_02",
      tool_name = "bash",
      result = { success = false, output = "second failed" },
    })

    assert.is_true(executor.has_job_completions(bufnr))

    local injector = require("flemma.tools.injector")
    local items = executor.drain_job_completions(bufnr)
    assert.equals(2, #items)
    assert.equals("job_first", items[1].job_id)
    assert.equals("job_second", items[2].job_id)

    for _, item in ipairs(items) do
      injector.append_job_result(bufnr, item.job_id, item.result)
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_first`"))
    assert.truthy(joined:match("first output"))
    assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_second`%s*%(error%)"))
    assert.truthy(joined:match("second failed"))

    assert.is_false(executor.has_job_completions(bufnr))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("fires job:completed hook for each drained item", function()
    local hooks = require("flemma.hooks")
    local fired = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = "FlemmaJobCompleted",
      callback = function(ev)
        table.insert(fired, ev.data.job_id)
      end,
    })

    hooks.dispatch("job:completed", {
      bufnr = 0,
      job_id = "job_a",
      tool_id = "tool_01",
      tool_name = "bash",
      success = true,
    })
    hooks.dispatch("job:completed", {
      bufnr = 0,
      job_id = "job_b",
      tool_id = "tool_02",
      tool_name = "bash",
      success = false,
    })

    assert.equals(2, #fired)
    assert.equals("job_a", fired[1])
    assert.equals("job_b", fired[2])

    vim.api.nvim_clear_autocmds({ pattern = "FlemmaJobCompleted" })
  end)
end)
