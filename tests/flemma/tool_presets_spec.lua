package.loaded["flemma.tools.presets"] = nil

local presets = require("flemma.tools.presets")

describe("flemma.tools.presets", function()
  after_each(function()
    presets.clear()
  end)

  describe("setup()", function()
    it("registers built-in presets when called with nil", function()
      presets.setup(nil)
      assert.is_not_nil(presets.get("$readonly"))
      assert.is_not_nil(presets.get("$default"))
    end)

    it("built-in $readonly approves read only", function()
      presets.setup(nil)
      local preset = presets.get("$readonly")
      assert.are.same({ "read" }, preset.approve)
      assert.is_nil(preset.deny)
    end)

    it("built-in $default approves read, write, edit", function()
      presets.setup(nil)
      local preset = presets.get("$default")
      local approve = vim.deepcopy(preset.approve)
      table.sort(approve)
      assert.are.same({ "edit", "read", "write" }, approve)
      assert.is_nil(preset.deny)
    end)

    it("user presets override built-ins by name", function()
      presets.setup({ ["$default"] = { approve = { "bash" } } })
      local preset = presets.get("$default")
      assert.are.same({ "bash" }, preset.approve)
    end)

    it("user presets are added alongside built-ins", function()
      presets.setup({ ["$yolo"] = { approve = { "bash" }, deny = { "write" } } })
      assert.is_not_nil(presets.get("$yolo"))
      assert.is_not_nil(presets.get("$default"))
      assert.is_not_nil(presets.get("$readonly"))
    end)

    it("warns on preset key without $ prefix", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg)
        if msg:match("must start with") then
          warned = true
        end
      end
      presets.setup({ bad = { approve = { "read" } } })
      vim.notify = orig_notify
      assert.is_true(warned)
      assert.is_nil(presets.get("bad"))
    end)

    it("warns on non-table approve field", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg)
        if msg:match("approve") then
          warned = true
        end
      end
      presets.setup({ ["$bad"] = { approve = "read" } })
      vim.notify = orig_notify
      assert.is_true(warned)
    end)

    it("warns on non-table deny field", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg)
        if msg:match("deny") then
          warned = true
        end
      end
      presets.setup({ ["$bad"] = { deny = "bash" } })
      vim.notify = orig_notify
      assert.is_true(warned)
    end)
  end)

  describe("get()", function()
    it("returns nil for unknown preset", function()
      presets.setup(nil)
      assert.is_nil(presets.get("$nonexistent"))
    end)

    it("returns a deep copy", function()
      presets.setup(nil)
      local a = presets.get("$default")
      local b = presets.get("$default")
      assert.are.same(a, b)
      table.insert(a.approve, "bash")
      assert.are_not.same(a, presets.get("$default"))
    end)
  end)

  describe("get_all()", function()
    it("returns all presets", function()
      presets.setup(nil)
      local all = presets.get_all()
      assert.is_not_nil(all["$readonly"])
      assert.is_not_nil(all["$default"])
    end)
  end)

  describe("names()", function()
    it("returns sorted list of preset names", function()
      presets.setup({ ["$yolo"] = { approve = { "bash" } } })
      local names = presets.names()
      assert.are.same({ "$default", "$readonly", "$yolo" }, names)
    end)
  end)

  describe("clear()", function()
    it("removes all presets", function()
      presets.setup(nil)
      presets.clear()
      assert.is_nil(presets.get("$default"))
      assert.are.same({}, presets.names())
    end)
  end)
end)
