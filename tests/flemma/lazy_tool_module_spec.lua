local notify = require("flemma.notify")

describe("lazy tool module loading", function()
  local executor, registry
  local original_path

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.commands"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.approval"] = nil
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.tools.registry"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.readiness"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["test_tools"] = nil

    original_path = package.path
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures/modules", ":p")
    package.path = fixture_dir .. "?.lua;" .. package.path

    local flemma = require("flemma")
    flemma.setup({
      tools = { modules = { "test_tools" } },
      parameters = { thinking = false },
    })

    executor = require("flemma.tools.executor")
    registry = require("flemma.tools.registry")
  end)

  after_each(function()
    package.path = original_path
    notify._reset_impl()
    vim.cmd("silent! %bdelete!")
  end)

  it("executor finds a tool from a lazy-loaded module", function()
    -- After setup, the module is registered but not yet loaded
    assert.is_false(registry.has("fixture_search"), "tool should NOT be in registry before first access")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Find something",
      "",
      "@Assistant:",
      "",
      "**Tool Use:** `fixture_search` (`toolu_lazy_01`)",
      "",
      "```json",
      '{"query":"hello"}',
      "```",
      "",
      "**Tool Result:** `toolu_lazy_01` (approved)",
      "",
      "```",
      "```",
    })
    vim.bo[bufnr].filetype = "chat"

    local ok, err = executor.execute(bufnr, {
      tool_id = "toolu_lazy_01",
      tool_name = "fixture_search",
      input = { query = "hello" },
      start_line = 12,
      end_line = 15,
    })

    assert.is_true(ok, "executor should succeed, got error: " .. tostring(err))
    assert.is_true(registry.has("fixture_search"), "tool should be in registry after execution")
  end)
end)
