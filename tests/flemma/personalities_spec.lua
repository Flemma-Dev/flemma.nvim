local personalities

describe("flemma.personalities", function()
  before_each(function()
    package.loaded["flemma.personalities"] = nil
    personalities = require("flemma.personalities")
  end)

  describe("registry", function()
    it("implements flemma.Registry contract", function()
      assert.is_function(personalities.register)
      assert.is_function(personalities.unregister)
      assert.is_function(personalities.get)
      assert.is_function(personalities.get_all)
      assert.is_function(personalities.has)
      assert.is_function(personalities.clear)
      assert.is_function(personalities.count)
    end)

    it("registers and retrieves a personality", function()
      local mock = {
        render = function()
          return "test"
        end,
      }
      personalities.register("test-personality", mock)
      assert.is_true(personalities.has("test-personality"))
      assert.equals(mock, personalities.get("test-personality"))
    end)

    it("returns nil for unknown personality", function()
      assert.is_nil(personalities.get("nonexistent"))
    end)

    it("rejects names with dots", function()
      assert.has_error(function()
        personalities.register("my.personality", {
          render = function()
            return ""
          end,
        })
      end)
    end)

    it("unregisters a personality", function()
      personalities.register("temp", {
        render = function()
          return ""
        end,
      })
      assert.is_true(personalities.unregister("temp"))
      assert.is_false(personalities.has("temp"))
    end)

    pending("registers built-in coding-assistant personality", function()
      -- Enabled after coding-assistant module is created (Task 5)
      personalities.setup()
      assert.is_true(personalities.has("coding-assistant"))
    end)
  end)
end)

local builder

describe("flemma.personalities.builder", function()
  before_each(function()
    package.loaded["flemma.personalities.builder"] = nil
    builder = require("flemma.personalities.builder")
  end)

  describe("build_tools()", function()
    it("returns tool entries with parts for the personality", function()
      local tool_definitions = {
        {
          name = "bash",
          description = "Execute commands",
          input_schema = { type = "object" },
          personalities = {
            ["coding-assistant"] = {
              snippet = "Execute shell commands",
              guidelines = { "Be careful", "Check first" },
            },
          },
        },
        {
          name = "read",
          description = "Read files",
          input_schema = { type = "object" },
        },
      }
      local result = builder.build_tools("coding-assistant", tool_definitions)
      assert.equals(2, #result)

      local bash = result[1]
      assert.equals("bash", bash.name)
      assert.same({ "Execute shell commands" }, bash.parts.snippet)
      assert.same({ "Be careful", "Check first" }, bash.parts.guidelines)

      local read_tool = result[2]
      assert.equals("read", read_tool.name)
      assert.same({}, read_tool.parts)
    end)

    it("normalizes single string parts to table", function()
      local tool_definitions = {
        {
          name = "bash",
          description = "Execute commands",
          input_schema = { type = "object" },
          personalities = {
            ["test"] = {
              snippet = "A single string",
            },
          },
        },
      }
      local result = builder.build_tools("test", tool_definitions)
      assert.same({ "A single string" }, result[1].parts.snippet)
    end)

    it("returns empty parts for personality not in tool definition", function()
      local tool_definitions = {
        {
          name = "bash",
          description = "Execute commands",
          input_schema = { type = "object" },
          personalities = {
            ["other-personality"] = { snippet = "Other" },
          },
        },
      }
      local result = builder.build_tools("coding-assistant", tool_definitions)
      assert.same({}, result[1].parts)
    end)
  end)

  describe("build_environment()", function()
    it("returns environment with cwd and date/time", function()
      local env = builder.build_environment()
      assert.is_string(env.cwd)
      assert.is_string(env.date)
      assert.is_string(env.time)
    end)
  end)

  describe("build_project_context()", function()
    it("returns empty table when no target files exist", function()
      local result = builder.build_project_context("/nonexistent/directory")
      assert.same({}, result)
    end)

    it("reads matching files from base directory", function()
      local result = builder.build_project_context("/tmp/nonexistent")
      assert.is_table(result)
    end)

    it("deduplicates files with identical content", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      local content = "identical content"

      local f1 = io.open(tmpdir .. "/AGENTS.md", "w")
      f1:write(content)
      f1:close()

      vim.fn.mkdir(tmpdir .. "/.claude", "p")
      local f2 = io.open(tmpdir .. "/.claude/CLAUDE.md", "w")
      f2:write(content)
      f2:close()

      local result = builder.build_project_context(tmpdir, {
        "AGENTS.md",
        ".claude/CLAUDE.md",
      })
      assert.equals(1, #result)
      assert.equals("AGENTS.md", result[1].path)

      vim.fn.delete(tmpdir, "rf")
    end)

    it("skips missing target files silently", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")

      local result = builder.build_project_context(tmpdir, {
        "NONEXISTENT.md",
        "ALSO_MISSING.md",
      })
      assert.same({}, result)

      vim.fn.delete(tmpdir, "rf")
    end)
  end)
end)
