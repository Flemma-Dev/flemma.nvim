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
