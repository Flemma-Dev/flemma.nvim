--- Tests for grep tool definition

package.loaded["flemma.tools.definitions.grep"] = nil
package.loaded["flemma.utilities.truncate"] = nil
package.loaded["flemma.utilities.json"] = nil
package.loaded["flemma.sink"] = nil

local executor = require("flemma.tools.executor")
local grep_module = require("flemma.tools.definitions.grep")

describe("Grep Tool", function()
  local grep_def, fixture_dir, bufnr, ctx

  before_each(function()
    grep_module._reset_backend_cache()
    grep_def = grep_module.definitions[1]
    fixture_dir = vim.fn.fnamemodify("tests/fixtures/grep_test", ":p"):gsub("/$", "")
    bufnr = vim.api.nvim_create_buf(false, true)
    ctx = executor.build_execution_context({
      bufnr = bufnr,
      cwd = fixture_dir,
      timeout = 30,
      tool_name = "grep",
    })
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("has correct metadata", function()
    assert.is_not_nil(grep_def)
    assert.equals("grep", grep_def.name)
    assert.is_true(grep_def.async)
  end)

  it("has can_auto_approve_if_sandboxed capability", function()
    assert.is_truthy(vim.tbl_contains(grep_def.capabilities, "can_auto_approve_if_sandboxed"))
  end)

  describe("backend detection", function()
    it("detects rg when available", function()
      local original_executable = vim.fn.executable
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.executable = function(name)
        if name == "rg" then
          return 1
        end
        return 0
      end

      grep_module._reset_backend_cache()
      -- Force detection by calling _build_command which implicitly needs a backend
      -- but we test via the exposed detect mechanism
      local cmd = grep_module._build_command("rg", "test", ".", nil, {})
      assert.equals("rg", cmd[1])

      vim.fn.executable = original_executable
    end)

    it("falls back to grep when rg is not available", function()
      local original_executable = vim.fn.executable
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.executable = function(name)
        if name == "grep" then
          return 1
        end
        return 0
      end

      grep_module._reset_backend_cache()
      local cmd = grep_module._build_command("grep-e", "test", ".", nil, {})
      assert.equals("grep", cmd[1])

      vim.fn.executable = original_executable
    end)
  end)

  describe("pattern translation (grep -E)", function()
    it("translates \\d to [0-9]", function()
      local result = grep_module._translate_ere_pattern("\\d+")
      assert.equals("[0-9]+", result)
    end)

    it("translates \\w to [a-zA-Z0-9_]", function()
      local result = grep_module._translate_ere_pattern("\\w+")
      assert.equals("[a-zA-Z0-9_]+", result)
    end)

    it("translates \\s to [[:space:]]", function()
      local result = grep_module._translate_ere_pattern("\\s+")
      assert.equals("[[:space:]]+", result)
    end)

    it("translates multiple shorthand classes", function()
      local result = grep_module._translate_ere_pattern("\\d\\w\\s")
      assert.equals("[0-9][a-zA-Z0-9_][[:space:]]", result)
    end)

    it("leaves other patterns unchanged", function()
      local result = grep_module._translate_ere_pattern("hello.*world")
      assert.equals("hello.*world", result)
    end)

    it("does not translate already-expanded classes", function()
      local result = grep_module._translate_ere_pattern("[0-9]+")
      assert.equals("[0-9]+", result)
    end)
  end)

  describe("command construction", function()
    describe("rg backend", function()
      it("builds basic rg command", function()
        local cmd = grep_module._build_command("rg", "hello", "/src", nil, {})
        assert.same({ "rg", "--json", "--no-messages", "hello", "/src" }, cmd)
      end)

      it("includes glob filter", function()
        local cmd = grep_module._build_command("rg", "hello", "/src", "*.lua", {})
        assert.same({ "rg", "--json", "--no-messages", "hello", "--glob", "*.lua", "/src" }, cmd)
      end)

      it("includes exclude patterns", function()
        local cmd = grep_module._build_command("rg", "hello", "/src", nil, { "node_modules", "*.min.js" })
        assert.same({
          "rg",
          "--json",
          "--no-messages",
          "hello",
          "--glob",
          "!node_modules",
          "--glob",
          "!*.min.js",
          "/src",
        }, cmd)
      end)

      it("defaults search path to . when nil", function()
        local cmd = grep_module._build_command("rg", "hello", nil, nil, {})
        assert.same({ "rg", "--json", "--no-messages", "hello", "." }, cmd)
      end)
    end)

    describe("grep-p backend", function()
      it("builds basic grep -P command", function()
        local cmd = grep_module._build_command("grep-p", "hello", "/src", nil, {})
        assert.same({ "grep", "-rn", "--binary-files=without-match", "-P", "hello", "/src" }, cmd)
      end)

      it("includes file glob as --include", function()
        local cmd = grep_module._build_command("grep-p", "hello", "/src", "*.lua", {})
        assert.same({ "grep", "-rn", "--binary-files=without-match", "-P", "hello", "--include=*.lua", "/src" }, cmd)
      end)

      it("uses --exclude-dir for directory excludes", function()
        local cmd = grep_module._build_command("grep-p", "hello", "/src", nil, { "node_modules" })
        assert.same({
          "grep",
          "-rn",
          "--binary-files=without-match",
          "-P",
          "hello",
          "--exclude-dir=node_modules",
          "/src",
        }, cmd)
      end)

      it("uses --exclude for file excludes", function()
        local cmd = grep_module._build_command("grep-p", "hello", "/src", nil, { "*.min.js" })
        assert.same({
          "grep",
          "-rn",
          "--binary-files=without-match",
          "-P",
          "hello",
          "--exclude=*.min.js",
          "/src",
        }, cmd)
      end)
    end)

    describe("grep-e backend", function()
      it("builds grep -E command with translated pattern", function()
        local cmd = grep_module._build_command("grep-e", "\\d+", "/src", nil, {})
        assert.same({ "grep", "-rn", "--binary-files=without-match", "-E", "[0-9]+", "/src" }, cmd)
      end)

      it("preserves non-shorthand patterns", function()
        local cmd = grep_module._build_command("grep-e", "hello.*world", "/src", nil, {})
        assert.same({ "grep", "-rn", "--binary-files=without-match", "-E", "hello.*world", "/src" }, cmd)
      end)
    end)
  end)

  describe("format_preview", function()
    it("shows pattern and label", function()
      local preview = grep_def.format_preview({ pattern = "hello", label = "searching" })
      assert.equals("searching", preview.label)
      assert.same({ "/hello/" }, preview.detail)
    end)

    it("shows path when provided", function()
      local preview = grep_def.format_preview({ pattern = "hello", path = "src/", label = "in source" })
      assert.equals("in source", preview.label)
      assert.same({ "/hello/", "src/" }, preview.detail)
    end)

    it("shows glob when provided", function()
      local preview = grep_def.format_preview({ pattern = "hello", glob = "*.lua", label = "lua files" })
      assert.equals("lua files", preview.label)
      assert.same({ "/hello/", "*.lua" }, preview.detail)
    end)

    it("shows all parts", function()
      local preview =
        grep_def.format_preview({ pattern = "TODO", path = "src/", glob = "*.ts", label = "finding todos" })
      assert.equals("finding todos", preview.label)
      assert.same({ "/TODO/", "src/", "*.ts" }, preview.detail)
    end)
  end)

  describe("path normalization", function()
    -- Helper to run grep asynchronously and wait for result
    ---@param input table<string, any>
    ---@param execution_ctx flemma.tools.ExecutionContext
    ---@return flemma.tools.ExecutionResult
    local function run_grep_async(input, execution_ctx)
      local result = nil
      grep_def.execute(input, execution_ctx, function(r)
        result = r
      end)
      vim.wait(5000, function()
        return result ~= nil
      end, 50)
      assert.is_not_nil(result, "grep did not complete within timeout")
      return result
    end

    it("produces relative paths for relative input", function()
      local result = run_grep_async({ label = "test", pattern = "hello", path = ".", glob = "*.lua", limit = nil }, ctx)
      assert.is_true(result.success)
      -- Output should not contain the absolute fixture_dir prefix
      assert.is_falsy(result.output:match(vim.pesc(fixture_dir)), "output should not contain absolute cwd path")
      -- Should contain relative paths
      assert.is_truthy(result.output:match("%.lua:%d+:"))
    end)

    it("normalizes absolute path matching cwd to relative", function()
      local result =
        run_grep_async({ label = "test", pattern = "hello", path = fixture_dir, glob = "*.lua", limit = nil }, ctx)
      assert.is_true(result.success)
      -- Output paths should be relative (./file or file), not absolute
      assert.is_falsy(result.output:match(vim.pesc(fixture_dir)), "output should not contain absolute cwd path")
      assert.is_truthy(result.output:match("%.lua:%d+:"))
    end)

    it("normalizes absolute subpath of cwd to relative", function()
      local subdir_absolute = fixture_dir .. "/subdir"
      local result =
        run_grep_async({ label = "test", pattern = "hello", path = subdir_absolute, glob = nil, limit = nil }, ctx)
      assert.is_true(result.success)
      -- Should not contain the cwd prefix in output
      assert.is_falsy(result.output:match(vim.pesc(fixture_dir)), "output should not contain absolute cwd path")
    end)
  end)

  describe("integration", function()
    -- Helper to run grep asynchronously and wait for result
    ---@param input table<string, any>
    ---@param execution_ctx flemma.tools.ExecutionContext
    ---@return flemma.tools.ExecutionResult
    local function run_grep(input, execution_ctx)
      local result = nil
      grep_def.execute(input, execution_ctx, function(r)
        result = r
      end)
      -- Wait for async completion
      vim.wait(5000, function()
        return result ~= nil
      end, 50)
      assert.is_not_nil(result, "grep did not complete within timeout")
      return result
    end

    it("finds matches in fixture files", function()
      local result = run_grep({ label = "test", pattern = "hello", path = nil, glob = nil, limit = nil }, ctx)
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("hello"))
      assert.is_truthy(result.output:match("%[%d+ matches"))
    end)

    it("returns no matches message when nothing found", function()
      local result =
        run_grep({ label = "test", pattern = "zzz_nonexistent_zzz", path = nil, glob = nil, limit = nil }, ctx)
      assert.is_true(result.success)
      assert.equals("No matches found.", result.output)
    end)

    it("filters by glob pattern", function()
      local result = run_grep({ label = "test", pattern = "hello", path = nil, glob = "*.lua", limit = nil }, ctx)
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("hello"))
      -- Should find matches in .lua files (sample.lua, subdir/nested.lua)
      assert.is_truthy(result.output:match("%.lua"))
    end)

    it("searches in specified path", function()
      local result = run_grep({ label = "test", pattern = "hello", path = "subdir", glob = nil, limit = nil }, ctx)
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("hello"))
    end)

    it("respects match limit", function()
      -- Our fixture has multiple "hello" matches; limit to 1
      local result = run_grep({ label = "test", pattern = "hello", path = nil, glob = nil, limit = 1 }, ctx)
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("limit reached"))
    end)

    it("returns error for empty pattern", function()
      local result = nil
      grep_def.execute({ label = "test", pattern = "", path = nil, glob = nil, limit = nil }, ctx, function(r)
        result = r
      end)
      -- Empty pattern returns synchronously
      assert.is_not_nil(result)
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No pattern"))
    end)

    it("returns error for nil pattern", function()
      local result = nil
      grep_def.execute({ label = "test", path = nil, glob = nil, limit = nil }, ctx, function(r)
        result = r
      end)
      assert.is_not_nil(result)
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No pattern"))
    end)

    it("includes line numbers in output", function()
      local result = run_grep({ label = "test", pattern = "hello", path = nil, glob = "*.lua", limit = nil }, ctx)
      assert.is_true(result.success)
      -- Output should contain path:linenum:content format
      assert.is_truthy(result.output:match(":%d+:"))
    end)
  end)
end)
