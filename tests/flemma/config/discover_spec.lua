local symbols = require("flemma.symbols")

describe("flemma.config DISCOVER resolution", function()
  ---@type flemma.config.proxy
  local proxy
  ---@type flemma.config.store
  local store
  ---@type flemma.config.schema
  local s
  ---@type { DEFAULTS: integer, SETUP: integer, RUNTIME: integer, FRONTMATTER: integer }
  local L

  before_each(function()
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.config.schema.types"] = nil
    package.loaded["flemma.config.schema.navigation"] = nil
    package.loaded["flemma.loader"] = nil
    proxy = require("flemma.config.proxy")
    store = require("flemma.config.store")
    s = require("flemma.config.schema")
    L = store.LAYERS
  end)

  -- ---------------------------------------------------------------------------
  -- DISCOVER callback invocation
  -- ---------------------------------------------------------------------------

  describe("callback invocation", function()
    it("invokes DISCOVER for unknown keys on an object", function()
      local called_with = nil
      local schema = s.object({
        parameters = s.object({
          [symbols.DISCOVER] = function(key)
            called_with = key
            return s.optional(s.string())
          end,
        }),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.parameters.custom_provider = "value"
      assert.equals("custom_provider", called_with)
    end)

    it("DISCOVER is NOT invoked for known (real) fields", function()
      local called = false
      local schema = s.object({
        parameters = s.object({
          timeout = s.optional(s.integer()),
          [symbols.DISCOVER] = function(_key)
            called = true
            return s.optional(s.string())
          end,
        }),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.parameters.timeout = 600
      assert.is_false(called)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Schema caching
  -- ---------------------------------------------------------------------------

  describe("schema caching", function()
    it("caches the resolved schema after first access", function()
      local count = 0
      local schema = s.object({
        parameters = s.object({
          [symbols.DISCOVER] = function(key)
            count = count + 1
            if key == "dynamic" then
              return s.optional(s.string())
            end
            return nil
          end,
        }),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.parameters.dynamic = "first"
      w.parameters.dynamic = "second"
      -- Read also uses cached schema
      local cfg = proxy.read_proxy(schema, nil)
      local _ = cfg.parameters.dynamic
      assert.equals(1, count)
    end)

    it("does NOT cache misses — callback fires again on each nil lookup", function()
      local count = 0
      local schema = s.object({
        parameters = s.object({
          [symbols.DISCOVER] = function(_key)
            count = count + 1
            return nil
          end,
        }),
      })
      store.init(schema)
      -- Each failed lookup re-invokes the callback
      local cfg = proxy.read_proxy(schema, nil)
      pcall(function()
        local _ = cfg.parameters.unknown_a
      end)
      pcall(function()
        local _ = cfg.parameters.unknown_a
      end)
      assert.equals(2, count)
    end)

    it("caches different keys independently", function()
      local count = 0
      local schema = s.object({
        tools = s.object({
          [symbols.DISCOVER] = function(key)
            count = count + 1
            if key == "bash" or key == "grep" then
              return s.object({
                cwd = s.optional(s.string()),
              })
            end
            return nil
          end,
        }),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.bash.cwd = "/tmp"
      w.tools.grep.cwd = "/home"
      -- Each key discovered once
      assert.equals(2, count)
      -- Subsequent accesses use cache
      w.tools.bash.cwd = "/var"
      assert.equals(2, count)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Callback returning nil triggers validation error
  -- ---------------------------------------------------------------------------

  describe("nil return triggers error", function()
    it("read proxy errors on unknown key when DISCOVER returns nil", function()
      local schema = s.object({
        parameters = s.object({
          [symbols.DISCOVER] = function(_key)
            return nil
          end,
        }),
      })
      store.init(schema)
      local cfg = proxy.read_proxy(schema, nil)
      assert.has_error(function()
        local _ = cfg.parameters.totally_unknown
      end)
    end)

    it("write proxy errors on unknown key when DISCOVER returns nil", function()
      local schema = s.object({
        parameters = s.object({
          [symbols.DISCOVER] = function(_key)
            return nil
          end,
        }),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_error(function()
        w.parameters.totally_unknown = "value"
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Discovered schema validates writes
  -- ---------------------------------------------------------------------------

  describe("discovered schema validates writes", function()
    it("accepts valid values for the discovered schema type", function()
      local schema = s.object({
        parameters = s.object({
          [symbols.DISCOVER] = function(key)
            if key == "anthropic" then
              return s.object({
                thinking_budget = s.optional(s.integer()),
              })
            end
            return nil
          end,
        }),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_no.error(function()
        w.parameters.anthropic.thinking_budget = 4096
      end)
      assert.equals(4096, store.resolve("parameters.anthropic.thinking_budget", nil))
    end)

    it("rejects invalid values for the discovered schema type", function()
      local schema = s.object({
        parameters = s.object({
          [symbols.DISCOVER] = function(key)
            if key == "anthropic" then
              return s.object({
                thinking_budget = s.optional(s.integer()),
              })
            end
            return nil
          end,
        }),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_error(function()
        w.parameters.anthropic.thinking_budget = "not-an-integer"
      end)
    end)

    it("discovered optional schema accepts nil", function()
      local schema = s.object({
        parameters = s.object({
          [symbols.DISCOVER] = function(key)
            if key == "custom" then
              return s.optional(s.string())
            end
            return nil
          end,
        }),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_no.error(function()
        w.parameters.custom = nil
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Provider and tool config schema patterns
  -- ---------------------------------------------------------------------------

  describe("provider config schema pattern", function()
    it("simulates provider-specific parameter resolution via DISCOVER", function()
      local anthropic_schema = s.object({
        thinking_budget = s.optional(s.integer()),
      })
      local openai_schema = s.object({
        reasoning_summary = s.optional(s.string("auto")),
      })
      local schema = s.object({
        parameters = s.object({
          timeout = s.optional(s.integer()),
          thinking = s.optional(s.string()),
          [symbols.DISCOVER] = function(key)
            if key == "anthropic" then
              return anthropic_schema
            end
            if key == "openai" then
              return openai_schema
            end
            return nil
          end,
        }),
      })
      store.init(schema)

      -- Write provider-specific params
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.parameters.anthropic.thinking_budget = 8192
      w.parameters.openai.reasoning_summary = "detailed"

      -- Read back
      local cfg = proxy.read_proxy(schema, nil)
      assert.equals(8192, cfg.parameters.anthropic.thinking_budget)
      assert.equals("detailed", cfg.parameters.openai.reasoning_summary)
    end)

    it("unknown provider triggers error", function()
      local schema = s.object({
        parameters = s.object({
          [symbols.DISCOVER] = function(_key)
            return nil
          end,
        }),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_error(function()
        w.parameters.nonexistent_provider = "value"
      end)
    end)
  end)

  describe("tool config schema pattern", function()
    it("simulates tool-specific config resolution via DISCOVER", function()
      local bash_schema = s.object({
        shell = s.optional(s.string()),
        cwd = s.optional(s.string()),
      })
      local schema = s.object({
        tools = s.object({
          modules = s.list(s.string(), {}),
          timeout = s.integer(120000),
          [symbols.DISCOVER] = function(key)
            if key == "bash" then
              return bash_schema
            end
            return nil
          end,
        }),
      })
      store.init(schema)

      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.bash.shell = "/bin/zsh"
      w.tools.bash.cwd = "/tmp"

      local cfg = proxy.read_proxy(schema, nil)
      assert.equals("/bin/zsh", cfg.tools.bash.shell)
      assert.equals("/tmp", cfg.tools.bash.cwd)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Schema defaults from discovered schemas
  -- ---------------------------------------------------------------------------

  describe("defaults from discovered schemas", function()
    it("discovered schemas with defaults materialize when the schema is accessed", function()
      -- DISCOVER-resolved schemas can have defaults. These defaults don't
      -- participate in layer 10 materialization (since DISCOVER is lazy), but
      -- the schema's default value is used when the schema node is queried
      -- and no ops exist at that path.
      local schema = s.object({
        tools = s.object({
          [symbols.DISCOVER] = function(key)
            if key == "bash" then
              return s.object({
                shell = s.optional(s.string("/bin/bash")),
              })
            end
            return nil
          end,
        }),
      })
      store.init(schema)

      -- No ops recorded for tools.bash.shell — the schema has a default
      -- but it won't appear via store.resolve since no op was recorded.
      -- DISCOVER defaults are baked into the schema for validation, not
      -- automatically materialized into the store.
      assert.is_nil(store.resolve("tools.bash.shell", nil))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Resolution priority: real field > alias > DISCOVER
  -- ---------------------------------------------------------------------------

  describe("resolution priority", function()
    it("real field takes priority over DISCOVER for the same key", function()
      local discover_called = false
      local schema = s.object({
        parameters = s.object({
          timeout = s.optional(s.integer()),
          [symbols.DISCOVER] = function(_key)
            discover_called = true
            return s.optional(s.string())
          end,
        }),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.parameters.timeout = 600
      -- DISCOVER should NOT have been called — timeout is a real field
      assert.is_false(discover_called)
    end)

    it("alias takes priority over DISCOVER for the same key", function()
      local discover_called = false
      local schema = s.object({
        parameters = s.object({
          timeout = s.optional(s.integer()),
        }),
        [symbols.ALIASES] = {
          timeout = "parameters.timeout",
        },
        [symbols.DISCOVER] = function(_key)
          discover_called = true
          return s.optional(s.string())
        end,
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.timeout = 600
      -- Alias resolved to parameters.timeout; DISCOVER not needed at root
      assert.is_false(discover_called)
      assert.equals(600, store.resolve("parameters.timeout", nil))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Cross-layer DISCOVER resolution
  -- ---------------------------------------------------------------------------

  describe("cross-layer resolution", function()
    it("discovered fields resolve across layers like static fields", function()
      local schema = s.object({
        parameters = s.object({
          [symbols.DISCOVER] = function(key)
            if key == "anthropic" then
              return s.object({
                thinking_budget = s.optional(s.integer()),
              })
            end
            return nil
          end,
        }),
      })
      store.init(schema)
      store.record(L.SETUP, nil, "set", "parameters.anthropic.thinking_budget", 4096)
      store.record(L.FRONTMATTER, 1, "set", "parameters.anthropic.thinking_budget", 8192)

      local cfg_global = proxy.read_proxy(schema, nil)
      assert.equals(4096, cfg_global.parameters.anthropic.thinking_budget)

      local cfg_buf = proxy.read_proxy(schema, 1)
      assert.equals(8192, cfg_buf.parameters.anthropic.thinking_budget)
    end)
  end)
end)
