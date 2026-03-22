describe("flemma.config list operations", function()
  ---@type flemma.config.proxy
  local proxy
  ---@type flemma.config.store
  local store
  ---@type flemma.schema
  local s
  ---@type { DEFAULTS: integer, SETUP: integer, RUNTIME: integer, FRONTMATTER: integer }
  local L
  ---@type flemma.schema.Node
  local schema

  local function make_list_schema()
    return s.object({
      items = s.list(s.string(), {}),
      numbers = s.list(s.integer(), {}),
    })
  end

  before_each(function()
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.schema"] = nil
    package.loaded["flemma.schema.types"] = nil
    package.loaded["flemma.schema.navigation"] = nil
    package.loaded["flemma.loader"] = nil
    proxy = require("flemma.config.proxy")
    store = require("flemma.config.store")
    s = require("flemma.schema")
    L = store.LAYERS
    schema = make_list_schema()
  end)

  -- ---------------------------------------------------------------------------
  -- Append dedup semantics
  -- ---------------------------------------------------------------------------

  describe("append dedup", function()
    it("appending an existing item moves it to the end (appears once)", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b", "c" })
      store.record(L.SETUP, nil, "append", "items", "a")
      assert.are.same({ "b", "c", "a" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("appending the same item twice in the same layer moves it once", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b" })
      store.record(L.SETUP, nil, "append", "items", "c")
      store.record(L.SETUP, nil, "append", "items", "c")
      assert.are.same({ "a", "b", "c" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("appending moves item from middle to end", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b", "c" })
      store.record(L.SETUP, nil, "append", "items", "b")
      assert.are.same({ "a", "c", "b" }, store.resolve("items", nil, { is_list = true }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Remove then re-append
  -- ---------------------------------------------------------------------------

  describe("remove then re-append", function()
    it("removing then re-appending restores the item at the end", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b", "c" })
      store.record(L.SETUP, nil, "remove", "items", "b")
      store.record(L.SETUP, nil, "append", "items", "b")
      assert.are.same({ "a", "c", "b" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("removing a nonexistent item is a no-op", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b" })
      store.record(L.SETUP, nil, "remove", "items", "z")
      assert.are.same({ "a", "b" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("removing all items then appending builds a fresh list", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b" })
      store.record(L.SETUP, nil, "remove", "items", "a")
      store.record(L.SETUP, nil, "remove", "items", "b")
      store.record(L.SETUP, nil, "append", "items", "c")
      assert.are.same({ "c" }, store.resolve("items", nil, { is_list = true }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Prepend order preservation
  -- ---------------------------------------------------------------------------

  describe("prepend order preservation", function()
    it("multiple prepends preserve insertion order (last prepend is first)", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "c" })
      store.record(L.SETUP, nil, "prepend", "items", "b")
      store.record(L.SETUP, nil, "prepend", "items", "a")
      assert.are.same({ "a", "b", "c" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("prepend dedup moves item to front", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b", "c" })
      store.record(L.SETUP, nil, "prepend", "items", "c")
      assert.are.same({ "c", "a", "b" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("prepend then append: prepend goes first, append goes last", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "b" })
      store.record(L.SETUP, nil, "prepend", "items", "a")
      store.record(L.SETUP, nil, "append", "items", "c")
      assert.are.same({ "a", "b", "c" }, store.resolve("items", nil, { is_list = true }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Empty set followed by appends
  -- ---------------------------------------------------------------------------

  describe("empty set followed by appends", function()
    it("set to empty list then append builds from scratch", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b", "c" })
      store.record(L.SETUP, nil, "set", "items", {})
      store.record(L.SETUP, nil, "append", "items", "x")
      assert.are.same({ "x" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("set to empty list discards all lower-layer items", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b" })
      store.record(L.SETUP, nil, "append", "items", "c")
      store.record(L.RUNTIME, nil, "set", "items", {})
      assert.are.same({}, store.resolve("items", nil, { is_list = true }))
    end)

    it("set to empty at highest layer with appends at same layer", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "old" })
      store.record(L.FRONTMATTER, 1, "set", "items", {})
      store.record(L.FRONTMATTER, 1, "append", "items", "new")
      assert.are.same({ "new" }, store.resolve("items", 1, { is_list = true }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Cross-layer interactions
  -- ---------------------------------------------------------------------------

  describe("set and append/remove across layers", function()
    it("set at higher layer discards all lower layer ops", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b", "c" })
      store.record(L.SETUP, nil, "append", "items", "d")
      store.record(L.RUNTIME, nil, "set", "items", { "x" })
      assert.are.same({ "x" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("append at higher layer adds to lower layer's set", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a" })
      store.record(L.SETUP, nil, "append", "items", "b")
      store.record(L.RUNTIME, nil, "append", "items", "c")
      assert.are.same({ "a", "b", "c" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("remove at higher layer removes from lower layer's accumulated list", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b", "c" })
      store.record(L.SETUP, nil, "append", "items", "d")
      store.record(L.RUNTIME, nil, "remove", "items", "b")
      assert.are.same({ "a", "c", "d" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("frontmatter remove of defaults item", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "$default", "bash" })
      store.record(L.FRONTMATTER, 1, "remove", "items", "$default")
      assert.are.same({ "bash" }, store.resolve("items", 1, { is_list = true }))
    end)

    it("four-layer composition: set + append + append + remove", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b" })
      store.record(L.SETUP, nil, "append", "items", "c")
      store.record(L.RUNTIME, nil, "append", "items", "d")
      store.record(L.FRONTMATTER, 1, "remove", "items", "a")
      assert.are.same({ "b", "c", "d" }, store.resolve("items", 1, { is_list = true }))
    end)

    it("set in middle layer resets: only ops at and above that layer matter", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b" })
      store.record(L.SETUP, nil, "set", "items", { "x" })
      store.record(L.RUNTIME, nil, "append", "items", "y")
      assert.are.same({ "x", "y" }, store.resolve("items", nil, { is_list = true }))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Operator chaining via proxy
  -- ---------------------------------------------------------------------------

  describe("operator chaining", function()
    it("+ then + then -", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "$default" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.items = w.items + "a" + "b" - "$default"
      assert.are.same({ "a", "b" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("^ then + (prepend then append)", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "b" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.items = w.items ^ "a" + "c"
      assert.are.same({ "a", "b", "c" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("- then + (remove then re-add)", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b", "c" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.items = w.items - "b" + "b"
      assert.are.same({ "a", "c", "b" }, store.resolve("items", nil, { is_list = true }))
    end)

    it("chained operators record individual ops (not a single set)", function()
      store.init()
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      -- Note: ^ has higher precedence than + and - in Lua, so mixed chains
      -- with ^ must use method calls or explicit grouping.
      w.items:append("a")
      w.items:remove("b")
      w.items:prepend("c")
      local ops = store.dump_layer(L.SETUP, nil)
      assert.equals(3, #ops)
      assert.equals("append", ops[1].op)
      assert.equals("a", ops[1].value)
      assert.equals("remove", ops[2].op)
      assert.equals("b", ops[2].value)
      assert.equals("prepend", ops[3].op)
      assert.equals("c", ops[3].value)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Source attribution for lists
  -- ---------------------------------------------------------------------------

  describe("source attribution", function()
    it("single-layer list reports that layer as source", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a" })
      local _, source = store.resolve_with_source("items", nil, { is_list = true })
      assert.equals("D", source)
    end)

    it("multi-layer list reports combined source", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a" })
      store.record(L.SETUP, nil, "append", "items", "b")
      local _, source = store.resolve_with_source("items", nil, { is_list = true })
      assert.equals("D+S", source)
    end)

    it("set at higher layer reports only that layer", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a" })
      store.record(L.SETUP, nil, "set", "items", { "b" })
      local _, source = store.resolve_with_source("items", nil, { is_list = true })
      assert.equals("S", source)
    end)

    it("no-op remove does not add to contributing layers", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a" })
      store.record(L.SETUP, nil, "remove", "items", "nonexistent")
      local _, source = store.resolve_with_source("items", nil, { is_list = true })
      assert.equals("D", source)
    end)

    it("effective remove adds to contributing layers", function()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "items", { "a", "b" })
      store.record(L.SETUP, nil, "remove", "items", "a")
      local _, source = store.resolve_with_source("items", nil, { is_list = true })
      assert.equals("D+S", source)
    end)
  end)
end)
