--- Test file for Claude provider functionality
describe("Claude Provider", function()
  local claude = require("flemma.provider.providers.claude")

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  describe("try_import_from_buffer", function()
    it("should import Claude Workbench JavaScript code to chat format", function()
      local provider = claude.new({ model = "claude-3-5-sonnet" })

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

    it("should return nil when no Claude API call is found", function()
      local provider = claude.new({ model = "claude-3-5-sonnet" })

      local input_lines = {
        'console.log("Hello World");',
        "const x = 42;",
      }

      local result = provider:try_import_from_buffer(input_lines)

      assert.is_nil(result, "Should return nil when no API call found")
    end)

    it("should handle malformed JSON gracefully", function()
      local provider = claude.new({ model = "claude-3-5-sonnet" })

      local input_lines = {
        "const msg = await anthropic.messages.create({",
        '  model: "claude-3-5-sonnet",',
        "  malformed: json content here",
        "  messages: [",
        "});",
      }

      local result = provider:try_import_from_buffer(input_lines)

      assert.is_nil(result, "Should return nil when JSON is malformed")
    end)

    it("should handle messages with string content format", function()
      local provider = claude.new({ model = "claude-3-5-sonnet" })

      local input_lines = {
        "const msg = await anthropic.messages.create({",
        '  model: "claude-3-5-sonnet",',
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
end)
