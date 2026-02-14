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

  describe("is_auth_error", function()
    it("should detect UNAUTHENTICATED status in error message", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })
      assert.is_true(provider:is_auth_error("Request had invalid authentication credentials (Status: UNAUTHENTICATED)"))
    end)

    it("should detect lowercase unauthenticated", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })
      assert.is_true(provider:is_auth_error("unauthenticated"))
    end)

    it("should detect invalid authentication credentials", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })
      assert.is_true(provider:is_auth_error("Invalid Authentication Credentials"))
    end)

    it("should return false for non-auth errors", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })
      assert.is_false(provider:is_auth_error("Rate limit exceeded"))
      assert.is_false(provider:is_auth_error("Model not found"))
      assert.is_false(provider:is_auth_error("Internal server error"))
    end)

    it("should handle nil and non-string input", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })
      assert.is_false(provider:is_auth_error(nil))
      assert.is_false(provider:is_auth_error(123 --[[@as any]]))
    end)
  end)

  describe("reset with opts", function()
    it("should clear api_key and token tracking when opts.auth is true", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })

      -- Simulate a cached gcloud token
      provider.state.api_key = "ya29.fake-token"
      provider._token_generated_at = os.time()
      provider._token_from = "gcloud"

      provider:reset({ auth = true })

      assert.is_nil(provider.state.api_key)
      assert.is_nil(provider._token_generated_at)
      assert.is_nil(provider._token_from)
    end)

    it("should NOT reset the response buffer when opts.auth is true", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })

      -- Record what the response buffer looks like after construction
      local original_buffer = provider._response_buffer
      assert.is_not_nil(original_buffer)

      -- Auth reset should preserve the response buffer
      provider:reset({ auth = true })
      assert.equals(original_buffer, provider._response_buffer)
    end)

    it("should perform full reset when no opts are passed", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })

      local original_buffer = provider._response_buffer

      -- Full reset creates a new response buffer
      provider:reset()
      assert.is_not.equals(original_buffer, provider._response_buffer)
      assert.equals("", provider._response_buffer.extra.accumulated_thoughts)
    end)
  end)

  describe("extract_json_response_error", function()
    it("should handle non-array object format with status", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })

      local data = {
        error = {
          code = 401,
          message = "Request had invalid authentication credentials.",
          status = "UNAUTHENTICATED",
        },
      }

      local msg = provider:extract_json_response_error(data)
      assert.is_not_nil(msg)
      assert.truthy(msg:match("Request had invalid authentication credentials"))
      assert.truthy(msg:match("UNAUTHENTICATED"))
    end)

    it("should handle non-array object format with details", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })

      local data = {
        error = {
          code = 400,
          message = "Invalid request",
          status = "INVALID_ARGUMENT",
          details = {
            {
              ["@type"] = "type.googleapis.com/google.rpc.BadRequest",
              fieldViolations = {
                { description = "Field X is required" },
              },
            },
          },
        },
      }

      local msg = provider:extract_json_response_error(data)
      assert.is_not_nil(msg)
      assert.truthy(msg:match("INVALID_ARGUMENT"))
      assert.truthy(msg:match("Field X is required"))
    end)

    it("should still handle array format", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })

      local data = {
        {
          error = {
            message = "Array error message",
            status = "PERMISSION_DENIED",
          },
        },
      }

      local msg = provider:extract_json_response_error(data)
      assert.is_not_nil(msg)
      assert.truthy(msg:match("Array error message"))
      assert.truthy(msg:match("PERMISSION_DENIED"))
    end)
  end)

  describe("proactive token refresh", function()
    it("should clear stale gcloud token when age exceeds threshold", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })

      -- Simulate a gcloud token generated 56 minutes ago (past the 55-min threshold)
      provider.state.api_key = "ya29.stale-token"
      provider._token_from = "gcloud"
      provider._token_generated_at = os.time() - (56 * 60)

      -- Set VERTEX_AI_ACCESS_TOKEN to catch the call after cache is cleared
      -- (otherwise get_api_key would try gcloud/keyring which we can't mock easily)
      local original_env = os.getenv("VERTEX_AI_ACCESS_TOKEN")
      vim.env.VERTEX_AI_ACCESS_TOKEN = "ya29.fresh-env-token"

      local token = provider:get_api_key()

      -- Restore env
      if original_env then
        vim.env.VERTEX_AI_ACCESS_TOKEN = original_env
      else
        vim.env.VERTEX_AI_ACCESS_TOKEN = nil
      end

      -- Should have picked up the env token since the stale one was cleared
      assert.equals("ya29.fresh-env-token", token)
      assert.equals("env", provider._token_from)
    end)

    it("should keep valid gcloud token when age is within threshold", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })

      -- Simulate a gcloud token generated 30 minutes ago (within the 55-min threshold)
      provider.state.api_key = "ya29.valid-token"
      provider._token_from = "gcloud"
      provider._token_generated_at = os.time() - (30 * 60)

      -- Temporarily clear VERTEX_AI_ACCESS_TOKEN to avoid short-circuiting
      local original_env = os.getenv("VERTEX_AI_ACCESS_TOKEN")
      vim.env.VERTEX_AI_ACCESS_TOKEN = nil

      local token = provider:get_api_key()

      -- Restore env
      if original_env then
        vim.env.VERTEX_AI_ACCESS_TOKEN = original_env
      end

      -- Should still use the cached token
      assert.equals("ya29.valid-token", token)
      assert.equals("gcloud", provider._token_from)
    end)

    it("should not check staleness for env tokens", function()
      local provider = vertex.new({
        model = "gemini-2.5-pro",
        project_id = "test-project",
        location = "us-central1",
      })

      -- Simulate an env token that's old (but env tokens are always re-read)
      provider.state.api_key = "old-env-token"
      provider._token_from = "env"
      provider._token_generated_at = os.time() - (120 * 60) -- 2 hours old

      vim.env.VERTEX_AI_ACCESS_TOKEN = "ya29.current-env-token"

      local token = provider:get_api_key()

      -- Restore env
      vim.env.VERTEX_AI_ACCESS_TOKEN = nil

      -- Should pick up the current env token (re-read on every call)
      assert.equals("ya29.current-env-token", token)
      assert.equals("env", provider._token_from)
    end)
  end)
end)
