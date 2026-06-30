local json = require("flemma.utilities.json")

describe("flemma.secrets.resolvers.chatgpt", function()
  local chatgpt

  before_each(function()
    package.loaded["flemma.secrets.resolvers.chatgpt"] = nil
    chatgpt = require("flemma.secrets.resolvers.chatgpt")
  end)

  describe("supports()", function()
    it("returns true for chatgpt_subscription kind", function()
      local ctx = {
        diagnostic = function() end,
        get_config = function()
          return nil
        end,
      }
      assert.is_true(chatgpt:supports({ kind = "chatgpt_subscription", service = "codex" }, ctx))
    end)

    it("returns false for other credential kinds", function()
      local ctx = {
        diagnostic = function() end,
        get_config = function()
          return nil
        end,
      }
      assert.is_false(chatgpt:supports({ kind = "api_key", service = "openai" }, ctx))
    end)
  end)

  describe("resolve_async()", function()
    it("reads auth file and returns token with metadata", function()
      local tmp = vim.fn.tempname() .. ".json"
      local auth_data = {
        auth_mode = "chatgpt",
        tokens = {
          access_token = "test-access-token",
          refresh_token = "test-refresh-token",
          account_id = "acct_12345",
          expires_at = os.time() + 3600,
        },
      }
      local f = io.open(tmp, "w")
      f:write(json.encode(auth_data))
      f:close()

      local result_captured
      local ctx = {
        diagnostic = function() end,
        get_config = function()
          return { auth_file = tmp }
        end,
      }
      chatgpt:resolve_async({ kind = "chatgpt_subscription", service = "codex" }, ctx, function(result)
        result_captured = result
      end)

      assert.is_not_nil(result_captured)
      assert.are.equal("test-access-token", result_captured.value)
      assert.are.equal("acct_12345", result_captured.metadata.account_id)
      assert.is_number(result_captured.ttl)

      os.remove(tmp)
    end)

    it("returns nil when auth file does not exist", function()
      local diagnostics = {}
      local ctx = {
        diagnostic = function(_, msg)
          table.insert(diagnostics, msg)
        end,
        get_config = function()
          return { auth_file = "/nonexistent/path/auth.json" }
        end,
      }

      local result_captured = "sentinel"
      chatgpt:resolve_async({ kind = "chatgpt_subscription", service = "codex" }, ctx, function(result)
        result_captured = result
      end)

      assert.is_nil(result_captured)
      assert.is_true(#diagnostics > 0)
    end)

    it("returns nil when auth_mode is not chatgpt", function()
      local tmp = vim.fn.tempname() .. ".json"
      local auth_data = {
        auth_mode = "api_key",
        tokens = { access_token = "test" },
      }
      local f = io.open(tmp, "w")
      f:write(json.encode(auth_data))
      f:close()

      local diagnostics = {}
      local ctx = {
        diagnostic = function(_, msg)
          table.insert(diagnostics, msg)
        end,
        get_config = function()
          return { auth_file = tmp }
        end,
      }

      local result_captured = "sentinel"
      chatgpt:resolve_async({ kind = "chatgpt_subscription", service = "codex" }, ctx, function(result)
        result_captured = result
      end)

      assert.is_nil(result_captured)
      assert.is_true(#diagnostics > 0)

      os.remove(tmp)
    end)
  end)
end)
