--- Tests for config.apply_operators (JSON frontmatter operator dispatch)
--- and the JSON codeblock parser's config integration.

local s = require("flemma.schema")

--- Build a test schema with scalars, lists, objects, and hybrid nodes.
---@return flemma.schema.ObjectNode
local function test_schema()
  return s.object({
    provider = s.string("anthropic"),
    model = s.string("claude-sonnet-4-20250514"),
    parameters = s.object({
      temperature = s.number(0.7),
      max_tokens = s.optional(s.integer()),
    }),
    tools = s.object({
      auto_approve = s.list(s.string(), {}),
      autopilot = s.object({
        enabled = s.boolean(true),
      }):coerce(function(value)
        if type(value) == "boolean" then
          return { enabled = value }
        end
        return value
      end),
    }):allow_list(s.string()),
    tags = s.list(s.string(), {}),
  })
end

describe("config.apply_operators", function()
  local config, store

  before_each(function()
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.operators"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    config = require("flemma.config")
    store = require("flemma.config.store")
    config.init(test_schema())
  end)

  -- =========================================================================
  -- Scalar set (plain value)
  -- =========================================================================

  describe("scalar set", function()
    it("records a set op for a plain string value", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        provider = "openai",
      })

      assert.are.same({}, failures)
      local value = store.resolve("provider", bufnr)
      assert.are.equal("openai", value)
    end)

    it("records a set op for a numeric value", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        parameters = { temperature = 0.5 },
      })

      assert.are.same({}, failures)
      local value = store.resolve("parameters.temperature", bufnr)
      assert.are.equal(0.5, value)
    end)
  end)

  -- =========================================================================
  -- List set (array on list-capable node)
  -- =========================================================================

  describe("list set", function()
    it("sets a list on a pure ListNode", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tags = { "debug", "test" },
      })

      assert.are.same({}, failures)
      local value = store.resolve("tags", bufnr, { is_list = true })
      assert.are.same({ "debug", "test" }, value)
    end)

    it("sets a list on a hybrid ObjectNode (allow_list)", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tools = { "bash", "read" },
      })

      assert.are.same({}, failures)
      local value = store.resolve("tools", bufnr, { is_list = true })
      assert.are.same({ "bash", "read" }, value)
    end)
  end)

  -- =========================================================================
  -- $set operator (explicit)
  -- =========================================================================

  describe("$set operator", function()
    it("behaves like a plain value for scalars", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        provider = { ["$set"] = "openai" },
      })

      assert.are.same({}, failures)
      assert.are.equal("openai", store.resolve("provider", bufnr))
    end)

    it("behaves like a plain array for lists", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tags = { ["$set"] = { "a", "b" } },
      })

      assert.are.same({}, failures)
      assert.are.same({ "a", "b" }, store.resolve("tags", bufnr, { is_list = true }))
    end)
  end)

  -- =========================================================================
  -- Coerce on object nodes (e.g., autopilot: false → { enabled: false })
  -- =========================================================================

  describe("coerce on object nodes", function()
    it("coerces a boolean to an object via the node's coerce function", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tools = { autopilot = false },
      })

      assert.are.same({}, failures)
      assert.is_false(store.resolve("tools.autopilot.enabled", bufnr))
    end)
  end)

  -- =========================================================================
  -- $append operator
  -- =========================================================================

  describe("$append operator", function()
    it("appends a single item to a list", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tags = { ["$append"] = "new-tag" },
      })

      assert.are.same({}, failures)
      local ops = store.dump_layer(config.LAYERS.FRONTMATTER, bufnr)
      assert.are.equal(1, #ops)
      assert.are.equal("append", ops[1].op)
      assert.are.equal("tags", ops[1].path)
      assert.are.equal("new-tag", ops[1].value)
    end)

    it("appends multiple items from an array", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tags = { ["$append"] = { "a", "b" } },
      })

      assert.are.same({}, failures)
      local ops = store.dump_layer(config.LAYERS.FRONTMATTER, bufnr)
      assert.are.equal(2, #ops)
      assert.are.equal("append", ops[1].op)
      assert.are.equal("a", ops[1].value)
      assert.are.equal("append", ops[2].op)
      assert.are.equal("b", ops[2].value)
    end)

    it("appends to a hybrid ObjectNode list part", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tools = { ["$append"] = { "slack", "mcp" } },
      })

      assert.are.same({}, failures)
      local ops = store.dump_layer(config.LAYERS.FRONTMATTER, bufnr)
      assert.are.equal(2, #ops)
      assert.are.equal("append", ops[1].op)
      assert.are.equal("tools", ops[1].path)
      assert.are.equal("slack", ops[1].value)
      assert.are.equal("mcp", ops[2].value)
    end)
  end)

  -- =========================================================================
  -- $remove operator
  -- =========================================================================

  describe("$remove operator", function()
    it("records remove ops without item validation", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tags = { ["$remove"] = "old-tag" },
      })

      assert.are.same({}, failures)
      local ops = store.dump_layer(config.LAYERS.FRONTMATTER, bufnr)
      assert.are.equal(1, #ops)
      assert.are.equal("remove", ops[1].op)
      assert.are.equal("old-tag", ops[1].value)
    end)
  end)

  -- =========================================================================
  -- $prepend operator
  -- =========================================================================

  describe("$prepend operator", function()
    it("records prepend ops for an array", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tags = { ["$prepend"] = { "first", "second" } },
      })

      assert.are.same({}, failures)
      local ops = store.dump_layer(config.LAYERS.FRONTMATTER, bufnr)
      assert.are.equal(2, #ops)
      assert.are.equal("prepend", ops[1].op)
      assert.are.equal("first", ops[1].value)
      assert.are.equal("prepend", ops[2].op)
      assert.are.equal("second", ops[2].value)
    end)
  end)

  -- =========================================================================
  -- Mixed operators and regular keys
  -- =========================================================================

  describe("mixed operators and regular keys", function()
    it("handles $append on list part + regular key on object part", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tools = {
          ["$append"] = { "slack" },
          auto_approve = { "bash" },
        },
      })

      assert.are.same({}, failures)
      local ops = store.dump_layer(config.LAYERS.FRONTMATTER, bufnr)

      -- Should have: append "slack" to tools + set auto_approve to ["bash"]
      local append_ops = vim.tbl_filter(function(op)
        return op.op == "append" and op.path == "tools"
      end, ops)
      local set_ops = vim.tbl_filter(function(op)
        return op.op == "set" and op.path == "tools.auto_approve"
      end, ops)

      assert.are.equal(1, #append_ops)
      assert.are.equal("slack", append_ops[1].value)
      assert.are.equal(1, #set_ops)
      assert.are.same({ "bash" }, set_ops[1].value)
    end)

    it("handles multiple config paths in one object", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        provider = "openai",
        model = "gpt-4o",
        parameters = { temperature = 0.5 },
        tags = { ["$append"] = "debug" },
      })

      assert.are.same({}, failures)
      assert.are.equal("openai", store.resolve("provider", bufnr))
      assert.are.equal("gpt-4o", store.resolve("model", bufnr))
      assert.are.equal(0.5, store.resolve("parameters.temperature", bufnr))
    end)
  end)

  -- =========================================================================
  -- Error cases
  -- =========================================================================

  describe("error cases", function()
    it("reports unknown config keys", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        nonexistent = "value",
      })

      assert.are.equal(1, #failures)
      assert.is_truthy(failures[1].message:find("unknown config key"))
    end)

    it("reports unknown operators", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tags = { ["$merge"] = { "a" } },
      })

      assert.are.equal(1, #failures)
      assert.is_truthy(failures[1].message:find("unknown operator"))
    end)

    it("reports $append on non-list field", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        provider = { ["$append"] = "openai" },
      })

      assert.are.equal(1, #failures)
      assert.is_truthy(failures[1].message:find("list%-capable"))
    end)

    it("reports array values on scalar fields", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        provider = { "openai", "vertex" },
      })

      assert.are.equal(1, #failures)
      assert.is_truthy(failures[1].message:find("does not accept array"))
    end)

    it("reports validation errors for invalid list items", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        tags = { 123 },
      })

      assert.are.equal(1, #failures)
    end)

    it("continues processing after errors (collects all failures)", function()
      local bufnr = 1
      store.clear(config.LAYERS.FRONTMATTER, bufnr)

      local failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, {
        nonexistent_a = "one",
        nonexistent_b = "two",
      })

      assert.are.equal(2, #failures)
    end)
  end)
end)

-- ===========================================================================
-- JSON parser integration
-- ===========================================================================

describe("codeblock.parsers.json config integration", function()
  local config, store, json_parser

  before_each(function()
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.operators"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.codeblock.parsers.json"] = nil
    config = require("flemma.config")
    store = require("flemma.config.store")
    json_parser = require("flemma.codeblock.parsers.json")
    config.init(test_schema())
  end)

  it("processes flemma key as config operations when bufnr provided", function()
    local bufnr = 1
    store.clear(config.LAYERS.FRONTMATTER, bufnr)

    local variables, failures =
      json_parser.parse('{ "flemma": { "provider": "openai", "tags": ["debug"] } }', nil, bufnr)

    assert.are.same({}, variables)
    assert.is_nil(failures)
    assert.are.equal("openai", store.resolve("provider", bufnr))
    assert.are.same({ "debug" }, store.resolve("tags", bufnr, { is_list = true }))
  end)

  it("returns non-flemma keys as template variables", function()
    local bufnr = 1
    store.clear(config.LAYERS.FRONTMATTER, bufnr)

    local variables = json_parser.parse('{ "flemma": { "provider": "openai" }, "title": "My Chat" }', nil, bufnr)

    assert.are.equal("My Chat", variables.title)
  end)

  it("treats flemma key as a regular variable without bufnr", function()
    local variables = json_parser.parse('{ "flemma": { "provider": "openai" } }', nil, nil)

    assert.is_not_nil(variables.flemma)
    assert.are.equal("openai", variables.flemma.provider)
  end)

  it("processes $append operator through JSON", function()
    local bufnr = 1
    store.clear(config.LAYERS.FRONTMATTER, bufnr)

    local variables, failures = json_parser.parse('{ "flemma": { "tags": { "$append": ["new-tag"] } } }', nil, bufnr)

    assert.are.same({}, variables)
    assert.is_nil(failures)
    local ops = store.dump_layer(config.LAYERS.FRONTMATTER, bufnr)
    assert.are.equal(1, #ops)
    assert.are.equal("append", ops[1].op)
    assert.are.equal("new-tag", ops[1].value)
  end)

  it("returns validation failures for bad config", function()
    local bufnr = 1
    store.clear(config.LAYERS.FRONTMATTER, bufnr)

    local _, failures = json_parser.parse('{ "flemma": { "nonexistent": "value" } }', nil, bufnr)

    assert.is_not_nil(failures)
    assert.is_truthy(#failures > 0)
  end)

  it("raises on malformed JSON", function()
    assert.has_error(function()
      json_parser.parse("{ bad json", nil, nil)
    end)
  end)

  it("raises when flemma value is not an object", function()
    assert.has_error(function()
      json_parser.parse('{ "flemma": ["not", "an", "object"] }', nil, 1)
    end)
  end)
end)

-- ===========================================================================
-- E2E: buffer with ```json frontmatter through full pipeline
-- ===========================================================================

describe("JSON frontmatter E2E", function()
  local flemma, config, processor

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.processor"] = nil
    package.loaded["flemma.pipeline"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.codeblock.parsers"] = nil
    package.loaded["flemma.codeblock.parsers.json"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.operators"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil

    flemma = require("flemma")
    config = require("flemma.config")
    processor = require("flemma.processor")

    flemma.setup({
      parameters = { thinking = false },
      tools = { autopilot = { enabled = true } },
    })
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("scalar override: JSON frontmatter sets temperature via config facade", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```json",
      '{ "flemma": { "parameters": { "temperature": 0.2 } } }',
      "```",
      "",
      "@You:",
      "Hello",
    })

    local result = processor.evaluate_buffer_frontmatter(bufnr)

    assert.are.same({}, result.diagnostics)
    assert.are.equal(0.2, config.get(bufnr).parameters.temperature)
  end)

  it("list set: JSON frontmatter replaces tools list", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```json",
      '{ "flemma": { "tools": { "auto_approve": ["bash"] } } }',
      "```",
      "",
      "@You:",
      "Hello",
    })

    local result = processor.evaluate_buffer_frontmatter(bufnr)

    assert.are.same({}, result.diagnostics)
    local cfg = config.get(bufnr)
    assert.are.same({ "bash" }, cfg.tools.auto_approve)
  end)

  it("$append: JSON frontmatter appends to auto_approve list", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```json",
      '{ "flemma": { "tools": { "auto_approve": { "$append": "bash" } } } }',
      "```",
      "",
      "@You:",
      "Hello",
    })

    local result = processor.evaluate_buffer_frontmatter(bufnr)

    assert.are.same({}, result.diagnostics)
    local resolved = config.get(bufnr).tools.auto_approve
    -- append adds to the default (empty) list
    assert.is_true(vim.tbl_contains(resolved, "bash"))
  end)

  it("mixed: operators + object keys in same JSON object", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```json",
      '{ "flemma": { "tools": { "auto_approve": ["bash"], "autopilot": { "enabled": false } } } }',
      "```",
      "",
      "@You:",
      "Hello",
    })

    local result = processor.evaluate_buffer_frontmatter(bufnr)

    assert.are.same({}, result.diagnostics)
    local cfg = config.get(bufnr)
    assert.are.same({ "bash" }, cfg.tools.auto_approve)
    assert.is_false(cfg.tools.autopilot.enabled)
  end)

  it("template variables: non-flemma keys are available in context", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```json",
      '{ "flemma": { "parameters": { "temperature": 0.1 } }, "persona": "helpful assistant" }',
      "```",
      "",
      "@You:",
      "Hello",
    })

    local result = processor.evaluate_buffer_frontmatter(bufnr)

    assert.are.same({}, result.diagnostics)
    assert.are.equal("helpful assistant", result.context:get_variables()["persona"])
    assert.are.equal(0.1, config.get(bufnr).parameters.temperature)
  end)

  it("validation failures: unknown keys produce diagnostics, not crashes", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```json",
      '{ "flemma": { "nonexistent_key": "value" } }',
      "```",
      "",
      "@You:",
      "Hello",
    })

    local result = processor.evaluate_buffer_frontmatter(bufnr)

    -- Should produce diagnostics for unknown keys, not crash
    assert.is_true(#result.diagnostics > 0)
    assert.are.equal("config", result.diagnostics[1].type)
    assert.are.equal("error", result.diagnostics[1].severity)
    assert.is_truthy(result.diagnostics[1].error:find("unknown config key"))
  end)

  it("autopilot disable: JSON frontmatter disables autopilot for buffer", function()
    local autopilot = require("flemma.autopilot")
    local client = require("flemma.client")
    local core = require("flemma.core")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```json",
      '{ "flemma": { "tools": { "autopilot": { "enabled": false } } } }',
      "```",
      "",
      "@You:",
      "Hello",
    })

    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")
    core.send_or_execute({ bufnr = bufnr })

    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i, line in ipairs(lines) do
        if line == "@You:" and lines[i + 1] == "" then
          return true
        end
      end
      return false
    end)

    assert.is_false(autopilot.is_enabled(bufnr))
    client.clear_fixtures()
  end)

  it("coerce shorthand: autopilot: false is coerced to { enabled: false }", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```json",
      '{ "flemma": { "tools": { "autopilot": false } } }',
      "```",
      "",
      "@You:",
      "Hello",
    })

    local result = processor.evaluate_buffer_frontmatter(bufnr)

    assert.are.same({}, result.diagnostics)
    assert.is_false(config.get(bufnr).tools.autopilot.enabled)
  end)
end)
