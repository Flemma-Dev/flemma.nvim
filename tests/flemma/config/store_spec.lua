describe("flemma.config.store", function()
  ---@type flemma.config.store
  local store
  ---@type { DEFAULTS: integer, SETUP: integer, RUNTIME: integer, FRONTMATTER: integer }
  local L

  before_each(function()
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.loader"] = nil
    store = require("flemma.config.store")
    L = store.LAYERS
    store.init()
  end)

  -- ---------------------------------------------------------------------------
  -- Scalar resolution
  -- ---------------------------------------------------------------------------

  describe("scalar resolution — top-down, first set wins", function()
    it("returns value from the only layer that has a set op", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      assert.equals("openai", store.resolve("provider", nil, { is_list = false }))
    end)

    it("higher-priority layer wins over lower-priority layer", function()
      store.record(L.DEFAULTS, nil, "set", "provider", "anthropic")
      store.record(L.SETUP, nil, "set", "provider", "openai")
      assert.equals("openai", store.resolve("provider", nil, { is_list = false }))
    end)

    it("RUNTIME beats SETUP", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      store.record(L.RUNTIME, nil, "set", "provider", "vertex")
      assert.equals("vertex", store.resolve("provider", nil, { is_list = false }))
    end)

    it("FRONTMATTER beats RUNTIME", function()
      store.record(L.RUNTIME, nil, "set", "provider", "vertex")
      store.record(L.FRONTMATTER, 1, "set", "provider", "anthropic")
      assert.equals("anthropic", store.resolve("provider", 1, { is_list = false }))
    end)

    it("falls through empty layers to lower layers", function()
      store.record(L.DEFAULTS, nil, "set", "provider", "anthropic")
      -- SETUP and RUNTIME have no ops for "provider"
      assert.equals("anthropic", store.resolve("provider", nil, { is_list = false }))
    end)

    it("returns nil when no layer has a set op", function()
      assert.is_nil(store.resolve("model", nil, { is_list = false }))
    end)

    it("last write wins within the same layer", function()
      store.record(L.SETUP, nil, "set", "provider", "first")
      store.record(L.SETUP, nil, "set", "provider", "second")
      assert.equals("second", store.resolve("provider", nil, { is_list = false }))
    end)

    it("nested scalar path resolves correctly", function()
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      assert.equals(600, store.resolve("parameters.timeout", nil, { is_list = false }))
    end)

    it("buffer layer overrides global layers for scalars", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      store.record(L.FRONTMATTER, 1, "set", "provider", "vertex")
      assert.equals("vertex", store.resolve("provider", 1, { is_list = false }))
    end)

    it("resolving without bufnr ignores buffer layer ops", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      store.record(L.FRONTMATTER, 1, "set", "provider", "vertex")
      -- nil bufnr: only global layers consulted
      assert.equals("openai", store.resolve("provider", nil, { is_list = false }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Buffer isolation
  -- ---------------------------------------------------------------------------

  describe("buffer isolation", function()
    it("bufnr A's frontmatter does not affect bufnr B resolution", function()
      store.record(L.FRONTMATTER, 1, "set", "provider", "openai")
      assert.is_nil(store.resolve("provider", 2, { is_list = false }))
    end)

    it("each buffer has an independent frontmatter layer", function()
      store.record(L.FRONTMATTER, 1, "set", "provider", "openai")
      store.record(L.FRONTMATTER, 2, "set", "provider", "vertex")
      assert.equals("openai", store.resolve("provider", 1, { is_list = false }))
      assert.equals("vertex", store.resolve("provider", 2, { is_list = false }))
    end)

    it("global layers are shared across all buffers", function()
      store.record(L.SETUP, nil, "set", "provider", "anthropic")
      -- Both buffers see the global setup value when they have no frontmatter ops
      assert.equals("anthropic", store.resolve("provider", 1, { is_list = false }))
      assert.equals("anthropic", store.resolve("provider", 2, { is_list = false }))
    end)

    it("buffer frontmatter overrides global without affecting other buffers", function()
      store.record(L.SETUP, nil, "set", "provider", "anthropic")
      store.record(L.FRONTMATTER, 1, "set", "provider", "openai")
      assert.equals("openai", store.resolve("provider", 1, { is_list = false }))
      assert.equals("anthropic", store.resolve("provider", 2, { is_list = false }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- List resolution — bottom-up accumulation
  -- ---------------------------------------------------------------------------

  describe("list resolution — bottom-up accumulation", function()
    it("set at defaults initializes the list", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      local result = store.resolve("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "$default" }, result)
    end)

    it("append adds item to end of inherited list", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "bash")
      local result = store.resolve("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "$default", "bash" }, result)
    end)

    it("prepend adds item to front of inherited list", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash", "grep" })
      store.record(L.SETUP, nil, "prepend", "tools.auto_approve", "find")
      local result = store.resolve("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "find", "bash", "grep" }, result)
    end)

    it("remove removes item from inherited list", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default", "bash" })
      store.record(L.SETUP, nil, "remove", "tools.auto_approve", "$default")
      local result = store.resolve("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "bash" }, result)
    end)

    it("remove of nonexistent item is a no-op", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash" })
      store.record(L.SETUP, nil, "remove", "tools.auto_approve", "nonexistent")
      local result = store.resolve("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "bash" }, result)
    end)

    it("set at higher layer discards all lower-layer ops", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "bash")
      store.record(L.RUNTIME, nil, "set", "tools.auto_approve", { "grep" })
      local result = store.resolve("tools.auto_approve", nil, { is_list = true })
      -- RUNTIME's set resets the accumulator; defaults and setup are discarded
      assert.are.same({ "grep" }, result)
    end)

    it("buffer layer ops apply on top of global list", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      store.record(L.FRONTMATTER, 1, "append", "tools.auto_approve", "bash")
      local result = store.resolve("tools.auto_approve", 1, { is_list = true })
      assert.are.same({ "$default", "bash" }, result)
    end)

    it("buffer layer set discards all global ops", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default", "grep" })
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "bash")
      store.record(L.FRONTMATTER, 1, "set", "tools.auto_approve", { "find" })
      local result = store.resolve("tools.auto_approve", 1, { is_list = true })
      assert.are.same({ "find" }, result)
    end)

    it("returns empty list when set op provides empty list", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", {})
      local result = store.resolve("tools.auto_approve", nil, { is_list = true })
      assert.are.same({}, result)
    end)

    it("returns nil when no ops exist for a list path", function()
      assert.is_nil(store.resolve("tools.modules", nil, { is_list = true }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Multiple ops at same layer compose
  -- ---------------------------------------------------------------------------

  describe("same-layer op composition", function()
    it("set then append within same layer: append applies after set", function()
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "bash" })
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "grep")
      local result = store.resolve("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "bash", "grep" }, result)
    end)

    it("multiple appends within same layer accumulate in order", function()
      store.record(L.SETUP, nil, "set", "tools.auto_approve", {})
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "a")
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "b")
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "c")
      local result = store.resolve("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "a", "b", "c" }, result)
    end)

    it("later set within same layer replaces earlier set (scalar)", function()
      store.record(L.RUNTIME, nil, "set", "provider", "openai")
      store.record(L.RUNTIME, nil, "set", "provider", "vertex")
      assert.equals("vertex", store.resolve("provider", nil, { is_list = false }))
    end)

    it("later set within same layer resets list accumulator", function()
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "bash" })
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "grep")
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "find" })
      local result = store.resolve("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "find" }, result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Multi-layer list composition (all 4 layers contribute)
  -- ---------------------------------------------------------------------------

  describe("multi-layer list composition", function()
    it("ops across all 4 layers compose correctly", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "bash")
      store.record(L.RUNTIME, nil, "remove", "tools.auto_approve", "$default")
      store.record(L.FRONTMATTER, 1, "prepend", "tools.auto_approve", "grep")
      local result = store.resolve("tools.auto_approve", 1, { is_list = true })
      -- D: ["$default"] → S: ["$default","bash"] → R: ["bash"] → F: ["grep","bash"]
      assert.are.same({ "grep", "bash" }, result)
    end)

    it("two independent buffers with different frontmatter ops", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      store.record(L.FRONTMATTER, 1, "append", "tools.auto_approve", "bash")
      store.record(L.FRONTMATTER, 2, "append", "tools.auto_approve", "grep")
      assert.are.same({ "$default", "bash" }, store.resolve("tools.auto_approve", 1, { is_list = true }))
      assert.are.same({ "$default", "grep" }, store.resolve("tools.auto_approve", 2, { is_list = true }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Layer clearing
  -- ---------------------------------------------------------------------------

  describe("layer clearing", function()
    it("clearing a global layer removes its ops", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      store.clear(L.SETUP, nil)
      assert.is_nil(store.resolve("provider", nil, { is_list = false }))
    end)

    it("clearing one global layer does not affect other global layers", function()
      store.record(L.DEFAULTS, nil, "set", "provider", "anthropic")
      store.record(L.SETUP, nil, "set", "provider", "openai")
      store.clear(L.SETUP, nil)
      assert.equals("anthropic", store.resolve("provider", nil, { is_list = false }))
    end)

    it("clearing buffer layer removes that buffer's ops", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      store.record(L.FRONTMATTER, 1, "set", "provider", "vertex")
      store.clear(L.FRONTMATTER, 1)
      assert.equals("openai", store.resolve("provider", 1, { is_list = false }))
    end)

    it("clearing buffer A does not affect buffer B", function()
      store.record(L.FRONTMATTER, 1, "set", "provider", "openai")
      store.record(L.FRONTMATTER, 2, "set", "provider", "vertex")
      store.clear(L.FRONTMATTER, 1)
      assert.is_nil(store.resolve("provider", 1, { is_list = false }))
      assert.equals("vertex", store.resolve("provider", 2, { is_list = false }))
    end)

    it("clearing list layer removes appended items", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "bash")
      store.clear(L.SETUP, nil)
      assert.are.same({ "$default" }, store.resolve("tools.auto_approve", nil, { is_list = true }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Introspection: resolve_with_source
  -- ---------------------------------------------------------------------------

  describe("resolve_with_source", function()
    it("returns layer indicator for scalar resolved from DEFAULTS", function()
      store.record(L.DEFAULTS, nil, "set", "provider", "anthropic")
      local value, source = store.resolve_with_source("provider", nil, { is_list = false })
      assert.equals("anthropic", value)
      assert.equals("D", source)
    end)

    it("returns layer indicator for scalar resolved from SETUP", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      local value, source = store.resolve_with_source("provider", nil, { is_list = false })
      assert.equals("openai", value)
      assert.equals("S", source)
    end)

    it("returns layer indicator for scalar resolved from RUNTIME", function()
      store.record(L.RUNTIME, nil, "set", "provider", "vertex")
      local value, source = store.resolve_with_source("provider", nil, { is_list = false })
      assert.equals("vertex", value)
      assert.equals("R", source)
    end)

    it("returns layer indicator for scalar resolved from FRONTMATTER", function()
      store.record(L.FRONTMATTER, 1, "set", "provider", "anthropic")
      local value, source = store.resolve_with_source("provider", 1, { is_list = false })
      assert.equals("anthropic", value)
      assert.equals("F", source)
    end)

    it("returns nil source when no value found", function()
      local value, source = store.resolve_with_source("model", nil, { is_list = false })
      assert.is_nil(value)
      assert.is_nil(source)
    end)

    it("returns single layer indicator for list from one layer", function()
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "bash" })
      local value, source = store.resolve_with_source("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "bash" }, value)
      assert.equals("S", source)
    end)

    it("list source reflects multiple contributing layers", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      store.record(L.FRONTMATTER, 1, "append", "tools.auto_approve", "bash")
      local value, source = store.resolve_with_source("tools.auto_approve", 1, { is_list = true })
      assert.are.same({ "$default", "bash" }, value)
      assert.equals("D+F", source)
    end)

    it("list source resets when a set op takes ownership", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "$default" })
      store.record(L.FRONTMATTER, 1, "append", "tools.auto_approve", "bash")
      local value, source = store.resolve_with_source("tools.auto_approve", 1, { is_list = true })
      assert.are.same({ "$default", "bash" }, value)
      -- SETUP's set takes ownership; DEFAULTS is not reflected in source
      assert.equals("S+F", source)
    end)

    it("list source reflects only the single set layer when no other ops exist", function()
      store.record(L.RUNTIME, nil, "set", "tools.auto_approve", { "find" })
      local value, source = store.resolve_with_source("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "find" }, value)
      assert.equals("R", source)
    end)

    it("returns nil source for list with no ops", function()
      local value, source = store.resolve_with_source("tools.modules", nil, { is_list = true })
      assert.is_nil(value)
      assert.is_nil(source)
    end)

    it("no-op remove does not add the layer to source attribution", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash" })
      store.record(L.SETUP, nil, "remove", "tools.auto_approve", "nonexistent")
      local value, source = store.resolve_with_source("tools.auto_approve", nil, { is_list = true })
      assert.are.same({ "bash" }, value)
      -- SETUP's remove was a no-op; only DEFAULTS shaped the value
      assert.equals("D", source)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- dump_layer
  -- ---------------------------------------------------------------------------

  describe("dump_layer", function()
    it("returns empty array when layer has no ops", function()
      local ops = store.dump_layer(L.SETUP, nil)
      assert.are.same({}, ops)
    end)

    it("returns ops recorded for a global layer", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      local ops = store.dump_layer(L.SETUP, nil)
      assert.equals(1, #ops)
      assert.equals("set", ops[1].op)
      assert.equals("provider", ops[1].path)
      assert.equals("openai", ops[1].value)
    end)

    it("returns ops for a specific buffer's frontmatter layer", function()
      store.record(L.FRONTMATTER, 1, "append", "tools.auto_approve", "bash")
      local ops = store.dump_layer(L.FRONTMATTER, 1)
      assert.equals(1, #ops)
      assert.equals("append", ops[1].op)
    end)

    it("returns a copy — mutations do not affect the store", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      local ops = store.dump_layer(L.SETUP, nil)
      ops[1].value = "mutated"
      -- Resolving again still returns the original value
      assert.equals("openai", store.resolve("provider", nil, { is_list = false }))
    end)

    it("returns empty array for FRONTMATTER layer with no ops for that buffer", function()
      -- Buffer 99 has never been written to
      local ops = store.dump_layer(L.FRONTMATTER, 99)
      assert.are.same({}, ops)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Edge cases: uninitialized store and empty buffer state
  -- ---------------------------------------------------------------------------

  describe("edge cases", function()
    it("resolve returns nil when called before init() has set any ops", function()
      -- init() was called with a fresh schema in before_each, but no ops recorded
      assert.is_nil(store.resolve("provider", nil, { is_list = false }))
    end)

    it("clear on a buffer that has never been written is a no-op", function()
      -- Buffer 99 has no ops; clearing it should not error
      store.clear(L.FRONTMATTER, 99)
      assert.is_nil(store.resolve("provider", 99, { is_list = false }))
    end)

    it("resolve after clear on never-written buffer returns global value", function()
      store.record(L.SETUP, nil, "set", "provider", "anthropic")
      store.clear(L.FRONTMATTER, 99)
      assert.equals("anthropic", store.resolve("provider", 99, { is_list = false }))
    end)

    it("record asserts on invalid op string", function()
      assert.has_error(function()
        store.record(L.SETUP, nil, "add", "provider", "openai")
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- layer_has_set
  -- ---------------------------------------------------------------------------

  describe("layer_has_set", function()
    it("returns true when layer has a set op for the path", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      assert.is_true(store.layer_has_set(L.SETUP, nil, "provider"))
    end)

    it("returns false when layer has no ops for the path", function()
      assert.is_false(store.layer_has_set(L.SETUP, nil, "provider"))
    end)

    it("returns false when layer has only non-set ops for the path", function()
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "bash")
      assert.is_false(store.layer_has_set(L.SETUP, nil, "tools.auto_approve"))
    end)

    it("distinguishes between layers", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      assert.is_true(store.layer_has_set(L.SETUP, nil, "provider"))
      assert.is_false(store.layer_has_set(L.RUNTIME, nil, "provider"))
    end)

    it("works with FRONTMATTER layer", function()
      store.record(L.FRONTMATTER, 1, "set", "tools.auto_approve", { "bash" })
      assert.is_true(store.layer_has_set(L.FRONTMATTER, 1, "tools.auto_approve"))
      assert.is_false(store.layer_has_set(L.FRONTMATTER, 2, "tools.auto_approve"))
    end)

    it("distinguishes between paths", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      assert.is_true(store.layer_has_set(L.SETUP, nil, "provider"))
      assert.is_false(store.layer_has_set(L.SETUP, nil, "model"))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- transform_ops
  -- ---------------------------------------------------------------------------

  describe("transform_ops", function()
    it("transforms set op values for lists (per-item)", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default", "other" })
      store.transform_ops("tools.auto_approve", function(value)
        if value == "$default" then
          return { "bash", "grep" }
        end
        return value
      end, nil, nil, { is_list = true })
      assert.are.same({ "bash", "grep", "other" }, store.resolve("tools.auto_approve", nil, { is_list = true }))
    end)

    it("expands append ops into multiple ops", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash" })
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "$default")
      store.transform_ops("tools.auto_approve", function(value)
        if value == "$default" then
          return { "grep", "find" }
        end
        return value
      end, nil, nil, { is_list = true })
      -- $default appended → expanded to append("grep"), append("find")
      assert.are.same({ "bash", "grep", "find" }, store.resolve("tools.auto_approve", nil, { is_list = true }))
    end)

    it("expands remove ops into multiple ops", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash", "grep", "find" })
      store.record(L.FRONTMATTER, 1, "remove", "tools.auto_approve", "$all")
      store.transform_ops("tools.auto_approve", function(value)
        if value == "$all" then
          return { "bash", "grep", "find" }
        end
        return value
      end, nil, nil, { is_list = true })
      -- remove("$all") → remove("bash"), remove("grep"), remove("find")
      assert.are.same({}, store.resolve("tools.auto_approve", 1, { is_list = true }))
    end)

    it("expands prepend ops into multiple ops", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash" })
      store.record(L.SETUP, nil, "prepend", "tools.auto_approve", "$preset")
      store.transform_ops("tools.auto_approve", function(value)
        if value == "$preset" then
          return { "grep", "find" }
        end
        return value
      end, nil, nil, { is_list = true })
      -- prepend("$preset") → prepend("grep"), prepend("find")
      -- prepend inserts at front: find, grep, then bash after
      assert.are.same({ "find", "grep", "bash" }, store.resolve("tools.auto_approve", nil, { is_list = true }))
    end)

    it("passes context to the transform function", function()
      store.record(L.DEFAULTS, nil, "set", "provider", "test_value")
      local received_ctx = nil
      store.transform_ops("provider", function(value, ctx)
        received_ctx = ctx
        return value
      end, { my_key = "my_value" }, nil, { is_list = false })
      assert.equals("my_value", received_ctx.my_key)
    end)

    it("leaves non-matching paths untouched", function()
      store.record(L.DEFAULTS, nil, "set", "provider", "anthropic")
      store.record(L.DEFAULTS, nil, "set", "model", "haiku")
      store.transform_ops("provider", function()
        return "transformed"
      end, nil, nil, { is_list = false })
      assert.equals("transformed", store.resolve("provider", nil, { is_list = false }))
      assert.equals("haiku", store.resolve("model", nil, { is_list = false }))
    end)

    it("transforms ops across global and buffer layers", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$d" })
      store.record(L.FRONTMATTER, 1, "remove", "tools.auto_approve", "$d")
      store.transform_ops("tools.auto_approve", function(value)
        if value == "$d" then
          return { "bash", "grep" }
        end
        return value
      end, nil, nil, { is_list = true })
      -- D: set(["bash","grep"]), F(1): remove("bash"), remove("grep")
      assert.are.same({}, store.resolve("tools.auto_approve", 1, { is_list = true }))
    end)

    it("non-table return replaces single item in set list", function()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "old" })
      store.transform_ops("tools.auto_approve", function(value)
        if value == "old" then
          return "new"
        end
        return value
      end, nil, nil, { is_list = true })
      assert.are.same({ "new" }, store.resolve("tools.auto_approve", nil, { is_list = true }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- allow_list: store recognizes ObjectNode with list part
  -- ---------------------------------------------------------------------------

  describe("allow_list store integration", function()
    it("list ops work on an allow_list object path", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "tools", { "bash", "grep" })
      store.record(L.SETUP, nil, "append", "tools", "find")
      assert.are.same({ "bash", "grep", "find" }, store.resolve("tools", nil, { is_list = true }))
    end)

    it("sub-path ops work independently of list ops", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "tools", { "bash" })
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "grep" })
      assert.are.same({ "bash" }, store.resolve("tools", nil, { is_list = true }))
      assert.are.same({ "grep" }, store.resolve("tools.auto_approve", nil, { is_list = true }))
    end)

    it("remove op on list part works", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "tools", { "bash", "grep", "find" })
      store.record(L.FRONTMATTER, 1, "remove", "tools", "grep")
      assert.are.same({ "bash", "find" }, store.resolve("tools", 1, { is_list = true }))
    end)
  end)
end)
