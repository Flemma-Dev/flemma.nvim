local symbols = require("flemma.symbols")

describe("flemma.config — deferred validation", function()
  ---@type flemma.config
  local config
  ---@type flemma.config.schema
  local s
  ---@type { DEFAULTS: integer, SETUP: integer, RUNTIME: integer, FRONTMATTER: integer }
  local L
  ---@type flemma.config.store
  local store

  before_each(function()
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.config.schema.types"] = nil
    package.loaded["flemma.config.schema.navigation"] = nil
    package.loaded["flemma.loader"] = nil
    config = require("flemma.config")
    s = require("flemma.config.schema")
    store = require("flemma.config.store")
    L = config.LAYERS
  end)

  -- ---------------------------------------------------------------------------
  -- Schema node :validate() API
  -- ---------------------------------------------------------------------------

  describe("schema node :validate()", function()
    it("stores the callback and returns self for chaining", function()
      local fn = function()
        return true
      end
      local node = s.string()
      local result = node:validate(fn)
      assert.equals(node, result)
    end)

    it("has_deferred_validator returns false when no validator set", function()
      local node = s.string()
      assert.is_false(node:has_deferred_validator())
    end)

    it("has_deferred_validator returns true after :validate()", function()
      local node = s.string():validate(function()
        return true
      end)
      assert.is_true(node:has_deferred_validator())
    end)

    it("get_deferred_validator returns the stored function", function()
      local fn = function()
        return true
      end
      local node = s.string():validate(fn)
      assert.equals(fn, node:get_deferred_validator())
    end)

    it("get_deferred_validator returns nil when no validator set", function()
      local node = s.string()
      assert.is_nil(node:get_deferred_validator())
    end)

    it("chains with coerce and other methods", function()
      local node = s.string()
        :validate(function()
          return true
        end)
        :coerce(function(v)
          return v
        end)
        :describe("test")
      assert.is_true(node:has_deferred_validator())
      assert.is_true(node:has_coerce())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- OptionalNode delegation
  -- ---------------------------------------------------------------------------

  describe("OptionalNode delegation", function()
    it("delegates has_deferred_validator to inner schema", function()
      local inner = s.string():validate(function()
        return true
      end)
      local node = s.optional(inner)
      assert.is_true(node:has_deferred_validator())
    end)

    it("delegates get_deferred_validator to inner schema", function()
      local fn = function()
        return true
      end
      local inner = s.string():validate(fn)
      local node = s.optional(inner)
      assert.equals(fn, node:get_deferred_validator())
    end)

    it("returns false when inner has no validator", function()
      local node = s.optional(s.string())
      assert.is_false(node:has_deferred_validator())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- finalize() returns validation_failures
  -- ---------------------------------------------------------------------------

  describe("finalize() returns validation_failures", function()
    it("returns failures when deferred validation fails", function()
      local schema = s.object({
        name = s.string("default"):validate(function(value)
          if value == "bad" then
            return false, "name is bad"
          end
          return true
        end),
      })
      config.init(schema)
      config.apply(L.SETUP, { name = "bad" })

      local _, validation_failures = config.finalize(L.SETUP, nil)

      assert.equals(1, #validation_failures)
      assert.equals("name", validation_failures[1].path)
      assert.equals("bad", validation_failures[1].value)
      assert.equals("name is bad", validation_failures[1].message)
    end)

    it("returns empty table when all values pass", function()
      local schema = s.object({
        name = s.string("default"):validate(function()
          return true
        end),
      })
      config.init(schema)
      config.apply(L.SETUP, { name = "good" })

      local _, validation_failures = config.finalize(L.SETUP, nil)

      assert.equals(0, #validation_failures)
    end)

    it("works when no deferred is provided", function()
      local schema = s.object({
        name = s.string("default"):validate(function()
          return false, "always fails"
        end),
      })
      config.init(schema)
      config.apply(L.SETUP, { name = "test" })

      -- Should not error
      local _, validation_failures = config.finalize(L.SETUP, nil)
      assert.equals(1, #validation_failures)
    end)

    it("collects multiple failures across fields", function()
      local schema = s.object({
        alpha = s.string("a"):validate(function(value)
          if value == "bad_a" then
            return false, "alpha is bad"
          end
          return true
        end),
        beta = s.string("b"):validate(function(value)
          if value == "bad_b" then
            return false, "beta is bad"
          end
          return true
        end),
      })
      config.init(schema)
      config.apply(L.SETUP, { alpha = "bad_a", beta = "bad_b" })

      local _, validation_failures = config.finalize(L.SETUP, nil)

      assert.equals(2, #validation_failures)
      local messages = {}
      for _, f in ipairs(validation_failures) do
        messages[f.path] = f.message
      end
      assert.equals("alpha is bad", messages.alpha)
      assert.equals("beta is bad", messages.beta)
    end)

    it("provides default message when validator returns nil message", function()
      local schema = s.object({
        name = s.string("default"):validate(function()
          return false
        end),
      })
      config.init(schema)
      config.apply(L.SETUP, { name = "test" })

      local _, validation_failures = config.finalize(L.SETUP, nil)

      assert.equals(1, #validation_failures)
      assert.matches("validation failed", validation_failures[1].message)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- List item validation via allow_list
  -- ---------------------------------------------------------------------------

  describe("list item validation", function()
    it("validates each item in an allow_list individually", function()
      local known = { alpha = true, beta = true, gamma = true }
      local schema = s.object({
        items = s.object({
          [symbols.DISCOVER] = function()
            return nil
          end,
        }):allow_list(s.string():validate(function(name)
          if not known[name] then
            return false, ("unknown item '%s'"):format(name)
          end
          return true
        end)),
      })
      config.init(schema)

      -- Record list ops directly to avoid DISCOVER issues with plain apply
      store.record(L.SETUP, nil, "append", "items", "alpha")
      store.record(L.SETUP, nil, "append", "items", "nope")
      store.record(L.SETUP, nil, "append", "items", "beta")

      local _, validation_failures = config.finalize(L.SETUP, nil)

      assert.equals(1, #validation_failures)
      assert.equals("items", validation_failures[1].path)
      assert.equals("nope", validation_failures[1].value)
      assert.matches("unknown item 'nope'", validation_failures[1].message)
    end)

    it("passes when all list items are valid", function()
      local known = { alpha = true, beta = true }
      local schema = s.object({
        items = s.object({
          [symbols.DISCOVER] = function()
            return nil
          end,
        }):allow_list(s.string():validate(function(name)
          if not known[name] then
            return false, ("unknown item '%s'"):format(name)
          end
          return true
        end)),
      })
      config.init(schema)
      store.record(L.SETUP, nil, "append", "items", "alpha")
      store.record(L.SETUP, nil, "append", "items", "beta")

      local _, validation_failures = config.finalize(L.SETUP, nil)

      assert.equals(0, #validation_failures)
    end)

    it("validates remove ops (catches typos in tool removal)", function()
      local known = { alpha = true, beta = true, gamma = true }
      local schema = s.object({
        items = s.object({
          [symbols.DISCOVER] = function()
            return nil
          end,
        }):allow_list(s.string():validate(function(name)
          if not known[name] then
            return false, ("unknown item '%s'"):format(name)
          end
          return true
        end)),
      })
      config.init(schema)

      -- Default tools registered
      store.record(L.DEFAULTS, nil, "append", "items", "alpha")
      store.record(L.DEFAULTS, nil, "append", "items", "beta")
      -- Frontmatter removes a typo'd name
      store.record(L.FRONTMATTER, 1, "remove", "items", "alph")

      local _, validation_failures = config.finalize(L.FRONTMATTER, nil, 1)

      assert.equals(1, #validation_failures)
      assert.equals("items", validation_failures[1].path)
      assert.equals("alph", validation_failures[1].value)
      assert.matches("unknown item 'alph'", validation_failures[1].message)
    end)

    it("validates items in a plain ListNode", function()
      local schema = s.object({
        tags = s.list(
          s.string():validate(function(value)
            if value == "invalid" then
              return false, "invalid tag"
            end
            return true
          end),
          {}
        ),
      })
      config.init(schema)
      config.apply(L.SETUP, { tags = { "good", "invalid", "fine" } })

      local _, validation_failures = config.finalize(L.SETUP, nil)

      assert.equals(1, #validation_failures)
      assert.equals("tags", validation_failures[1].path)
      assert.equals("invalid", validation_failures[1].value)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- finalize() with bufnr (frontmatter path)
  -- ---------------------------------------------------------------------------

  describe("finalize() with bufnr", function()
    it("returns failures for buffer-scoped validation", function()
      local schema = s.object({
        items = s.object({
          [symbols.DISCOVER] = function()
            return nil
          end,
        }):allow_list(s.string():validate(function(name)
          if name == "bad" then
            return false, "bad item"
          end
          return true
        end)),
      })
      config.init(schema)

      local bufnr = 1
      store.record(L.FRONTMATTER, bufnr, "append", "items", "good")
      store.record(L.FRONTMATTER, bufnr, "append", "items", "bad")

      local _, validation_failures = config.finalize(L.FRONTMATTER, nil, bufnr)

      assert.equals(1, #validation_failures)
      assert.equals("bad", validation_failures[1].value)
    end)

    it("returns empty table when all frontmatter values are valid", function()
      local schema = s.object({
        name = s.string("default"):validate(function()
          return true
        end),
      })
      config.init(schema)
      store.record(L.FRONTMATTER, 1, "set", "name", "good")

      local _, validation_failures = config.finalize(L.FRONTMATTER, nil, 1)

      assert.equals(0, #validation_failures)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Validator sees post-coerce values
  -- ---------------------------------------------------------------------------

  describe("coerce + validate interaction", function()
    it("validator sees coerced values, not raw input", function()
      local validated_value = nil
      local schema = s.object({
        mode = s.string("default")
          :coerce(function(value)
            if value == "shorthand" then
              return "expanded_form"
            end
            return value
          end)
          :validate(function(value)
            validated_value = value
            return true
          end),
      })
      config.init(schema)
      config.apply(L.SETUP, { mode = "shorthand" })

      config.finalize(L.SETUP, nil)

      assert.equals("expanded_form", validated_value)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Tool registry helpers
  -- ---------------------------------------------------------------------------

  describe("tools.registry", function()
    local registry

    before_each(function()
      package.loaded["flemma.tools.registry"] = nil
      package.loaded["flemma.utilities.string"] = nil
      registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("bash", {
        name = "bash",
        description = "Execute shell commands",
        input_schema = { type = "object" },
      })
      registry.register("read", {
        name = "read",
        description = "Read files",
        input_schema = { type = "object" },
      })
      registry.register("grep", {
        name = "grep",
        description = "Search files",
        input_schema = { type = "object" },
      })
    end)

    it("has() returns true for registered tools", function()
      assert.is_true(registry.has("bash"))
      assert.is_true(registry.has("read"))
    end)

    it("has() returns false for unregistered tools", function()
      assert.is_false(registry.has("nonexistent"))
    end)

    it("closest_match() finds close matches", function()
      assert.equals("bash", registry.closest_match("bsh"))
      assert.equals("bash", registry.closest_match("bassh"))
      assert.equals("read", registry.closest_match("raed"))
      assert.equals("grep", registry.closest_match("grp"))
    end)

    it("closest_match() returns nil for distant strings", function()
      assert.is_nil(registry.closest_match("xyzzy"))
      assert.is_nil(registry.closest_match("completely_unrelated"))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Integration: real schema definition tool name validation
  -- ---------------------------------------------------------------------------

  describe("tool name validation with real schema", function()
    local registry

    before_each(function()
      -- Reset tool registry
      package.loaded["flemma.tools.registry"] = nil
      package.loaded["flemma.utilities.string"] = nil
      registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("bash", {
        name = "bash",
        description = "Execute shell commands",
        input_schema = { type = "object" },
      })
      registry.register("read", {
        name = "read",
        description = "Read files",
        input_schema = { type = "object" },
      })

      -- Use the real schema definition
      package.loaded["flemma.config.schema.definition"] = nil
      local schema = require("flemma.config.schema.definition")
      config.init(schema)
    end)

    it("reports typo with did-you-mean suggestion", function()
      store.record(L.FRONTMATTER, 1, "remove", "tools", "bsh")

      local _, validation_failures = config.finalize(L.FRONTMATTER, nil, 1)

      assert.equals(1, #validation_failures)
      assert.matches("Unknown tool 'bsh'", validation_failures[1].message)
      assert.matches("did you mean 'bash'", validation_failures[1].message)
    end)

    it("reports typo without suggestion when too distant", function()
      store.record(L.FRONTMATTER, 1, "append", "tools", "xyzzy")

      local _, validation_failures = config.finalize(L.FRONTMATTER, nil, 1)

      assert.equals(1, #validation_failures)
      assert.matches("Unknown tool 'xyzzy'", validation_failures[1].message)
      assert.not_matches("did you mean", validation_failures[1].message)
    end)

    it("passes for valid registered tool names", function()
      store.record(L.FRONTMATTER, 1, "append", "tools", "bash")
      store.record(L.FRONTMATTER, 1, "append", "tools", "read")

      local _, validation_failures = config.finalize(L.FRONTMATTER, nil, 1)

      assert.equals(0, #validation_failures)
    end)
  end)
end)
