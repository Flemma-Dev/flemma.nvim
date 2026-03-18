--- Tests for ls tool definition

package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.approval"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.executor"] = nil
package.loaded["flemma.tools.definitions.ls"] = nil
package.loaded["flemma.utilities.truncate"] = nil

local executor = require("flemma.tools.executor")
local ls_module = require("flemma.tools.definitions.ls")

describe("Ls Tool", function()
  local ls_def, fixture_dir, bufnr, ctx

  before_each(function()
    ls_def = ls_module.definitions[1]
    fixture_dir = vim.fn.fnamemodify("tests/fixtures/ls_test", ":p"):gsub("/$", "")
    bufnr = vim.api.nvim_create_buf(false, true)
    ctx = executor.build_execution_context({
      bufnr = bufnr,
      cwd = fixture_dir,
      timeout = 30,
      tool_name = "ls",
    })
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("has correct metadata", function()
    assert.is_not_nil(ls_def)
    assert.equals("ls", ls_def.name)
    assert.is_false(ls_def.async)
  end)

  it("lists direct children at depth 1", function()
    local result = ls_def.execute({ label = "test", path = ".", max_depth = 1, limit = 500 }, ctx)
    assert.is_true(result.success)
    -- Should contain all non-hidden entries
    assert.is_truthy(result.output:match("alpha/"))
    assert.is_truthy(result.output:match("beta/"))
    assert.is_truthy(result.output:match("readme%.txt"))
    assert.is_truthy(result.output:match("zebra%.lua"))
  end)

  it("includes hidden files", function()
    local result = ls_def.execute({ label = "test", path = ".", max_depth = 1, limit = 500 }, ctx)
    assert.is_true(result.success)
    assert.is_truthy(result.output:match("%.hidden"))
  end)

  it("suffixes directories with /", function()
    local result = ls_def.execute({ label = "test", path = ".", max_depth = 1, limit = 500 }, ctx)
    assert.is_true(result.success)
    assert.is_truthy(result.output:match("alpha/"))
    assert.is_truthy(result.output:match("beta/"))
    -- Files should NOT have /
    assert.is_falsy(result.output:match("readme%.txt/"))
  end)

  it("sorts directories first, then files, case-insensitively", function()
    local result = ls_def.execute({ label = "test", path = ".", max_depth = 1, limit = 500 }, ctx)
    assert.is_true(result.success)

    -- Extract lines before the footer
    local lines = vim.split(result.output, "\n", { plain = true })
    local entries = {}
    for _, line in ipairs(lines) do
      if line ~= "" and not line:match("^%[") then
        table.insert(entries, line)
      end
    end

    -- Find positions of directories and files
    local last_dir_index = 0
    local first_file_index = #entries + 1
    for i, entry in ipairs(entries) do
      if entry:match("/$") then
        last_dir_index = math.max(last_dir_index, i)
      else
        first_file_index = math.min(first_file_index, i)
      end
    end

    -- All directories should come before all files
    assert.is_true(last_dir_index < first_file_index, "directories should appear before files")
  end)

  it("respects limit with early termination", function()
    local result = ls_def.execute({ label = "test", path = ".", max_depth = 1, limit = 2 }, ctx)
    assert.is_true(result.success)

    -- Extract entry lines (not footer)
    local lines = vim.split(result.output, "\n", { plain = true })
    local entry_count = 0
    for _, line in ipairs(lines) do
      if line ~= "" and not line:match("^%[") then
        entry_count = entry_count + 1
      end
    end

    assert.equals(2, entry_count)
    -- Footer should show the count
    assert.is_truthy(result.output:match("%[2 entries%]"))
  end)

  it("returns error for non-existent path", function()
    local result = ls_def.execute({ label = "test", path = "/nonexistent/path", max_depth = 1, limit = 500 }, ctx)
    assert.is_false(result.success)
    assert.is_truthy(result.error:match("Directory not found"))
  end)

  it("returns error for empty path", function()
    local result = ls_def.execute({ label = "test", path = "", max_depth = 1, limit = 500 }, ctx)
    assert.is_false(result.success)
    assert.is_truthy(result.error:match("No path"))
  end)

  it("returns nested entries with full relative paths at depth > 1", function()
    local result = ls_def.execute({ label = "test", path = ".", max_depth = 2, limit = 500 }, ctx)
    assert.is_true(result.success)
    -- Should include nested entry with relative path
    assert.is_truthy(result.output:match("alpha/nested%.txt"))
    -- Footer should show depth
    assert.is_truthy(result.output:match("depth=2"))
  end)

  it("clamps max_depth to 10", function()
    -- Requesting depth 100 should be clamped to 10
    local result = ls_def.execute({ label = "test", path = ".", max_depth = 100, limit = 500 }, ctx)
    assert.is_true(result.success)
    -- Footer should show depth=10 (clamped)
    assert.is_truthy(result.output:match("depth=10"))
  end)

  it("defaults max_depth to 1 when nil", function()
    local result = ls_def.execute({ label = "test", path = "." }, ctx)
    assert.is_true(result.success)
    -- At depth=1, no nested entries should appear
    assert.is_falsy(result.output:match("alpha/nested%.txt"))
    -- Footer should not show depth
    assert.is_truthy(result.output:match("%[%d+ entries%]$"))
  end)

  it("resolves relative paths against cwd", function()
    -- ctx.cwd is fixture_dir, so "alpha" should resolve to fixture_dir/alpha
    local result = ls_def.execute({ label = "test", path = "alpha", max_depth = 1, limit = 500 }, ctx)
    assert.is_true(result.success)
    assert.is_truthy(result.output:match("nested%.txt"))
  end)

  it("handles absolute paths", function()
    local result = ls_def.execute({ label = "test", path = fixture_dir .. "/alpha", max_depth = 1, limit = 500 }, ctx)
    assert.is_true(result.success)
    assert.is_truthy(result.output:match("nested%.txt"))
  end)

  describe("format_preview", function()
    it("shows path and label", function()
      local preview = ls_def.format_preview({ path = "/some/dir", label = "listing root" })
      assert.equals("listing root", preview.label)
      assert.equals("/some/dir", preview.detail)
    end)

    it("shows depth when > 1", function()
      local preview = ls_def.format_preview({ path = "src", max_depth = 3, label = "deep scan" })
      assert.equals("deep scan", preview.label)
      assert.equals("src  depth=3", preview.detail)
    end)

    it("omits depth when 1", function()
      local preview = ls_def.format_preview({ path = "src", max_depth = 1, label = "shallow" })
      assert.equals("shallow", preview.label)
      assert.equals("src", preview.detail)
    end)
  end)
end)
