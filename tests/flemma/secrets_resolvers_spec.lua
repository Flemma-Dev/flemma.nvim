--- Tests for builtin secrets resolvers

local environment

describe("flemma.secrets.resolvers.environment", function()
  before_each(function()
    package.loaded["flemma.secrets.resolvers.environment"] = nil
    environment = require("flemma.secrets.resolvers.environment")
  end)

  local function make_env_ctx()
    return {
      get_config = function(_self)
        return nil
      end,
      diagnostic = function(_self, _msg) end,
      get_diagnostics = function(_self)
        return {}
      end,
    }
  end

  describe("supports", function()
    it("supports any credential kind", function()
      assert.is_true(environment:supports({ kind = "api_key", service = "test" }))
      assert.is_true(environment:supports({ kind = "access_token", service = "test" }))
      assert.is_true(environment:supports({ kind = "service_account", service = "test" }))
    end)
  end)

  describe("resolve_async", function()
    it("resolves using SERVICE_KIND convention", function()
      vim.env.ANTHROPIC_API_KEY = "sk-test-123"

      local got
      environment:resolve_async({ kind = "api_key", service = "anthropic" }, make_env_ctx(), function(result)
        got = result
      end)

      assert.is_not_nil(got)
      assert.equals("sk-test-123", got.value)

      vim.env.ANTHROPIC_API_KEY = nil
    end)

    it("returns nil when env var is not set", function()
      vim.env.NONEXISTENT_API_KEY = nil

      local got
      environment:resolve_async({ kind = "api_key", service = "nonexistent" }, make_env_ctx(), function(result)
        got = result
      end)

      assert.is_nil(got)
    end)

    it("returns nil for empty env var", function()
      vim.env.EMPTY_API_KEY = ""

      local got
      environment:resolve_async({ kind = "api_key", service = "empty" }, make_env_ctx(), function(result)
        got = result
      end)

      assert.is_nil(got)

      vim.env.EMPTY_API_KEY = nil
    end)

    it("checks aliases after convention", function()
      vim.env.VERTEX_ACCESS_TOKEN = nil
      vim.env.VERTEX_AI_ACCESS_TOKEN = "ya29.from-alias"

      local got
      environment:resolve_async(
        {
          kind = "access_token",
          service = "vertex",
          aliases = { "VERTEX_AI_ACCESS_TOKEN" },
        },
        make_env_ctx(),
        function(result)
          got = result
        end
      )

      assert.is_not_nil(got)
      assert.equals("ya29.from-alias", got.value)

      vim.env.VERTEX_AI_ACCESS_TOKEN = nil
    end)

    it("prefers convention over aliases", function()
      vim.env.VERTEX_ACCESS_TOKEN = "ya29.from-convention"
      vim.env.VERTEX_AI_ACCESS_TOKEN = "ya29.from-alias"

      local got
      environment:resolve_async(
        {
          kind = "access_token",
          service = "vertex",
          aliases = { "VERTEX_AI_ACCESS_TOKEN" },
        },
        make_env_ctx(),
        function(result)
          got = result
        end
      )

      assert.is_not_nil(got)
      assert.equals("ya29.from-convention", got.value)

      vim.env.VERTEX_ACCESS_TOKEN = nil
      vim.env.VERTEX_AI_ACCESS_TOKEN = nil
    end)

    it("tries aliases in order", function()
      vim.env.FIRST_ALIAS = nil
      vim.env.SECOND_ALIAS = "from-second"

      local got
      environment:resolve_async(
        {
          kind = "api_key",
          service = "test",
          aliases = { "FIRST_ALIAS", "SECOND_ALIAS" },
        },
        make_env_ctx(),
        function(result)
          got = result
        end
      )

      assert.is_not_nil(got)
      assert.equals("from-second", got.value)

      vim.env.SECOND_ALIAS = nil
    end)

    it("emits diagnostic when env var is not set", function()
      vim.env.NONEXISTENT_API_KEY = nil

      local diags = {}
      local ctx = {
        get_config = function(_self)
          return nil
        end,
        diagnostic = function(_self, msg)
          table.insert(diags, msg)
        end,
        get_diagnostics = function(_self)
          return diags
        end,
      }

      environment:resolve_async({ kind = "api_key", service = "nonexistent" }, ctx, function() end)

      assert.equals(1, #diags)
      assert.truthy(diags[1]:match("NONEXISTENT_API_KEY"))
      assert.truthy(diags[1]:match("not set"))
    end)

    it("includes aliases in diagnostic when tried", function()
      vim.env.VERTEX_ACCESS_TOKEN = nil
      vim.env.VERTEX_AI_ACCESS_TOKEN = nil

      local diags = {}
      local ctx = {
        get_config = function(_self)
          return nil
        end,
        diagnostic = function(_self, msg)
          table.insert(diags, msg)
        end,
        get_diagnostics = function(_self)
          return diags
        end,
      }

      environment:resolve_async({
        kind = "access_token",
        service = "vertex",
        aliases = { "VERTEX_AI_ACCESS_TOKEN" },
      }, ctx, function() end)

      assert.equals(1, #diags)
      assert.truthy(diags[1]:match("VERTEX_ACCESS_TOKEN"))
      assert.truthy(diags[1]:match("VERTEX_AI_ACCESS_TOKEN"))
    end)
  end)
end)

local secret_tool

describe("flemma.secrets.resolvers.secret_tool", function()
  before_each(function()
    package.loaded["flemma.secrets.resolvers.secret_tool"] = nil
    secret_tool = require("flemma.secrets.resolvers.secret_tool")
  end)

  local function make_st_ctx()
    return {
      get_config = function(_self)
        return nil
      end,
      diagnostic = function(_self, _msg) end,
      get_diagnostics = function(_self)
        return {}
      end,
    }
  end

  describe("supports", function()
    it("returns based on platform availability", function()
      local expected = vim.fn.has("linux") == 1 and vim.fn.executable("secret-tool") == 1
      assert.equals(expected, secret_tool:supports({ kind = "api_key", service = "test" }, make_st_ctx()))
    end)

    it("emits diagnostic when not on Linux", function()
      local diags = {}
      local ctx = {
        get_config = function(_self)
          return nil
        end,
        diagnostic = function(_self, msg)
          table.insert(diags, msg)
        end,
        get_diagnostics = function(_self)
          return diags
        end,
      }

      if vim.fn.has("linux") ~= 1 then
        secret_tool:supports({ kind = "api_key", service = "test" }, ctx)
        assert.equals(1, #diags)
        assert.truthy(diags[1]:match("requires Linux"))
      end
    end)
  end)

  describe("resolve_async", function()
    local original_system

    before_each(function()
      original_system = vim.system
    end)

    after_each(function()
      vim.system = original_system
    end)

    it("calls secret-tool with service and kind", function()
      local captured_cmd
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, on_exit)
        captured_cmd = cmd
        vim.schedule(function()
          on_exit({ code = 0, stdout = "sk-from-keyring\n", stderr = "" })
        end)
      end

      local got
      secret_tool:resolve_async({ kind = "api_key", service = "anthropic" }, make_st_ctx(), function(result)
        got = result
      end)

      vim.wait(100, function()
        return got ~= nil
      end)
      assert.is_not_nil(got)
      assert.equals("sk-from-keyring", got.value)
      assert.is_not_nil(captured_cmd)
      assert.equals("secret-tool", captured_cmd[1])
      assert.equals("lookup", captured_cmd[2])
      local cmd_str = table.concat(captured_cmd, " ")
      assert.truthy(cmd_str:match("service"))
      assert.truthy(cmd_str:match("anthropic"))
      assert.truthy(cmd_str:match("api_key"))
    end)

    it("falls back to legacy key=api when convention fails", function()
      local calls = {}
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, on_exit)
        table.insert(calls, vim.deepcopy(cmd))
        local key_value = cmd[6]
        vim.schedule(function()
          if key_value == "api" then
            on_exit({ code = 0, stdout = "sk-legacy\n", stderr = "" })
          else
            on_exit({ code = 1, stdout = "", stderr = "" })
          end
        end)
      end

      local got
      secret_tool:resolve_async({ kind = "api_key", service = "anthropic" }, make_st_ctx(), function(result)
        got = result
      end)

      vim.wait(200, function()
        return got ~= nil
      end)
      assert.is_not_nil(got)
      assert.equals("sk-legacy", got.value)
      assert.equals(2, #calls)
    end)

    it("skips legacy fallback for access_token kind", function()
      local calls = {}
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, on_exit)
        table.insert(calls, vim.deepcopy(cmd))
        vim.schedule(function()
          on_exit({ code = 1, stdout = "", stderr = "" })
        end)
      end

      local done = false
      secret_tool:resolve_async({ kind = "access_token", service = "vertex" }, make_st_ctx(), function(_result)
        done = true
      end)

      vim.wait(100, function()
        return done
      end)
      assert.equals(1, #calls)
    end)

    it("prefers convention over legacy", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 0, stdout = "sk-from-convention\n", stderr = "" })
        end)
      end

      local got
      secret_tool:resolve_async({ kind = "api_key", service = "anthropic" }, make_st_ctx(), function(result)
        got = result
      end)

      vim.wait(100, function()
        return got ~= nil
      end)
      assert.is_not_nil(got)
      assert.equals("sk-from-convention", got.value)
    end)

    it("trims trailing whitespace from result", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 0, stdout = "sk-test-key  \n\n", stderr = "" })
        end)
      end

      local got
      secret_tool:resolve_async({ kind = "api_key", service = "test" }, make_st_ctx(), function(result)
        got = result
      end)

      vim.wait(100, function()
        return got ~= nil
      end)
      assert.is_not_nil(got)
      assert.equals("sk-test-key", got.value)
    end)

    it("returns nil when both convention and legacy fail", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 1, stdout = "", stderr = "" })
        end)
      end

      local done = false
      local got = "untouched"
      secret_tool:resolve_async({ kind = "api_key", service = "test" }, make_st_ctx(), function(result)
        got = result
        done = true
      end)

      vim.wait(200, function()
        return done
      end)
      assert.is_nil(got)
    end)

    it("emits diagnostic when lookup fails", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 1, stdout = "", stderr = "" })
        end)
      end

      local diags = {}
      local ctx = {
        get_config = function(_self)
          return nil
        end,
        diagnostic = function(_self, msg)
          table.insert(diags, msg)
        end,
        get_diagnostics = function(_self)
          return diags
        end,
      }

      local done = false
      secret_tool:resolve_async({ kind = "api_key", service = "anthropic" }, ctx, function()
        done = true
      end)

      vim.wait(200, function()
        return done
      end)
      assert.is_true(#diags > 0)
      assert.truthy(diags[1]:match("no entry found"))
    end)
  end)
end)

local gcloud

describe("flemma.secrets.resolvers.gcloud", function()
  before_each(function()
    package.loaded["flemma.secrets.resolvers.gcloud"] = nil
    package.loaded["flemma.secrets"] = nil
    package.loaded["flemma.secrets.cache"] = nil
    package.loaded["flemma.secrets.registry"] = nil
    gcloud = require("flemma.secrets.resolvers.gcloud")
  end)

  --- Build a minimal mock context with an optional config subtable.
  ---@param cfg? table
  ---@return table
  local function make_ctx(cfg)
    local diags = {}
    return {
      get_config = function(_self)
        return cfg
      end,
      diagnostic = function(_self, msg)
        table.insert(diags, msg)
      end,
      get_diagnostics = function(_self)
        return diags
      end,
    }
  end

  describe("supports", function()
    it("only supports access_token kind", function()
      local has_gcloud = vim.fn.executable("gcloud") == 1
      assert.equals(has_gcloud, gcloud:supports({ kind = "access_token", service = "vertex" }, make_ctx(nil)))
      assert.is_false(gcloud:supports({ kind = "api_key", service = "vertex" }, make_ctx(nil)))
      assert.is_false(gcloud:supports({ kind = "service_account", service = "vertex" }, make_ctx(nil)))
    end)

    it("uses configured path for executable check", function()
      local ctx = make_ctx({ path = "/nonexistent/gcloud-binary" })
      assert.is_false(gcloud:supports({ kind = "access_token", service = "vertex" }, ctx))
    end)

    it("falls back to 'gcloud' when ctx returns nil config", function()
      local ctx = make_ctx(nil)
      local expected = vim.fn.executable("gcloud") == 1
      assert.equals(expected, gcloud:supports({ kind = "access_token", service = "vertex" }, ctx))
    end)

    it("emits diagnostic when executable not found", function()
      local diags = {}
      local ctx = {
        get_config = function(_self)
          return { path = "/nonexistent/gcloud" }
        end,
        diagnostic = function(_self, msg)
          table.insert(diags, msg)
        end,
        get_diagnostics = function(_self)
          return diags
        end,
      }

      gcloud:supports({ kind = "access_token", service = "vertex" }, ctx)

      assert.equals(1, #diags)
      assert.truthy(diags[1]:match("executable not found"))
      assert.truthy(diags[1]:match("/nonexistent/gcloud"))
    end)

    it("emits diagnostic for non-access_token kind", function()
      local diags = {}
      local ctx = {
        get_config = function(_self)
          return nil
        end,
        diagnostic = function(_self, msg)
          table.insert(diags, msg)
        end,
        get_diagnostics = function(_self)
          return diags
        end,
      }

      gcloud:supports({ kind = "api_key", service = "vertex" }, ctx)

      assert.equals(1, #diags)
      assert.truthy(diags[1]:match("only resolves access_token"))
    end)
  end)

  describe("resolve_async", function()
    local original_system

    before_each(function()
      original_system = vim.system
      local secrets_mod = require("flemma.secrets")
      secrets_mod.setup()
    end)

    after_each(function()
      vim.system = original_system
    end)

    it("derives access token from service account via gcloud", function()
      vim.env.VERTEX_SERVICE_ACCOUNT = '{"type":"service_account","project_id":"test"}'

      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 0, stdout = "ya29.generated-token\n", stderr = "" })
        end)
      end

      local got
      gcloud:resolve_async({ kind = "access_token", service = "vertex" }, make_ctx(nil), function(result)
        got = result
      end)

      vim.wait(200, function()
        return got ~= nil
      end)
      assert.is_not_nil(got)
      assert.equals("ya29.generated-token", got.value)
      assert.equals(3600, got.ttl)

      vim.env.VERTEX_SERVICE_ACCOUNT = nil
    end)

    it("falls back to default credentials when no service account", function()
      local captured_cmd
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, on_exit)
        captured_cmd = cmd
        vim.schedule(function()
          on_exit({ code = 0, stdout = "ya29.default-token\n", stderr = "" })
        end)
      end

      local got
      gcloud:resolve_async({ kind = "access_token", service = "vertex" }, make_ctx(nil), function(result)
        got = result
      end)

      vim.wait(200, function()
        return got ~= nil
      end)
      assert.is_not_nil(got)
      assert.equals("ya29.default-token", got.value)
      assert.is_not_nil(captured_cmd)
    end)

    it("returns nil when gcloud fails", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 1, stdout = "", stderr = "ERROR: not authenticated" })
        end)
      end

      local done = false
      local got = "untouched"
      gcloud:resolve_async({ kind = "access_token", service = "vertex" }, make_ctx(nil), function(result)
        got = result
        done = true
      end)

      vim.wait(200, function()
        return done
      end)
      assert.is_nil(got)
    end)

    it("validates token is non-empty", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 0, stdout = "\n", stderr = "" })
        end)
      end

      local done = false
      local got = "untouched"
      gcloud:resolve_async({ kind = "access_token", service = "vertex" }, make_ctx(nil), function(result)
        got = result
        done = true
      end)

      vim.wait(200, function()
        return done
      end)
      assert.is_nil(got)
    end)

    it("uses configured gcloud path in command", function()
      local captured_cmd
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, on_exit)
        captured_cmd = cmd
        vim.schedule(function()
          on_exit({ code = 0, stdout = "ya29.token\n", stderr = "" })
        end)
      end

      local ctx = make_ctx({ path = "/nix/store/abc123/bin/gcloud" })
      local got
      gcloud:resolve_async({ kind = "access_token", service = "vertex" }, ctx, function(result)
        got = result
      end)

      vim.wait(200, function()
        return got ~= nil
      end)
      assert.is_not_nil(got)
      assert.equals("/nix/store/abc123/bin/gcloud", captured_cmd[1])
    end)

    it("emits diagnostic when gcloud command fails", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 2, stdout = "", stderr = "ERROR" })
        end)
      end

      local diags = {}
      local ctx = {
        get_config = function(_self)
          return nil
        end,
        diagnostic = function(_self, msg)
          table.insert(diags, msg)
        end,
        get_diagnostics = function(_self)
          return diags
        end,
      }

      local done = false
      gcloud:resolve_async({ kind = "access_token", service = "vertex" }, ctx, function()
        done = true
      end)

      vim.wait(200, function()
        return done
      end)
      assert.is_true(#diags > 0)
      assert.truthy(diags[1]:match("auth failed"))
      assert.truthy(diags[1]:match("exit code 2"))
    end)

    it("emits diagnostic when token is empty", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 0, stdout = "\n", stderr = "" })
        end)
      end

      local diags = {}
      local ctx = {
        get_config = function(_self)
          return nil
        end,
        diagnostic = function(_self, msg)
          table.insert(diags, msg)
        end,
        get_diagnostics = function(_self)
          return diags
        end,
      }

      local done = false
      gcloud:resolve_async({ kind = "access_token", service = "vertex" }, ctx, function()
        done = true
      end)

      vim.wait(200, function()
        return done
      end)
      assert.is_true(#diags > 0)
      assert.truthy(diags[1]:match("returned empty token"))
    end)
  end)
end)

local keychain

describe("flemma.secrets.resolvers.keychain", function()
  before_each(function()
    package.loaded["flemma.secrets.resolvers.keychain"] = nil
    keychain = require("flemma.secrets.resolvers.keychain")
  end)

  local function make_kc_ctx()
    return {
      get_config = function(_self)
        return nil
      end,
      diagnostic = function(_self, _msg) end,
      get_diagnostics = function(_self)
        return {}
      end,
    }
  end

  describe("supports", function()
    it("returns true only on macOS", function()
      local expected = vim.fn.has("mac") == 1
      assert.equals(expected, keychain:supports({ kind = "api_key", service = "test" }, make_kc_ctx()))
    end)

    it("emits diagnostic when not on macOS", function()
      local diags = {}
      local ctx = {
        get_config = function(_self)
          return nil
        end,
        diagnostic = function(_self, msg)
          table.insert(diags, msg)
        end,
        get_diagnostics = function(_self)
          return diags
        end,
      }

      if vim.fn.has("mac") ~= 1 then
        keychain:supports({ kind = "api_key", service = "test" }, ctx)
        assert.equals(1, #diags)
        assert.truthy(diags[1]:match("requires macOS"))
      end
    end)
  end)

  describe("resolve_async", function()
    local original_system

    before_each(function()
      original_system = vim.system
    end)

    after_each(function()
      vim.system = original_system
    end)

    it("calls security find-generic-password with service and kind", function()
      local captured_cmd
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, on_exit)
        captured_cmd = cmd
        vim.schedule(function()
          on_exit({ code = 0, stdout = "sk-from-keychain\n", stderr = "" })
        end)
      end

      local got
      keychain:resolve_async({ kind = "api_key", service = "anthropic" }, make_kc_ctx(), function(result)
        got = result
      end)

      vim.wait(100, function()
        return got ~= nil
      end)
      assert.is_not_nil(got)
      assert.equals("sk-from-keychain", got.value)
      assert.equals("security", captured_cmd[1])
      assert.equals("find-generic-password", captured_cmd[2])
    end)

    it("falls back to legacy account=api when convention fails", function()
      local calls = {}
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, on_exit)
        table.insert(calls, vim.deepcopy(cmd))
        local account = cmd[6]
        vim.schedule(function()
          if account == "api" then
            on_exit({ code = 0, stdout = "sk-legacy\n", stderr = "" })
          else
            on_exit({ code = 44, stdout = "", stderr = "" })
          end
        end)
      end

      local got
      keychain:resolve_async({ kind = "api_key", service = "anthropic" }, make_kc_ctx(), function(result)
        got = result
      end)

      vim.wait(200, function()
        return got ~= nil
      end)
      assert.is_not_nil(got)
      assert.equals("sk-legacy", got.value)
      assert.equals(2, #calls)
    end)

    it("skips legacy fallback for access_token kind", function()
      local calls = {}
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _, on_exit)
        table.insert(calls, vim.deepcopy(cmd))
        vim.schedule(function()
          on_exit({ code = 44, stdout = "", stderr = "" })
        end)
      end

      local done = false
      keychain:resolve_async({ kind = "access_token", service = "vertex" }, make_kc_ctx(), function(_result)
        done = true
      end)

      vim.wait(100, function()
        return done
      end)
      assert.equals(1, #calls)
    end)

    it("trims trailing whitespace", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 0, stdout = "sk-key  \n", stderr = "" })
        end)
      end

      local got
      keychain:resolve_async({ kind = "api_key", service = "test" }, make_kc_ctx(), function(result)
        got = result
      end)

      vim.wait(100, function()
        return got ~= nil
      end)
      assert.is_not_nil(got)
      assert.equals("sk-key", got.value)
    end)

    it("returns nil when both convention and legacy fail", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 44, stdout = "", stderr = "" })
        end)
      end

      local done = false
      local got = "untouched"
      keychain:resolve_async({ kind = "api_key", service = "test" }, make_kc_ctx(), function(result)
        got = result
        done = true
      end)

      vim.wait(200, function()
        return done
      end)
      assert.is_nil(got)
    end)

    it("emits diagnostic when lookup fails", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_, _, on_exit)
        vim.schedule(function()
          on_exit({ code = 44, stdout = "", stderr = "" })
        end)
      end

      local diags = {}
      local ctx = {
        get_config = function(_self)
          return nil
        end,
        diagnostic = function(_self, msg)
          table.insert(diags, msg)
        end,
        get_diagnostics = function(_self)
          return diags
        end,
      }

      local done = false
      keychain:resolve_async({ kind = "api_key", service = "anthropic" }, ctx, function()
        done = true
      end)

      vim.wait(200, function()
        return done
      end)
      assert.is_true(#diags > 0)
      assert.truthy(diags[1]:match("no entry found"))
    end)
  end)
end)
