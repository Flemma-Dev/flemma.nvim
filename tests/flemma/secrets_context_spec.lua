--- Unit tests for flemma.secrets.context

local context
local config_facade

describe("flemma.secrets.context", function()
  before_each(function()
    package.loaded["flemma.secrets.context"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema.definition"] = nil
    config_facade = require("flemma.config")
    local schema = require("flemma.config.schema.definition")
    config_facade.init(schema)
    context = require("flemma.secrets.context")
  end)

  describe("new", function()
    it("returns an object with get_config method", function()
      local ctx = context.new("gcloud")
      assert.is_not_nil(ctx)
      assert.is_function(ctx.get_config)
    end)

    it("get_config returns nil when resolver subtable is absent", function()
      -- "nonexistent" has no schema entry, so it resolves to nil
      local ctx = context.new("nonexistent")
      assert.is_nil(ctx:get_config())
    end)

    it("get_config returns the resolver subtable", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { secrets = { gcloud = { path = "/nix/store/gcloud" } } })
      local ctx = context.new("gcloud")
      local cfg = ctx:get_config()
      assert.is_not_nil(cfg)
      assert.equals("/nix/store/gcloud", cfg.path)
    end)

    it("get_config returns schema defaults when no user config applied", function()
      local ctx = context.new("gcloud")
      local cfg = ctx:get_config()
      assert.is_not_nil(cfg)
      assert.equals("gcloud", cfg.path)
    end)

    it("get_config returns a deep copy (mutations do not affect state)", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { secrets = { gcloud = { path = "gcloud" } } })
      local ctx = context.new("gcloud")
      local cfg = ctx:get_config()
      cfg.path = "mutated"
      local cfg2 = ctx:get_config()
      assert.equals("gcloud", cfg2.path)
    end)

    it("different resolver names return independent configs", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { secrets = { gcloud = { path = "/path/to/gcloud" } } })
      local gcloud_ctx = context.new("gcloud")
      local nonexistent_ctx = context.new("nonexistent")
      assert.equals("/path/to/gcloud", gcloud_ctx:get_config().path)
      assert.is_nil(nonexistent_ctx:get_config())
    end)

    it("get_diagnostics returns empty table by default", function()
      local ctx = context.new("gcloud")
      assert.same({}, ctx:get_diagnostics())
    end)

    it("diagnostic appends a ResolverDiagnostic entry", function()
      local ctx = context.new("gcloud")
      ctx:diagnostic("executable not found")
      local diags = ctx:get_diagnostics()
      assert.equals(1, #diags)
      assert.equals("gcloud", diags[1].resolver)
      assert.equals("executable not found", diags[1].message)
    end)

    it("multiple diagnostics accumulate in order", function()
      local ctx = context.new("gcloud")
      ctx:diagnostic("first issue")
      ctx:diagnostic("second issue")
      local diags = ctx:get_diagnostics()
      assert.equals(2, #diags)
      assert.equals("first issue", diags[1].message)
      assert.equals("second issue", diags[2].message)
    end)

    it("diagnostics are scoped to the resolver name", function()
      local ctx_a = context.new("environment")
      local ctx_b = context.new("gcloud")
      ctx_a:diagnostic("var not set")
      ctx_b:diagnostic("binary missing")
      assert.equals("environment", ctx_a:get_diagnostics()[1].resolver)
      assert.equals("gcloud", ctx_b:get_diagnostics()[1].resolver)
    end)
  end)
end)
