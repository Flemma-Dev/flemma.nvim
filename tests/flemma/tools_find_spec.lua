--- Tests for find tool definition

package.loaded["flemma.tools.definitions.find"] = nil
package.loaded["flemma.utilities.truncate"] = nil
package.loaded["flemma.sink"] = nil

local find_module = require("flemma.tools.definitions.find")
local executor = require("flemma.tools.executor")

describe("Find Tool", function()
  local find_def
  local bufnr
  local ctx

  before_each(function()
    find_def = find_module.definitions[1]
    find_module._reset_backend_cache()

    bufnr = vim.api.nvim_create_buf(false, true)
    ctx = executor.build_execution_context({
      bufnr = bufnr,
      cwd = vim.fn.getcwd(),
      timeout = 30,
      tool_name = "find",
    })
  end)

  after_each(function()
    find_module._reset_backend_cache()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("has correct definition metadata", function()
    assert.is_not_nil(find_def)
    assert.equals("find", find_def.name)
    assert.is_true(find_def.async)
    assert.is_truthy(find_def.description:match("glob pattern"))
  end)

  it("has can_auto_approve_if_sandboxed capability", function()
    assert.is_not_nil(find_def.capabilities)
    local found = false
    for _, cap in ipairs(find_def.capabilities) do
      if cap == "can_auto_approve_if_sandboxed" then
        found = true
      end
    end
    assert.is_true(found)
  end)

  describe("format_preview", function()
    it("shows pattern", function()
      local preview = find_def.format_preview({ pattern = "*.lua", label = "finding lua files" })
      assert.equals("finding lua files", preview.label)
      assert.is_truthy(preview.detail:match("%*%.lua"))
    end)

    it("shows pattern and path", function()
      local preview = find_def.format_preview({ pattern = "*.lua", path = "src/", label = "test" })
      assert.is_truthy(preview.detail:match("%*%.lua"))
      assert.is_truthy(preview.detail:match("in src/"))
    end)
  end)

  describe("_build_command", function()
    describe("fd backend", function()
      it("builds simple filename pattern", function()
        local cmd = find_module._build_command("fd", "*.lua", "/project", {})
        assert.equals("fd", cmd[1])
        assert.is_truthy(vim.tbl_contains(cmd, "--glob"))
        assert.is_truthy(vim.tbl_contains(cmd, "*.lua"))
        assert.is_truthy(vim.tbl_contains(cmd, "/project"))
      end)

      it("builds path pattern with directory", function()
        local cmd = find_module._build_command("fd", "src/**/*.tsx", "/project", {})
        assert.equals("fd", cmd[1])
        assert.is_truthy(vim.tbl_contains(cmd, "--glob"))
        assert.is_truthy(vim.tbl_contains(cmd, "*.tsx"))
        -- search_path should include the directory prefix
        local found_path = false
        for _, arg in ipairs(cmd) do
          if arg:match("/project/src/") then
            found_path = true
          end
        end
        assert.is_true(found_path, "expected path with directory prefix")
      end)

      it("includes exclude patterns", function()
        local cmd = find_module._build_command("fd", "*.lua", "/project", { "node_modules", ".git" })
        local exclude_count = 0
        for _, arg in ipairs(cmd) do
          if arg == "--exclude" then
            exclude_count = exclude_count + 1
          end
        end
        assert.equals(2, exclude_count)
      end)

      it("defaults path to search_path when no directory in pattern", function()
        local cmd = find_module._build_command("fd", "*.lua", ".", {})
        assert.equals(".", cmd[#cmd])
      end)
    end)

    describe("git backend", function()
      it("builds simple filename pattern with root and recursive globs", function()
        local cmd = find_module._build_command("git", "*.lua", "/project", {})
        assert.equals("git", cmd[1])
        assert.equals("ls-files", cmd[2])
        -- Should include both root-level and recursive patterns
        assert.is_truthy(vim.tbl_contains(cmd, "*.lua"))
        assert.is_truthy(vim.tbl_contains(cmd, "**/*.lua"))
      end)

      it("builds path pattern without prepending", function()
        local cmd = find_module._build_command("git", "src/**/*.tsx", "/project", {})
        assert.equals("git", cmd[1])
        assert.is_truthy(vim.tbl_contains(cmd, "src/**/*.tsx"))
        -- Should NOT prepend **/
        assert.is_falsy(vim.tbl_contains(cmd, "**/src/**/*.tsx"))
      end)

      it("includes exclude patterns", function()
        local cmd = find_module._build_command("git", "*.lua", "/project", { "vendor" })
        assert.is_truthy(vim.tbl_contains(cmd, "--exclude"))
        assert.is_truthy(vim.tbl_contains(cmd, "vendor"))
      end)
    end)

    describe("GNU find backend", function()
      it("builds simple filename pattern", function()
        local cmd = find_module._build_command("find", "*.lua", "/project", {})
        assert.equals("find", cmd[1])
        assert.equals("/project", cmd[2])
        assert.is_truthy(vim.tbl_contains(cmd, "-name"))
        assert.is_truthy(vim.tbl_contains(cmd, "*.lua"))
      end)

      it("builds path pattern with directory prefix", function()
        local cmd = find_module._build_command("find", "src/**/*.tsx", "/project", {})
        assert.equals("find", cmd[1])
        -- Search path should include directory prefix
        local found_path = false
        for _, arg in ipairs(cmd) do
          if arg:match("/project/src/") then
            found_path = true
          end
        end
        assert.is_true(found_path, "expected path with directory prefix")
        assert.is_truthy(vim.tbl_contains(cmd, "-name"))
        assert.is_truthy(vim.tbl_contains(cmd, "*.tsx"))
      end)

      it("includes exclude patterns", function()
        local cmd = find_module._build_command("find", "*.lua", "/project", { "node_modules" })
        assert.is_truthy(vim.tbl_contains(cmd, "-not"))
        assert.is_truthy(vim.tbl_contains(cmd, "-path"))
        assert.is_truthy(vim.tbl_contains(cmd, "*/node_modules/*"))
      end)

      it("defaults path when no directory in pattern", function()
        local cmd = find_module._build_command("find", "*.txt", "/project", {})
        assert.equals("/project", cmd[2])
      end)
    end)
  end)

  describe("execute", function()
    it("returns error for empty pattern", function()
      local result_captured
      find_def.execute({ label = "test", pattern = "", path = nil, limit = nil }, ctx, function(result)
        result_captured = result
      end)
      assert.is_not_nil(result_captured)
      assert.is_false(result_captured.success)
      assert.is_truthy(result_captured.error:match("No pattern"))
    end)

    it("returns error for nil pattern", function()
      local result_captured
      find_def.execute({ label = "test", path = nil, limit = nil }, ctx, function(result)
        result_captured = result
      end)
      assert.is_not_nil(result_captured)
      assert.is_false(result_captured.success)
      assert.is_truthy(result_captured.error:match("No pattern"))
    end)

    it("finds files in fixtures directory", function()
      -- Use the project's own test fixtures
      local project_root = vim.fn.getcwd()
      local fixture_ctx = executor.build_execution_context({
        bufnr = bufnr,
        cwd = project_root,
        timeout = 10,
        tool_name = "find",
      })

      local result_captured
      local done = false
      find_def.execute(
        { label = "test", pattern = "*.txt", path = "tests/fixtures/ls_test", limit = nil },
        fixture_ctx,
        function(result)
          result_captured = result
          done = true
        end
      )

      vim.wait(5000, function()
        return done
      end)

      assert.is_true(done, "callback should have been called")
      assert.is_not_nil(result_captured)
      assert.is_true(result_captured.success)
      assert.is_truthy(result_captured.output:match("readme%.txt"))
    end)

    it("returns no-match message for pattern with zero results", function()
      local project_root = vim.fn.getcwd()
      local fixture_ctx = executor.build_execution_context({
        bufnr = bufnr,
        cwd = project_root,
        timeout = 10,
        tool_name = "find",
      })

      local result_captured
      local done = false
      find_def.execute(
        {
          label = "test",
          pattern = "*.nonexistent_extension_xyz",
          path = "tests/fixtures/ls_test",
          limit = nil,
        },
        fixture_ctx,
        function(result)
          result_captured = result
          done = true
        end
      )

      vim.wait(5000, function()
        return done
      end)

      assert.is_true(done, "callback should have been called")
      assert.is_not_nil(result_captured)
      assert.is_true(result_captured.success)
      assert.is_truthy(result_captured.output:match("No files found"))
    end)

    it("produces sorted relative paths", function()
      local project_root = vim.fn.getcwd()
      local fixture_ctx = executor.build_execution_context({
        bufnr = bufnr,
        cwd = project_root .. "/tests/fixtures/ls_test",
        timeout = 10,
        tool_name = "find",
      })

      local result_captured
      local done = false
      find_def.execute({ label = "test", pattern = "*", path = nil, limit = nil }, fixture_ctx, function(result)
        result_captured = result
        done = true
      end)

      vim.wait(5000, function()
        return done
      end)

      assert.is_true(done, "callback should have been called")
      assert.is_not_nil(result_captured)
      assert.is_true(result_captured.success)

      -- Results should be sorted
      local lines = vim.split(result_captured.output, "\n", { plain = true })
      -- Filter non-empty, non-metadata lines
      local file_lines = {}
      for _, line in ipairs(lines) do
        if line ~= "" and not line:match("^%[") then
          table.insert(file_lines, line)
        end
      end
      for i = 2, #file_lines do
        assert.is_true(
          file_lines[i - 1] <= file_lines[i],
          string.format("Results not sorted: '%s' should come before '%s'", file_lines[i - 1], file_lines[i])
        )
      end
    end)

    it("normalizes absolute path matching cwd to relative output", function()
      local project_root = vim.fn.getcwd()
      local fixture_cwd = project_root .. "/tests/fixtures/ls_test"
      local fixture_ctx = executor.build_execution_context({
        bufnr = bufnr,
        cwd = fixture_cwd,
        timeout = 10,
        tool_name = "find",
      })

      local result_captured
      local done = false
      find_def.execute(
        { label = "test", pattern = "*.txt", path = fixture_cwd, limit = nil },
        fixture_ctx,
        function(result)
          result_captured = result
          done = true
        end
      )

      vim.wait(5000, function()
        return done
      end)

      assert.is_true(done, "callback should have been called")
      assert.is_not_nil(result_captured)
      assert.is_true(result_captured.success)
      -- Output should not contain the absolute cwd path
      assert.is_falsy(
        result_captured.output:match(vim.pesc(fixture_cwd)),
        "output should not contain absolute cwd path"
      )
      assert.is_truthy(result_captured.output:match("readme%.txt"))
    end)

    it("normalizes absolute subpath of cwd to relative output", function()
      local project_root = vim.fn.getcwd()
      local fixture_cwd = project_root .. "/tests/fixtures/ls_test"
      local fixture_ctx = executor.build_execution_context({
        bufnr = bufnr,
        cwd = fixture_cwd,
        timeout = 10,
        tool_name = "find",
      })

      local result_captured
      local done = false
      find_def.execute(
        { label = "test", pattern = "*.txt", path = fixture_cwd .. "/alpha", limit = nil },
        fixture_ctx,
        function(result)
          result_captured = result
          done = true
        end
      )

      vim.wait(5000, function()
        return done
      end)

      assert.is_true(done, "callback should have been called")
      assert.is_not_nil(result_captured)
      assert.is_true(result_captured.success)
      -- Output should not contain the absolute cwd path
      assert.is_falsy(
        result_captured.output:match(vim.pesc(fixture_cwd)),
        "output should not contain absolute cwd path"
      )
    end)

    it("returns cancel function", function()
      local project_root = vim.fn.getcwd()
      local fixture_ctx = executor.build_execution_context({
        bufnr = bufnr,
        cwd = project_root,
        timeout = 10,
        tool_name = "find",
      })

      local cancel = find_def.execute(
        { label = "test", pattern = "*.lua", path = "tests/fixtures", limit = nil },
        fixture_ctx,
        function(_) end
      )

      assert.is_truthy(cancel)
      assert.equals("function", type(cancel))
      -- Cancel should not error
      cancel()
    end)
  end)
end)
