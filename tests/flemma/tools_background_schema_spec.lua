describe("harness parameter schema injection", function()
  local tools_module

  before_each(function()
    package.loaded["flemma.tools"] = nil
    tools_module = require("flemma.tools")
  end)

  it("injects flemma:background param for async tools", function()
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
    assert.truthy(schema.properties["flemma:background"])
    assert.equals("boolean", schema.properties["flemma:background"].type)
    assert.equals(false, schema.properties["flemma:background"].default)
    assert.is_nil(async_tool.input_schema.properties["flemma:background"])
  end)

  it("does not inject flemma:background for sync tools", function()
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
    assert.is_nil(schema.properties["flemma:background"])
  end)

  it("respects backgroundable = false opt-out", function()
    ---@type flemma.tools.ToolDefinition
    local tool = {
      name = "test_no_bg",
      description = "Async but not backgroundable",
      async = true,
      backgroundable = false,
      input_schema = {
        type = "object",
        properties = {
          data = { type = "string" },
        },
      },
    }

    local schema = tools_module.to_json_schema_for_prompt(tool)
    assert.is_nil(schema.properties["flemma:background"])
  end)

  it("injects flemma:save_to for all tools", function()
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
    assert.truthy(schema.properties["flemma:save_to"])
    assert.equals("string", schema.properties["flemma:save_to"].type)
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
    assert.is_nil(tool.input_schema.properties["flemma:background"])
    assert.is_nil(tool.input_schema.properties["flemma:save_to"])
  end)

  it("preserves colon in property names through JSON encoding", function()
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
    assert.is_truthy(encoded:find('"flemma:background"'), "colon in flemma:background preserved")
    assert.is_truthy(encoded:find('"flemma:save_to"'), "colon in flemma:save_to preserved")
  end)
end)
