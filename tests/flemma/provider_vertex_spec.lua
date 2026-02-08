--- Test file for Vertex AI provider functionality

-- Ensure tools module loads fresh
package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.definitions.calculator"] = nil
package.loaded["flemma.tools.definitions.bash"] = nil
package.loaded["flemma.tools.definitions.read"] = nil
package.loaded["flemma.tools.definitions.edit"] = nil
package.loaded["flemma.tools.definitions.write"] = nil

describe("Vertex AI Provider", function()
  local vertex = require("flemma.provider.providers.vertex")
  local tools = require("flemma.tools")

  before_each(function()
    tools.clear()
    tools.setup()
  end)

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  describe("process_response_line", function()
    it("should parse cached content tokens from usageMetadata", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
        max_tokens = 4000,
      })

      local usage_events = {}
      local callbacks = {
        on_content = function() end,
        on_usage = function(data)
          table.insert(usage_events, data)
        end,
        on_response_complete = function() end,
        on_error = function() end,
      }

      -- Simulate a streaming response with cached content tokens
      local line = 'data: {"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"}}],'
        .. '"usageMetadata":{"promptTokenCount":3000,"candidatesTokenCount":50,'
        .. '"cachedContentTokenCount":2048}}'
      provider:process_response_line(line, callbacks)

      -- Should have received input, output, and cache_read usage events
      local found_input = false
      local found_output = false
      local found_cache_read = false
      for _, event in ipairs(usage_events) do
        if event.type == "input" then
          -- input_tokens = promptTokenCount - cachedContentTokenCount (3000 - 2048 = 952)
          assert.equals(952, event.tokens)
          found_input = true
        elseif event.type == "output" then
          assert.equals(50, event.tokens)
          found_output = true
        elseif event.type == "cache_read" then
          assert.equals(2048, event.tokens)
          found_cache_read = true
        end
      end

      assert.is_true(found_input, "Expected input usage event")
      assert.is_true(found_output, "Expected output usage event")
      assert.is_true(found_cache_read, "Expected cache_read usage event")
    end)

    it("should not emit cache_read when cachedContentTokenCount is zero", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
        max_tokens = 4000,
      })

      local usage_events = {}
      local callbacks = {
        on_content = function() end,
        on_usage = function(data)
          table.insert(usage_events, data)
        end,
        on_response_complete = function() end,
        on_error = function() end,
      }

      -- Simulate a response with zero cached tokens
      local line = 'data: {"candidates":[{"content":{"parts":[{"text":"Hi"}],"role":"model"}}],'
        .. '"usageMetadata":{"promptTokenCount":500,"candidatesTokenCount":10,'
        .. '"cachedContentTokenCount":0}}'
      provider:process_response_line(line, callbacks)

      -- Should NOT have a cache_read event
      for _, event in ipairs(usage_events) do
        assert.is_not.equals("cache_read", event.type, "Should not emit cache_read for zero cached tokens")
      end
    end)

    it("should handle missing cachedContentTokenCount gracefully", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
        max_tokens = 4000,
      })

      local usage_events = {}
      local callbacks = {
        on_content = function() end,
        on_usage = function(data)
          table.insert(usage_events, data)
        end,
        on_response_complete = function() end,
        on_error = function() end,
      }

      -- Simulate a response without cachedContentTokenCount field
      local line = 'data: {"candidates":[{"content":{"parts":[{"text":"Hi"}],"role":"model"}}],'
        .. '"usageMetadata":{"promptTokenCount":500,"candidatesTokenCount":10}}'
      provider:process_response_line(line, callbacks)

      -- Should have input and output but no cache_read
      local found_cache_read = false
      for _, event in ipairs(usage_events) do
        if event.type == "cache_read" then
          found_cache_read = true
        end
      end
      assert.is_false(found_cache_read, "Should not emit cache_read when cachedContentTokenCount is missing")
    end)

    it("should parse thoughts tokens alongside cached tokens", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
        max_tokens = 4000,
      })

      local usage_events = {}
      local callbacks = {
        on_content = function() end,
        on_usage = function(data)
          table.insert(usage_events, data)
        end,
        on_response_complete = function() end,
        on_error = function() end,
      }

      -- Simulate a response with thoughts and cached tokens
      local line = 'data: {"candidates":[{"content":{"parts":[{"text":"result"}],"role":"model"}}],'
        .. '"usageMetadata":{"promptTokenCount":5000,"candidatesTokenCount":200,'
        .. '"thoughtsTokenCount":1500,"cachedContentTokenCount":3000}}'
      provider:process_response_line(line, callbacks)

      local found_input = false
      local found_output = false
      local found_thoughts = false
      local found_cache_read = false
      for _, event in ipairs(usage_events) do
        if event.type == "input" then
          -- input_tokens = promptTokenCount - cachedContentTokenCount (5000 - 3000 = 2000)
          assert.equals(2000, event.tokens)
          found_input = true
        elseif event.type == "output" then
          assert.equals(200, event.tokens)
          found_output = true
        elseif event.type == "thoughts" then
          assert.equals(1500, event.tokens)
          found_thoughts = true
        elseif event.type == "cache_read" then
          assert.equals(3000, event.tokens)
          found_cache_read = true
        end
      end

      assert.is_true(found_input, "Expected input usage event")
      assert.is_true(found_output, "Expected output usage event")
      assert.is_true(found_thoughts, "Expected thoughts usage event")
      assert.is_true(found_cache_read, "Expected cache_read usage event")
    end)
  end)
end)
