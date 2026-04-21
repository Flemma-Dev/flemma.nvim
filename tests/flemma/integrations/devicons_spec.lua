package.loaded["flemma.integrations.nvim-web-devicons"] = nil

local devicons

describe("flemma.integrations.nvim-web-devicons", function()
  before_each(function()
    package.loaded["flemma.integrations.nvim-web-devicons"] = nil
    package.loaded["nvim-web-devicons"] = nil
    devicons = require("flemma.integrations.nvim-web-devicons")
  end)

  describe("setup()", function()
    it("calls set_icon on nvim-web-devicons with the configured icon", function()
      local captured = nil
      package.loaded["nvim-web-devicons"] = {
        set_icon = function(icons)
          captured = icons
        end,
      }

      devicons.setup({ icon = "🪶" })

      assert.is_not_nil(captured)
      assert.are.same({
        chat = { icon = "🪶", name = "Chat" },
      }, captured)
    end)

    it("propagates a custom icon to the delegate", function()
      local captured = nil
      package.loaded["nvim-web-devicons"] = {
        set_icon = function(icons)
          captured = icons
        end,
      }

      devicons.setup({ icon = "X" })

      assert.are.same({
        chat = { icon = "X", name = "Chat" },
      }, captured)
    end)

    it("returns silently when no provider is available", function()
      assert.has_no.errors(function()
        devicons.setup({ icon = "🪶" })
      end)
    end)

    it("does not propagate errors from a misbehaving provider", function()
      package.loaded["nvim-web-devicons"] = {
        set_icon = function()
          error("API changed")
        end,
      }

      assert.has_no.errors(function()
        devicons.setup({ icon = "🪶" })
      end)
    end)
  end)
end)
