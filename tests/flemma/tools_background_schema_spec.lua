describe("background parameter schema injection", function()
  local tools_module

  before_each(function()
    package.loaded["flemma.tools"] = nil
    tools_module = require("flemma.tools")
  end)

  it("injects background param for async tools", function()
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
    assert.truthy(schema.properties.background)
    assert.equals("boolean", schema.properties.background.type)
    assert.equals(false, schema.properties.background.default)
    assert.is_nil(async_tool.input_schema.properties.background)
  end)

  it("does not inject for sync tools", function()
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
    assert.is_nil(schema.properties.background)
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
    assert.is_nil(schema.properties.background)
  end)
end)
