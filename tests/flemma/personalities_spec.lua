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

    it("registers built-in coding-assistant personality", function()
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

local coding_assistant

describe("flemma.personalities.coding-assistant", function()
  before_each(function()
    package.loaded["flemma.personalities.coding-assistant"] = nil
    coding_assistant = require("flemma.personalities.coding-assistant")
  end)

  it("has a render function", function()
    assert.is_function(coding_assistant.render)
  end)

  it("renders core persona", function()
    local result = coding_assistant.render({
      tools = {},
      environment = { cwd = "/test", date = "Monday, March 8, 2026", time = "02:15 PM" },
      project_context = {},
    })
    assert.truthy(result:find("coding assistant"))
    assert.truthy(result:find("Neovim"))
  end)

  it("renders tools with snippets", function()
    local result = coding_assistant.render({
      tools = {
        { name = "bash", parts = { snippet = { "Execute shell commands" } } },
        { name = "read", parts = {} },
      },
      environment = { cwd = "/test", date = "Monday", time = "12:00 PM" },
      project_context = {},
    })
    assert.truthy(result:find("bash: Execute shell commands"))
    assert.truthy(result:find("- read\n"))
  end)

  it("renders guidelines from tool parts", function()
    local result = coding_assistant.render({
      tools = {
        { name = "bash", parts = { guidelines = { "Be careful", "Check first" } } },
      },
      environment = { cwd = "/test", date = "Monday", time = "12:00 PM" },
      project_context = {},
    })
    assert.truthy(result:find("- Be careful"))
    assert.truthy(result:find("- Check first"))
  end)

  it("omits tools section when no tools", function()
    local result = coding_assistant.render({
      tools = {},
      environment = { cwd = "/test", date = "Monday", time = "12:00 PM" },
      project_context = {},
    })
    assert.falsy(result:find("Available tools"))
  end)

  it("omits guidelines section when no guidelines", function()
    local result = coding_assistant.render({
      tools = {
        { name = "bash", parts = { snippet = { "Execute commands" } } },
      },
      environment = { cwd = "/test", date = "Monday", time = "12:00 PM" },
      project_context = {},
    })
    assert.falsy(result:find("Guidelines"))
  end)

  it("renders environment context", function()
    local result = coding_assistant.render({
      tools = {},
      environment = {
        cwd = "/home/user/project",
        current_file = "src/main.lua",
        filetype = "lua",
        git_branch = "feature/foo",
        date = "Monday, March 8, 2026",
        time = "02:15 PM",
      },
      project_context = {},
    })
    assert.truthy(result:find("Monday, March 8, 2026"))
    assert.truthy(result:find("/home/user/project"))
    assert.truthy(result:find("src/main.lua"))
    assert.truthy(result:find("lua"))
    assert.truthy(result:find("feature/foo"))
  end)

  it("omits optional environment fields when nil", function()
    local result = coding_assistant.render({
      tools = {},
      environment = { cwd = "/test", date = "Monday", time = "12:00 PM" },
      project_context = {},
    })
    assert.falsy(result:find("Current file"))
    assert.falsy(result:find("Git branch"))
  end)

  it("renders project context files", function()
    local result = coding_assistant.render({
      tools = {},
      environment = { cwd = "/test", date = "Monday", time = "12:00 PM" },
      project_context = {
        { path = "AGENTS.md", content = "Project rules here" },
      },
    })
    assert.truthy(result:find("### AGENTS.md"))
    assert.truthy(result:find("Project rules here"))
  end)

  it("omits project context section when empty", function()
    local result = coding_assistant.render({
      tools = {},
      environment = { cwd = "/test", date = "Monday", time = "12:00 PM" },
      project_context = {},
    })
    assert.falsy(result:find("Project Context"))
  end)
end)

describe("URN dispatch in include()", function()
  local eval

  before_each(function()
    package.loaded["flemma.eval"] = nil
    package.loaded["flemma.personalities"] = nil
    package.loaded["flemma.personalities.coding-assistant"] = nil
    eval = require("flemma.eval")
    local pers = require("flemma.personalities")
    pers.setup()
  end)

  it("dispatches urn:flemma:personality: to personality registry", function()
    local env = eval.create_safe_env()
    env.__dirname = vim.fn.getcwd()

    local result = eval.eval_expression("include('urn:flemma:personality:coding-assistant')", env)
    assert.is_table(result)
    assert.is_function(result.emit)
  end)

  it("errors on unknown personality URN", function()
    local env = eval.create_safe_env()
    env.__dirname = vim.fn.getcwd()

    assert.has_error(function()
      eval.eval_expression("include('urn:flemma:personality:nonexistent')", env)
    end)
  end)

  it("still resolves file paths normally", function()
    local env = eval.create_safe_env()
    env.__dirname = vim.fn.fnamemodify("tests/fixtures", ":p")

    local ok = pcall(eval.eval_expression, "include('nonexistent.txt')", env)
    assert.is_false(ok)
  end)
end)

describe("personality system integration", function()
  before_each(function()
    package.loaded["flemma.eval"] = nil
    package.loaded["flemma.personalities"] = nil
    package.loaded["flemma.personalities.builder"] = nil
    package.loaded["flemma.personalities.coding-assistant"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.registry"] = nil

    local tool_registry = require("flemma.tools.registry")
    tool_registry.clear()

    tool_registry.register("bash", {
      name = "bash",
      description = "Execute commands",
      input_schema = { type = "object" },
      personalities = {
        ["coding-assistant"] = {
          snippet = "Execute shell commands",
          guidelines = { "Be careful with destructive commands" },
        },
      },
    })

    tool_registry.register("custom", {
      name = "custom",
      description = "Custom tool",
      input_schema = { type = "object" },
    })

    local pers = require("flemma.personalities")
    pers.setup()
  end)

  it("renders a complete prompt via include URN", function()
    local eval = require("flemma.eval")
    local env = eval.create_safe_env()
    env.__dirname = vim.fn.getcwd()

    local result = eval.eval_expression("include('urn:flemma:personality:coding-assistant')", env)

    -- Emit the result to get the final text
    local emittable_mod = require("flemma.emittable")
    local emit_ctx = emittable_mod.EmitContext.new()
    emit_ctx:emit(result)

    assert.equals(1, #emit_ctx.parts)
    local text = emit_ctx.parts[1].text

    -- Verify core sections are present
    assert.truthy(text:find("coding assistant"), "missing persona")
    assert.truthy(text:find("bash: Execute shell commands"), "missing bash snippet")
    assert.truthy(text:find("- custom\n"), "missing custom tool without snippet")
    assert.truthy(text:find("Be careful with destructive commands"), "missing guideline")
    assert.truthy(text:find("Working directory"), "missing environment")
  end)

  it("tool definitions without personalities field appear with empty parts", function()
    local builder_mod = require("flemma.personalities.builder")
    local tools_mod = require("flemma.tools")
    local sorted = tools_mod.get_sorted_for_prompt(nil)
    local entries = builder_mod.build_tools("coding-assistant", sorted)

    local custom_entry
    for _, entry in ipairs(entries) do
      if entry.name == "custom" then
        custom_entry = entry
        break
      end
    end

    assert.is_not_nil(custom_entry)
    assert.same({}, custom_entry.parts)
  end)
end)
