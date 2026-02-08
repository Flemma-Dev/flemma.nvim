--- Test file for Anthropic provider functionality

-- Ensure tools module loads fresh
package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.definitions.calculator"] = nil
package.loaded["flemma.tools.definitions.bash"] = nil
package.loaded["flemma.tools.definitions.read"] = nil
package.loaded["flemma.tools.definitions.edit"] = nil
package.loaded["flemma.tools.definitions.write"] = nil

describe("Anthropic Provider", function()
  local anthropic = require("flemma.provider.providers.anthropic")
  local tools = require("flemma.tools")

  before_each(function()
    tools.clear()
    tools.setup()
  end)

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  describe("try_import_from_buffer", function()
    it("should import Claude Workbench JavaScript code to chat format", function()
      local provider = anthropic.new({ model = "claude-sonnet-4-5" })

      -- JavaScript code from Claude Workbench
      local input_lines = {
        'import Anthropic from "@anthropic-ai/sdk";',
        "",
        "const anthropic = new Anthropic({",
        '  // defaults to process.env["ANTHROPIC_API_KEY"]',
        '  apiKey: "my_api_key",',
        "});",
        "",
        "const msg = await anthropic.messages.create({",
        '  model: "claude-sonnet-4-20250514",',
        "  max_tokens: 20000,",
        "  temperature: 1,",
        '  system: "Be brief!",',
        "  messages: [",
        "    {",
        '      "role": "user",',
        '      "content": [',
        "        {",
        '          "type": "text",',
        '          "text": "Hello, World!"',
        "        }",
        "      ]",
        "    },",
        "    {",
        '      "role": "assistant",',
        '      "content": [',
        "        {",
        '          "type": "text",',
        '          "text": "Hello! Nice to meet you! How are you doing today?"',
        "        }",
        "      ]",
        "    },",
        "    {",
        '      "role": "user",',
        '      "content": [',
        "        {",
        '          "type": "text",',
        '          "text": "Fin."',
        "        }",
        "      ]",
        "    }",
        "  ]",
        "});",
        "console.log(msg);",
      }

      -- Expected output in chat format
      local expected_chat =
        "@System: Be brief!\n\n@You: Hello, World!\n\n@Assistant: Hello! Nice to meet you! How are you doing today?\n\n@You: Fin."

      -- Call the import function
      local result = provider:try_import_from_buffer(input_lines)

      -- Verify the result
      assert.is_not_nil(result, "Import should return chat content")
      assert.are.equal(expected_chat, result, "Chat content should match expected format")
    end)

    it("should return nil when no Anthropic API call is found", function()
      local provider = anthropic.new({ model = "claude-sonnet-4-5" })

      local input_lines = {
        'console.log("Hello World");',
        "const x = 42;",
      }

      local result = provider:try_import_from_buffer(input_lines)

      assert.is_nil(result, "Should return nil when no API call found")
    end)

    it("should handle malformed JSON gracefully", function()
      local provider = anthropic.new({ model = "claude-sonnet-4-5" })

      local input_lines = {
        "const msg = await anthropic.messages.create({",
        '  model: "claude-sonnet-4-5",',
        "  malformed: json content here",
        "  messages: [",
        "});",
      }

      local result = provider:try_import_from_buffer(input_lines)

      assert.is_nil(result, "Should return nil when JSON is malformed")
    end)

    it("should handle messages with string content format", function()
      local provider = anthropic.new({ model = "claude-sonnet-4-5" })

      local input_lines = {
        "const msg = await anthropic.messages.create({",
        '  model: "claude-sonnet-4-5",',
        '  system: "You are helpful",',
        "  messages: [",
        "    {",
        '      "role": "user",',
        '      "content": "Simple string message"',
        "    }",
        "  ]",
        "});",
      }

      local expected_chat = "@System: You are helpful\n\n@You: Simple string message"

      local result = provider:try_import_from_buffer(input_lines)

      assert.is_not_nil(result)
      assert.are.equal(expected_chat, result)
    end)
  end)

  describe("prompt caching", function()
    --- Helper to find a tool by name
    local function find_tool(tools_array, name)
      for _, t in ipairs(tools_array) do
        if t.name == name then
          return t
        end
      end
    end

    it("tools are sorted alphabetically by name", function()
      local p = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100, cache_retention = "short" })
      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = nil,
      }
      local req = p:build_request(prompt)
      assert.is_not_nil(req.tools)
      for i = 1, #req.tools - 1 do
        assert.is_true(req.tools[i].name < req.tools[i + 1].name,
          "Expected " .. req.tools[i].name .. " < " .. req.tools[i + 1].name)
      end
    end)

    it("cache_retention=short adds ephemeral breakpoints", function()
      local p = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100, cache_retention = "short" })
      local prompt = {
        history = {
          { role = "user", parts = { { kind = "text", text = "hello" } } },
          { role = "assistant", parts = { { kind = "text", text = "hi" } } },
          { role = "user", parts = { { kind = "text", text = "world" } } },
        },
        system = "Be helpful",
      }
      local req = p:build_request(prompt)

      -- Breakpoint 1: last tool should have cache_control
      local last_tool = req.tools[#req.tools]
      assert.is_not_nil(last_tool.cache_control)
      assert.are.same({ type = "ephemeral" }, last_tool.cache_control)

      -- Breakpoint 2: system should be array format with cache_control
      assert.are.equal("table", type(req.system))
      assert.are.equal(1, #req.system)
      assert.are.equal("Be helpful", req.system[1].text)
      assert.are.same({ type = "ephemeral" }, req.system[1].cache_control)

      -- Breakpoint 3: last user message's last content block has cache_control
      local last_user_msg = req.messages[#req.messages]
      assert.are.equal("user", last_user_msg.role)
      local last_block = last_user_msg.content[#last_user_msg.content]
      assert.are.same({ type = "ephemeral" }, last_block.cache_control)
    end)

    it("cache_retention=long adds ephemeral with 1h TTL", function()
      local p = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100, cache_retention = "long" })
      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = "Be helpful",
      }
      local req = p:build_request(prompt)

      local expected_cc = { type = "ephemeral", ttl = "1h" }

      -- Check tool breakpoint
      local last_tool = req.tools[#req.tools]
      assert.are.same(expected_cc, last_tool.cache_control)

      -- Check system breakpoint
      assert.are.same(expected_cc, req.system[1].cache_control)

      -- Check user message breakpoint
      local last_block = req.messages[1].content[#req.messages[1].content]
      assert.are.same(expected_cc, last_block.cache_control)
    end)

    it("cache_retention=none adds no cache_control, system is string", function()
      local p = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100, cache_retention = "none" })
      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = "Be helpful",
      }
      local req = p:build_request(prompt)

      -- System should be plain string
      assert.are.equal("Be helpful", req.system)

      -- No cache_control on tools
      for _, t in ipairs(req.tools) do
        assert.is_nil(t.cache_control)
      end

      -- No cache_control on user message content
      for _, block in ipairs(req.messages[1].content) do
        assert.is_nil(block.cache_control)
      end
    end)

    it("no crash when no tools present with caching enabled", function()
      local p = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100, cache_retention = "short" })
      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = "Be helpful",
        opts = { tools = {} },
      }
      local req = p:build_request(prompt)
      assert.is_nil(req.tools)
      -- System still gets cache_control
      assert.are.same({ type = "ephemeral" }, req.system[1].cache_control)
    end)

    it("per-buffer thinking_budget override does not mutate self.parameters", function()
      local p = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100, cache_retention = "short" })
      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = nil,
        opts = { anthropic = { thinking_budget = 2048 } },
      }
      local req = p:build_request(prompt)
      assert.is_not_nil(req.thinking)
      assert.are.equal(2048, req.thinking.budget_tokens)
      -- Original parameters untouched
      assert.is_nil(p.parameters.thinking_budget)
    end)

    it("per-buffer cache_retention=none override disables caching", function()
      local p = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100, cache_retention = "short" })
      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = "Be helpful",
        opts = { anthropic = { cache_retention = "none" } },
      }
      local req = p:build_request(prompt)
      -- System should be plain string (no caching)
      assert.are.equal("Be helpful", req.system)
    end)

    it("system uses array format only when caching enabled", function()
      local p = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100, cache_retention = "short" })
      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = "Be helpful",
      }
      local req = p:build_request(prompt)
      assert.are.equal("table", type(req.system))
      assert.are.equal("text", req.system[1].type)
    end)

    it("no system field when system prompt is empty", function()
      local p = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100, cache_retention = "short" })
      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = "",
      }
      local req = p:build_request(prompt)
      assert.is_nil(req.system)
    end)

    it("no system field when system prompt is nil", function()
      local p = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100, cache_retention = "short" })
      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = nil,
      }
      local req = p:build_request(prompt)
      assert.is_nil(req.system)
    end)
  end)
end)
