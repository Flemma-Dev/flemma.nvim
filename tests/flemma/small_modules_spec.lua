package.loaded["flemma.bridge"] = nil
package.loaded["flemma.messages"] = nil
package.loaded["flemma.utilities.glob"] = nil

local bridge = require("flemma.bridge")
local roles = require("flemma.utilities.roles")
local glob = require("flemma.utilities.glob")

describe("flemma.bridge", function()
  before_each(function()
    package.loaded["flemma.bridge"] = nil
    bridge = require("flemma.bridge")
  end)

  it("raises error when calling unregistered callback", function()
    assert.has_error(function()
      bridge.send_or_execute({ bufnr = 1 })
    end)
  end)

  it("dispatches send_or_execute after registration", function()
    local called_with = nil
    bridge.register("send_or_execute", function(opts)
      called_with = opts
    end)
    bridge.send_or_execute({ bufnr = 42 })
    assert.are.same({ bufnr = 42 }, called_with)
  end)

  it("dispatches cancel_request with opts after registration", function()
    local called_opts = nil
    bridge.register("cancel_request", function(opts)
      called_opts = opts
    end)
    bridge.cancel_request({ bufnr = 99 })
    assert.are.same({ bufnr = 99 }, called_opts)
  end)

  it("dispatches update_ui after registration", function()
    local called_bufnr = nil
    bridge.register("update_ui", function(bufnr)
      called_bufnr = bufnr
    end)
    bridge.update_ui(7)
    assert.are.equal(7, called_bufnr)
  end)

  it("dispatches auto_prompt after registration", function()
    local called_bufnr = nil
    bridge.register("auto_prompt", function(bufnr)
      called_bufnr = bufnr
    end)
    bridge.auto_prompt(5)
    assert.are.equal(5, called_bufnr)
  end)
end)

describe("flemma.messages", function()
  local messages

  before_each(function()
    package.loaded["flemma.messages"] = nil
    messages = require("flemma.messages")
  end)

  describe("render", function()
    it("renders job-executing--tracked template with variables", function()
      local result = messages.render("job-executing--tracked", { job_id = "job_test1" })
      assert.is_string(result)
      assert.truthy(result:match("job_test1"))
      assert.truthy(result:match("flemma%.jobs%.status"))
      assert.truthy(result:match("Do not retry"))
    end)

    it("renders job-executing--untracked template without job_id", function()
      local result = messages.render("job-executing--untracked")
      assert.is_string(result)
      assert.truthy(result:match("Do not retry"))
      assert.is_falsy(result:match("flemma%.jobs%.status"))
      assert.is_falsy(result:match("job_id"))
    end)

    it("errors for non-existent template", function()
      assert.has_error(function()
        messages.render("nonexistent_template")
      end, nil)
    end)

    it("uses the templating engine for expression evaluation", function()
      local result = messages.render("job-executing--tracked", { job_id = "job_expr" })
      assert.is_string(result)
      assert.truthy(result:match("job_expr"))
      assert.is_falsy(result:match("{{"))
    end)

    it("substitutes different job_ids correctly", function()
      local result_a = messages.render("job-executing--tracked", { job_id = "job_aaa" })
      local result_b = messages.render("job-executing--tracked", { job_id = "job_bbb" })
      assert.truthy(result_a:match("job_aaa"))
      assert.is_falsy(result_a:match("job_bbb"))
      assert.truthy(result_b:match("job_bbb"))
      assert.is_falsy(result_b:match("job_aaa"))
    end)
  end)
end)

describe("utilities.tools", function()
  local tool_names

  before_each(function()
    package.loaded["flemma.utilities.tools"] = nil
    tool_names = require("flemma.utilities.tools")
  end)

  describe("encode_tool_name", function()
    it("replaces dot with wire separator", function()
      assert.equals("slack__channels_list", tool_names.encode_tool_name("slack.channels_list"))
    end)

    it("handles multiple dots", function()
      assert.equals("server__group__tool", tool_names.encode_tool_name("server.group.tool"))
    end)

    it("passes through names without dots", function()
      assert.equals("bash", tool_names.encode_tool_name("bash"))
    end)

    it("passes through empty string", function()
      assert.equals("", tool_names.encode_tool_name(""))
    end)
  end)

  describe("decode_tool_name", function()
    it("replaces wire separator with dot", function()
      assert.equals("slack.channels_list", tool_names.decode_tool_name("slack__channels_list"))
    end)

    it("handles multiple wire separators", function()
      assert.equals("server.group.tool", tool_names.decode_tool_name("server__group__tool"))
    end)

    it("passes through names without wire separator", function()
      assert.equals("bash", tool_names.decode_tool_name("bash"))
    end)

    it("passes through empty string", function()
      assert.equals("", tool_names.decode_tool_name(""))
    end)
  end)

  describe("round-trip", function()
    it("encode then decode returns original", function()
      local original = "slack.channels_list"
      assert.equals(original, tool_names.decode_tool_name(tool_names.encode_tool_name(original)))
    end)

    it("decode then encode returns original", function()
      local wire = "slack__channels_list"
      assert.equals(wire, tool_names.encode_tool_name(tool_names.decode_tool_name(wire)))
    end)
  end)
end)

describe("flemma.utilities.roles", function()
  describe("constants", function()
    it("exposes buffer-format role names", function()
      assert.equals("You", roles.YOU)
      assert.equals("Assistant", roles.ASSISTANT)
      assert.equals("System", roles.SYSTEM)
    end)
  end)

  describe("to_key()", function()
    it("maps 'You' to 'user'", function()
      assert.equals("user", roles.to_key("You"))
    end)

    it("maps 'Assistant' to 'assistant'", function()
      assert.equals("assistant", roles.to_key("Assistant"))
    end)

    it("maps 'System' to 'system'", function()
      assert.equals("system", roles.to_key("System"))
    end)

    it("lowercases unknown roles as fallback", function()
      assert.equals("custom", roles.to_key("Custom"))
    end)
  end)

  describe("is_user()", function()
    it("returns true for 'You'", function()
      assert.is_true(roles.is_user("You"))
    end)

    it("returns false for 'Assistant'", function()
      assert.is_false(roles.is_user("Assistant"))
    end)

    it("returns false for 'System'", function()
      assert.is_false(roles.is_user("System"))
    end)
  end)

  describe("capitalize()", function()
    it("capitalizes 'user' to 'User'", function()
      assert.equals("User", roles.capitalize("user"))
    end)

    it("capitalizes 'assistant' to 'Assistant'", function()
      assert.equals("Assistant", roles.capitalize("assistant"))
    end)

    it("capitalizes single character", function()
      assert.equals("A", roles.capitalize("a"))
    end)
  end)

  describe("highlight_group()", function()
    it("builds FlemmaRoleUser from prefix and 'You'", function()
      assert.equals("FlemmaRoleUser", roles.highlight_group("FlemmaRole", "You"))
    end)

    it("builds FlemmaLineAssistant from prefix and 'Assistant'", function()
      assert.equals("FlemmaLineAssistant", roles.highlight_group("FlemmaLine", "Assistant"))
    end)

    it("builds FlemmaRulerSystem from prefix and 'System'", function()
      assert.equals("FlemmaRulerSystem", roles.highlight_group("FlemmaRuler", "System"))
    end)

    it("builds FlemmaUser from 'Flemma' prefix and 'You'", function()
      assert.equals("FlemmaUser", roles.highlight_group("Flemma", "You"))
    end)
  end)
end)

describe("flemma.templating.renderer", function()
  local renderer

  before_each(function()
    package.loaded["flemma.templating.renderer"] = nil
    renderer = require("flemma.templating.renderer")
  end)

  local function render_text(template, env)
    return renderer.parts_to_text(renderer.render(template, env))
  end

  describe("template rendering", function()
    it("renders expression variables", function()
      assert.are.equal("hello", render_text("{{ greeting }}", { greeting = "hello" }))
    end)

    it("renders code block conditionals", function()
      local template = "{% if active then %}yes{% else %}no{% end %}"
      assert.are.equal("yes", render_text(template, { active = true }))
      assert.are.equal("no", render_text(template, { active = false }))
    end)

    it("supports whitespace trimming for multiline strings", function()
      local template = [[
{{ model.name }}
{%- if thinking.enabled then %} ({{ thinking.level }}){% end -%}
]]
      local env = {
        model = { name = "claude-sonnet-4-5" },
        thinking = { enabled = true, level = "high" },
      }
      assert.are.equal("claude-sonnet-4-5 (high)", render_text(template, env))
    end)
  end)

  describe("lazy evaluation and explicit compilation", function()
    it("only resolves accessed nested values", function()
      local token_accesses = 0
      local env = {
        model = { name = "o3" },
        buffer = {
          tokens = setmetatable({}, {
            __index = function(_, key)
              if key == "input" then
                token_accesses = token_accesses + 1
                return 123
              end
              return nil
            end,
          }),
        },
      }

      assert.are.equal("o3", render_text("{{ model.name }}", env))
      assert.are.equal(0, token_accesses)
    end)

    it("returns reusable render functions without global caching", function()
      local render = renderer.compile("{{ value }}")

      assert.are.equal("one", renderer.parts_to_text(render({ value = "one" })))
      assert.are.equal("two", renderer.parts_to_text(render({ value = "two" })))
    end)
  end)
end)

describe("flemma.templating.builtins.format", function()
  local format

  before_each(function()
    package.loaded["flemma.templating.builtins.format"] = nil
    format = require("flemma.templating.builtins.format")
  end)

  it("exports display formatting functions", function()
    assert.are.equal("12,345", format.exports.number(12345))
    assert.are.equal("15K", format.exports.tokens(15000))
    assert.are.equal("$0.375", format.exports.money(0.375))
    assert.are.equal("17%", format.exports.percent(0.17, 0))
    assert.are.equal("17.3%", format.exports.percent(0.1734, 1))
  end)

  it("populates the template environment as format", function()
    local env = {}
    format.populate(env)

    assert.are.equal(format.exports, env.format)
  end)
end)

describe("flemma.utilities.glob", function()
  describe("is_glob", function()
    it("returns true when string contains *", function()
      assert.is_true(glob.is_glob("github.*"))
    end)

    it("returns false for plain strings", function()
      assert.is_false(glob.is_glob("github.create_issue"))
    end)

    it("returns false for empty string", function()
      assert.is_false(glob.is_glob(""))
    end)
  end)

  describe("match", function()
    it("matches a trailing wildcard", function()
      assert.is_true(glob.match("github.create_issue", "github.*"))
    end)

    it("rejects a non-matching name", function()
      assert.is_false(glob.match("slack.post_message", "github.*"))
    end)

    it("matches an exact name without wildcards", function()
      assert.is_true(glob.match("read", "read"))
    end)

    it("rejects a partial exact mismatch", function()
      assert.is_false(glob.match("readonly", "read"))
    end)

    it("matches a leading wildcard", function()
      assert.is_true(glob.match("github.create_issue", "*.create_issue"))
    end)

    it("matches a middle wildcard", function()
      assert.is_true(glob.match("github.v2.create_issue", "github.*.create_issue"))
    end)

    it("matches a bare wildcard against anything", function()
      assert.is_true(glob.match("anything", "*"))
    end)

    it("escapes lua pattern metacharacters in the glob", function()
      assert.is_true(glob.match("my-tool.v1+beta", "my-tool.v1+beta"))
      assert.is_false(glob.match("my-toolXv1Xbeta", "my-tool.v1+beta"))
    end)
  end)

  describe("matches_any", function()
    it("returns true when any pattern matches", function()
      assert.is_true(glob.matches_any("github.create_issue", { "slack.*", "github.*" }))
    end)

    it("returns false when no pattern matches", function()
      assert.is_false(glob.matches_any("trello.create_card", { "slack.*", "github.*" }))
    end)

    it("handles a mix of exact names and globs", function()
      assert.is_true(glob.matches_any("read", { "read", "github.*" }))
      assert.is_true(glob.matches_any("github.list_repos", { "read", "github.*" }))
      assert.is_false(glob.matches_any("write", { "read", "github.*" }))
    end)

    it("returns false for an empty pattern list", function()
      assert.is_false(glob.matches_any("anything", {}))
    end)
  end)
end)
