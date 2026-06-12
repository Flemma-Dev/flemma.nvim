describe("harness parameter schema injection", function()
  local tools_module

  before_each(function()
    package.loaded["flemma.tools"] = nil
    tools_module = require("flemma.tools")
  end)

  it("injects flemma.background param for async tools", function()
    ---@type flemma.tools.ToolDefinition
    local async_tool = {
      name = "test_async",
      description = "An async tool",
      async = true,
      input_schema = {
        type = "object",
        properties = {
          command = { type = "string", description = "The command" },
        },
        required = { "command" },
      },
    }

    local schema = tools_module.to_json_schema_for_prompt(async_tool)
    assert.truthy(schema.properties["flemma.background"])
    assert.equals("boolean", schema.properties["flemma.background"].type)
    assert.equals(false, schema.properties["flemma.background"].default)
    assert.is_nil(async_tool.input_schema.properties["flemma.background"])
  end)

  it("does not inject flemma.background for sync tools", function()
    ---@type flemma.tools.ToolDefinition
    local sync_tool = {
      name = "test_sync",
      description = "A sync tool",
      input_schema = {
        type = "object",
        properties = {
          path = { type = "string" },
        },
      },
    }

    local schema = tools_module.to_json_schema_for_prompt(sync_tool)
    assert.is_nil(schema.properties["flemma.background"])
  end)

  it("respects disables_background capability opt-out", function()
    local registry = require("flemma.tools.registry")
    ---@type flemma.tools.ToolDefinition
    local tool = {
      name = "test_no_bg",
      description = "Async but not backgroundable",
      async = true,
      capabilities = { "disables_background" },
      input_schema = {
        type = "object",
        properties = {
          data = { type = "string" },
        },
      },
    }
    registry.register("test_no_bg", tool)

    local schema = tools_module.to_json_schema_for_prompt(tool)
    assert.is_nil(schema.properties["flemma.background"])

    registry.unregister("test_no_bg")
  end)

  it("injects flemma.save_to for all tools", function()
    ---@type flemma.tools.ToolDefinition
    local sync_tool = {
      name = "test_sync",
      description = "A sync tool",
      input_schema = {
        type = "object",
        properties = {
          path = { type = "string" },
        },
      },
    }

    local schema = tools_module.to_json_schema_for_prompt(sync_tool)
    assert.truthy(schema.properties["flemma.save_to"])
    assert.equals("string", schema.properties["flemma.save_to"].type)
  end)

  it("does not mutate original input_schema", function()
    ---@type flemma.tools.ToolDefinition
    local tool = {
      name = "test_immutable",
      description = "Test",
      async = true,
      input_schema = {
        type = "object",
        properties = {
          x = { type = "string" },
        },
      },
    }

    tools_module.to_json_schema_for_prompt(tool)
    assert.is_nil(tool.input_schema.properties["flemma.background"])
    assert.is_nil(tool.input_schema.properties["flemma.save_to"])
  end)

  it("preserves dot in property names through JSON encoding", function()
    local json = require("flemma.utilities.json")
    ---@type flemma.tools.ToolDefinition
    local tool = {
      name = "test_json",
      description = "Test",
      async = true,
      input_schema = {
        type = "object",
        properties = {
          cmd = { type = "string" },
        },
      },
    }

    local schema = tools_module.to_json_schema_for_prompt(tool)
    local encoded = json.encode(schema)
    assert.is_truthy(encoded:find('"flemma.background"'), "dot in flemma.background preserved")
    assert.is_truthy(encoded:find('"flemma.save_to"'), "dot in flemma.save_to preserved")
  end)

  it("uses nullable types and adds to required for strict schemas", function()
    ---@type flemma.tools.ToolDefinition
    local tool = {
      name = "test_strict",
      description = "Strict tool",
      async = true,
      strict = true,
      input_schema = {
        type = "object",
        properties = {
          command = { type = "string" },
        },
        required = { "command" },
        additionalProperties = false,
      },
    }

    local schema = tools_module.to_json_schema_for_prompt(tool)
    assert.are.same({ "boolean", "null" }, schema.properties["flemma.background"].type)
    assert.are.same({ "string", "null" }, schema.properties["flemma.save_to"].type)
    assert.is_truthy(vim.tbl_contains(schema.required, "flemma.background"))
    assert.is_truthy(vim.tbl_contains(schema.required, "flemma.save_to"))
    assert.is_truthy(vim.tbl_contains(schema.required, "command"))
  end)

  it("uses plain types for non-strict schemas", function()
    ---@type flemma.tools.ToolDefinition
    local tool = {
      name = "test_non_strict",
      description = "Non-strict tool",
      async = true,
      input_schema = {
        type = "object",
        properties = {
          command = { type = "string" },
        },
        required = { "command" },
      },
    }

    local schema = tools_module.to_json_schema_for_prompt(tool)
    assert.equals("boolean", schema.properties["flemma.background"].type)
    assert.equals("string", schema.properties["flemma.save_to"].type)
  end)
end)
