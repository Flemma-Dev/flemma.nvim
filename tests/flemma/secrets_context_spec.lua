--- Unit tests for flemma.secrets.context

local context
local state

describe("flemma.secrets.context", function()
  before_each(function()
    package.loaded["flemma.secrets.context"] = nil
    package.loaded["flemma.state"] = nil
    state = require("flemma.state")
    context = require("flemma.secrets.context")
  end)

  describe("new", function()
    it("returns an object with get_config method", function()
      local ctx = context.new("gcloud")
      assert.is_not_nil(ctx)
      assert.is_function(ctx.get_config)
    end)

    it("get_config returns nil when no secrets config exists", function()
      state.set_config({})
      local ctx = context.new("gcloud")
      assert.is_nil(ctx:get_config())
    end)

    it("get_config returns nil when resolver subtable is absent", function()
      state.set_config({ secrets = {} })
      local ctx = context.new("gcloud")
      assert.is_nil(ctx:get_config())
    end)

    it("get_config returns the resolver subtable", function()
      state.set_config({ secrets = { gcloud = { path = "/nix/store/gcloud" } } })
      local ctx = context.new("gcloud")
      local cfg = ctx:get_config()
      assert.is_not_nil(cfg)
      assert.equals("/nix/store/gcloud", cfg.path)
    end)

    it("get_config returns a deep copy (mutations do not affect state)", function()
      state.set_config({ secrets = { gcloud = { path = "gcloud" } } })
      local ctx = context.new("gcloud")
      local cfg = ctx:get_config()
      cfg.path = "mutated"
      local cfg2 = ctx:get_config()
      assert.equals("gcloud", cfg2.path)
    end)

    it("different resolver names return independent configs", function()
      state.set_config({
        secrets = {
          gcloud = { path = "/path/to/gcloud" },
          other = { foo = "bar" },
        },
      })
      local gcloud_ctx = context.new("gcloud")
      local other_ctx = context.new("other")
      assert.equals("/path/to/gcloud", gcloud_ctx:get_config().path)
      assert.equals("bar", other_ctx:get_config().foo)
    end)
  end)
end)
