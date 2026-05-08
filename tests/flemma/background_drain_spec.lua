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
      job_id = "bg_test1",
      tool_id = "tool_01",
      tool_name = "bash",
      success = true,
    })
    assert.equals(1, #hooks_fired)
    assert.equals("job:completed", hooks_fired[1].name)
    assert.equals("bg_test1", hooks_fired[1].data.job_id)
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
      job_id = "bg_drain1",
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
    assert.truthy(joined:match("%*%*Job Result:%*%*%s*`bg_drain1`"))
    assert.truthy(joined:match("drain test output"))
    assert.is_false(executor.has_job_completions(bufnr))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
