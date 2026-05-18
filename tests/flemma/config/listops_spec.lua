describe("flemma.config.listops", function()
  local listops

  before_each(function()
    package.loaded["flemma.config.listops"] = nil
    listops = require("flemma.config.listops")
  end)

  describe("parse()", function()
    it("returns set with all items when no prefixes present", function()
      local result = listops.parse({ "read", "write", "bash" })
      assert.are.same({ "read", "write", "bash" }, result.set_items)
      assert.are.same({}, result.ops)
      assert.are.same({}, result.refs)
    end)

    it("returns set with empty list for empty table", function()
      local result = listops.parse({})
      assert.are.same({}, result.set_items)
      assert.are.same({}, result.ops)
      assert.are.same({}, result.refs)
    end)

    it("parses + prefix as append", function()
      local result = listops.parse({ "+bash" })
      assert.is_nil(result.set_items)
      assert.are.same({ { op = "append", value = "bash" } }, result.ops)
    end)

    it("parses ^ prefix as prepend", function()
      local result = listops.parse({ "^find" })
      assert.is_nil(result.set_items)
      assert.are.same({ { op = "prepend", value = "find" } }, result.ops)
    end)

    it("parses ! prefix as remove", function()
      local result = listops.parse({ "!bash" })
      assert.is_nil(result.set_items)
      assert.are.same({ { op = "remove", value = "bash" } }, result.ops)
    end)

    it("parses $ prefix as a reference", function()
      local result = listops.parse({ "$standard" })
      assert.is_nil(result.set_items)
      assert.are.same({ "$standard" }, result.refs)
      assert.are.same({}, result.ops)
    end)

    it("separates bare values, refs, and ops", function()
      local result = listops.parse({ "read", "$standard", "!grep", "+bash" })
      assert.are.same({ "read" }, result.set_items)
      assert.are.same({ "$standard" }, result.refs)
      assert.are.same({
        { op = "remove", value = "grep" },
        { op = "append", value = "bash" },
      }, result.ops)
    end)

    it("preserves declaration order of ops", function()
      local result = listops.parse({ "+a", "!b", "^c", "+d" })
      assert.is_nil(result.set_items)
      assert.equals("append", result.ops[1].op)
      assert.equals("remove", result.ops[2].op)
      assert.equals("prepend", result.ops[3].op)
      assert.equals("append", result.ops[4].op)
    end)

    it("treats non-string items as bare values", function()
      local result = listops.parse({ 42, true })
      assert.are.same({ 42, true }, result.set_items)
    end)

    it("treats single-character prefix strings as bare values", function()
      local result = listops.parse({ "+", "!", "^", "$" })
      assert.are.same({ "+", "!", "^", "$" }, result.set_items)
    end)

    it("returns nil set_items and empty ops for non-table input", function()
      local result = listops.parse("not a table")
      assert.is_nil(result.set_items)
      assert.are.same({}, result.ops)
      assert.are.same({}, result.refs)
    end)

    it("errors on composed operator prefixes", function()
      assert.has_error(function()
        listops.parse({ "!$standard" })
      end)
      assert.has_error(function()
        listops.parse({ "+^bash" })
      end)
      assert.has_error(function()
        listops.parse({ "!+bash" })
      end)
      assert.has_error(function()
        listops.parse({ "^$readonly" })
      end)
    end)

    it("treats $UpperCase as a bare value, not a preset reference", function()
      local result = listops.parse({ "$UpperCase", "bash" })
      assert.are.same({ "$UpperCase", "bash" }, result.set_items)
      assert.are.same({}, result.refs)
    end)
  end)

  describe("resolve_references()", function()
    local presets

    before_each(function()
      package.loaded["flemma.presets"] = nil
      package.loaded["flemma.config.listops"] = nil
      presets = require("flemma.presets")
      presets.clear()
      presets.setup({
        ["$standard"] = { auto_approve = { "read", "write", "edit" } },
        ["$readonly"] = { auto_approve = { "read", "grep" } },
        ["$bashless"] = { tools = { "!bash" } },
        ["$basic_tools"] = { tools = { "bash", "read", "write" } },
      })
      listops = require("flemma.config.listops")
    end)

    after_each(function()
      presets.clear()
    end)

    it("resolves a single reference for auto_approve", function()
      local result = listops.resolve_references({ "$standard" }, "auto_approve")
      assert.are.same({ "read", "write", "edit" }, result)
    end)

    it("resolves a single reference for tools", function()
      local result = listops.resolve_references({ "$basic_tools" }, "tools")
      assert.are.same({ "bash", "read", "write" }, result)
    end)

    it("resolves multiple references and concatenates", function()
      local result = listops.resolve_references({ "$standard", "$readonly" }, "auto_approve")
      assert.are.same({ "read", "write", "edit", "read", "grep" }, result)
    end)

    it("returns empty for reference to preset without the field", function()
      local result = listops.resolve_references({ "$standard" }, "tools")
      assert.are.same({}, result)
    end)

    it("returns empty for unknown preset reference", function()
      local result = listops.resolve_references({ "$nonexistent" }, "tools")
      assert.are.same({}, result)
    end)

    it("preserves ops from referenced values", function()
      local result = listops.resolve_references({ "$bashless" }, "tools")
      assert.are.same({ "!bash" }, result)
    end)
  end)

  describe("apply()", function()
    local store_mod, L, presets

    before_each(function()
      package.loaded["flemma.config.store"] = nil
      package.loaded["flemma.presets"] = nil
      package.loaded["flemma.config.listops"] = nil
      store_mod = require("flemma.config.store")
      L = store_mod.LAYERS
      store_mod.init()
      presets = require("flemma.presets")
      presets.clear()
      presets.setup({
        ["$standard"] = { auto_approve = { "read", "write", "edit" } },
        ["$bashless"] = { tools = { "!bash" } },
        ["$basic_tools"] = { tools = { "bash", "read", "write" } },
      })
      listops = require("flemma.config.listops")
    end)

    after_each(function()
      presets.clear()
    end)

    it("records a set op for bare values", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "grep" })
      listops.apply(L.RUNTIME, nil, "tools", { "read", "write" })
      assert.are.same({ "read", "write" }, store_mod.resolve("tools", nil, { is_list = true }))
    end)

    it("records an empty set for empty table", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "grep" })
      listops.apply(L.RUNTIME, nil, "tools", {})
      assert.are.same({}, store_mod.resolve("tools", nil, { is_list = true }))
    end)

    it("records remove ops without a set when all items are prefixed", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "grep", "read" })
      listops.apply(L.RUNTIME, nil, "tools", { "!bash" })
      assert.are.same({ "grep", "read" }, store_mod.resolve("tools", nil, { is_list = true }))
    end)

    it("resolves $ references and merges with bare values and ops", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "old" })
      listops.apply(L.RUNTIME, nil, "tools", { "$basic_tools", "!bash" })
      assert.are.same({ "read", "write" }, store_mod.resolve("tools", nil, { is_list = true }))
    end)

    it("resolves $ references that contain ops", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "read", "write" })
      listops.apply(L.RUNTIME, nil, "tools", { "$bashless" })
      assert.are.same({ "read", "write" }, store_mod.resolve("tools", nil, { is_list = true }))
    end)

    it("derives field name from last path segment", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash" })
      listops.apply(L.RUNTIME, nil, "tools.auto_approve", { "$standard" })
      assert.are.same({ "read", "write", "edit" }, store_mod.resolve("tools.auto_approve", nil, { is_list = true }))
    end)

    it("handles mixed bare values + refs + ops", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "old" })
      listops.apply(L.RUNTIME, nil, "tools.auto_approve", { "bash", "$standard", "!edit" })
      assert.are.same({ "bash", "read", "write" }, store_mod.resolve("tools.auto_approve", nil, { is_list = true }))
    end)

    it("records append ops for + prefixed items", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "read" })
      listops.apply(L.RUNTIME, nil, "tools", { "+write" })
      assert.are.same({ "bash", "read", "write" }, store_mod.resolve("tools", nil, { is_list = true }))
    end)

    it("records prepend ops for ^ prefixed items", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "read" })
      listops.apply(L.RUNTIME, nil, "tools", { "^write" })
      assert.are.same({ "write", "bash", "read" }, store_mod.resolve("tools", nil, { is_list = true }))
    end)

    it("preserves unresolved refs as-is when no refs resolve and no ops", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash" })
      listops.apply(L.RUNTIME, nil, "tools", { "$unknown" })
      local ops = store_mod.dump_layer(L.RUNTIME)
      assert.are.equal(1, #ops)
      assert.are.equal("set", ops[1].op)
      assert.are.same({ "$unknown" }, ops[1].value)
    end)

    it("is a no-op when preset exists but lacks the target field", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "read" })
      listops.apply(L.RUNTIME, nil, "tools", { "$standard" })
      local ops = store_mod.dump_layer(L.RUNTIME)
      assert.are.equal(0, #ops)
      assert.are.same({ "bash", "read" }, store_mod.resolve("tools", nil, { is_list = true }))
    end)
  end)

  describe("expand_deferred()", function()
    local store_mod, L, presets

    before_each(function()
      package.loaded["flemma.config.store"] = nil
      package.loaded["flemma.presets"] = nil
      package.loaded["flemma.config.listops"] = nil
      store_mod = require("flemma.config.store")
      L = store_mod.LAYERS
      store_mod.init()
      presets = require("flemma.presets")
      presets.clear()
      presets.setup({
        ["$standard"] = { auto_approve = { "read", "write", "edit" } },
        ["$bashless"] = { tools = { "!bash" } },
        ["$basic_tools"] = { tools = { "bash", "read", "write" } },
      })
      listops = require("flemma.config.listops")
    end)

    after_each(function()
      presets.clear()
    end)

    it("expands $ref in a set op into bare values", function()
      store_mod.record(L.DEFAULTS, nil, "set", "auto_approve", { "$standard", "bash" })
      listops.expand_deferred(L.DEFAULTS, nil, { "auto_approve" })
      local result = store_mod.resolve("auto_approve", nil, { is_list = true })
      assert.are.same({ "bash", "read", "write", "edit" }, result)
    end)

    it("expands $ref that contains ops in a set op", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "read", "write" })
      store_mod.record(L.RUNTIME, nil, "set", "tools", { "$bashless" })
      listops.expand_deferred(L.RUNTIME, nil, { "tools" })
      local result = store_mod.resolve("tools", nil, { is_list = true })
      assert.are.same({ "read", "write" }, result)
    end)

    it("expands $ref in an append op", function()
      store_mod.record(L.DEFAULTS, nil, "set", "auto_approve", { "bash" })
      store_mod.record(L.RUNTIME, nil, "append", "auto_approve", "$standard")
      listops.expand_deferred(L.RUNTIME, nil, { "auto_approve" })
      local result = store_mod.resolve("auto_approve", nil, { is_list = true })
      assert.are.same({ "bash", "read", "write", "edit" }, result)
    end)

    it("expands $ref in a prepend op", function()
      store_mod.record(L.DEFAULTS, nil, "set", "auto_approve", { "bash" })
      store_mod.record(L.RUNTIME, nil, "prepend", "auto_approve", "$standard")
      listops.expand_deferred(L.RUNTIME, nil, { "auto_approve" })
      local result = store_mod.resolve("auto_approve", nil, { is_list = true })
      assert.are.same({ "edit", "write", "read", "bash" }, result)
    end)

    it("expands $ref that resolves to op-prefixed values in append position", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "read", "write" })
      store_mod.record(L.RUNTIME, nil, "append", "tools", "$bashless")
      listops.expand_deferred(L.RUNTIME, nil, { "tools" })
      local result = store_mod.resolve("tools", nil, { is_list = true })
      assert.are.same({ "read", "write" }, result)
    end)

    it("preserves unresolved refs in set ops", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "$unknown", "bash" })
      listops.expand_deferred(L.DEFAULTS, nil, { "tools" })
      local ops = store_mod.dump_layer(L.DEFAULTS)
      assert.are.equal(1, #ops)
      assert.are.same({ "$unknown", "bash" }, ops[1].value)
    end)

    it("preserves unresolved refs in append ops", function()
      store_mod.record(L.RUNTIME, nil, "append", "tools", "$unknown")
      listops.expand_deferred(L.RUNTIME, nil, { "tools" })
      local ops = store_mod.dump_layer(L.RUNTIME)
      assert.are.equal(1, #ops)
      assert.are.equal("append", ops[1].op)
      assert.are.equal("$unknown", ops[1].value)
    end)

    it("expands $ref in a remove op for auto_approve", function()
      store_mod.record(L.DEFAULTS, nil, "set", "auto_approve", { "read", "write", "edit", "bash" })
      store_mod.record(L.RUNTIME, nil, "remove", "auto_approve", "$standard")
      listops.expand_deferred(L.RUNTIME, nil, { "auto_approve" })
      local result = store_mod.resolve("auto_approve", nil, { is_list = true })
      assert.are.same({ "bash" }, result)
    end)

    it("expands $ref in a remove op for tools", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "read", "write", "grep" })
      store_mod.record(L.RUNTIME, nil, "remove", "tools", "$basic_tools")
      listops.expand_deferred(L.RUNTIME, nil, { "tools" })
      local result = store_mod.resolve("tools", nil, { is_list = true })
      assert.are.same({ "grep" }, result)
    end)

    it("does not modify ops on non-list paths", function()
      store_mod.record(L.DEFAULTS, nil, "set", "provider", "anthropic")
      listops.expand_deferred(L.DEFAULTS, nil, { "tools" })
      assert.are.equal("anthropic", store_mod.resolve("provider", nil))
    end)

    it("does not modify layer when nothing changed", function()
      store_mod.record(L.DEFAULTS, nil, "set", "tools", { "bash", "read" })
      listops.expand_deferred(L.DEFAULTS, nil, { "tools" })
      local ops = store_mod.dump_layer(L.DEFAULTS)
      assert.are.equal(1, #ops)
      assert.are.same({ "bash", "read" }, ops[1].value)
    end)
  end)
end)
