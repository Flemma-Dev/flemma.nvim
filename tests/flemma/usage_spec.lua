describe("flemma.usage", function()
  local usage
  local config_facade
  local session_module

  before_each(function()
    package.loaded["flemma.usage"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.pricing"] = nil
    package.loaded["flemma.session"] = nil
    package.loaded["flemma.ui.bar.layout"] = nil

    config_facade = require("flemma.config")
    local schema = require("flemma.config.schema")
    config_facade.init(schema)
    config_facade.apply(config_facade.LAYERS.SETUP, {
      pricing = { enabled = true },
    })

    usage = require("flemma.usage")
    session_module = require("flemma.session")
  end)

  describe("calculate_cache_percent", function()
    it("should return nil when total input is 0", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 0,
        output_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })
      assert.is_nil(usage.calculate_cache_percent(request))
    end)

    it("should calculate percentage correctly", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 200,
        input_price = 3.00,
        output_price = 15.00,
        cache_read_input_tokens = 400,
        cache_creation_input_tokens = 0,
      })
      assert.are.equal(80, usage.calculate_cache_percent(request))
    end)
  end)

  --- Find an item by key across all segments
  ---@param segments table[]
  ---@param key string
  ---@return table|nil
  local function find_item(segments, key)
    for _, segment in ipairs(segments) do
      for _, item in ipairs(segment.items or {}) do
        if item.key == key then
          return item
        end
      end
    end
    return nil
  end

  describe("cache percentage with min_cache_tokens threshold", function()
    it("should omit cache_percent when 0% and below min_cache_tokens", function()
      -- Anthropic haiku-4-5 has min_cache_tokens = 4096
      -- Total input = 2000 (below 4096), cache = 0%
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-haiku-4-5",
        input_tokens = 2000,
        output_tokens = 500,
        input_price = 1.00,
        output_price = 5.00,
        cache_read_input_tokens = 0,
        cache_creation_input_tokens = 0,
      })
      local segments = usage.build_segments(request, nil)
      local cache_item = find_item(segments, "cache_percent")
      assert.is_nil(cache_item)
    end)

    it("should show cache_percent when 0% but above min_cache_tokens", function()
      -- Total input = 10000 (above 4096), cache = 0%
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-haiku-4-5",
        input_tokens = 10000,
        output_tokens = 500,
        input_price = 1.00,
        output_price = 5.00,
        cache_read_input_tokens = 0,
        cache_creation_input_tokens = 0,
      })
      local segments = usage.build_segments(request, nil)
      local cache_item = find_item(segments, "cache_percent")
      assert.is_not_nil(cache_item)
    end)

    it("should show cache_percent when nonzero regardless of threshold", function()
      -- Total input = 2000 (below 4096), but cache_read > 0
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-haiku-4-5",
        input_tokens = 1000,
        output_tokens = 500,
        input_price = 1.00,
        output_price = 5.00,
        cache_read_input_tokens = 1000,
        cache_creation_input_tokens = 0,
      })
      local segments = usage.build_segments(request, nil)
      local cache_item = find_item(segments, "cache_percent")
      assert.is_not_nil(cache_item)
    end)
  end)

  describe("build_segments", function()
    it("should build identity segment from request", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })

      local segments = usage.build_segments(request, nil)

      -- Find identity segment
      local identity = nil
      for _, segment in ipairs(segments) do
        if segment.key == "identity" then
          identity = segment
        end
      end

      assert.is_not_nil(identity)

      -- Find model_name item
      local model_item = nil
      for _, item in ipairs(identity.items) do
        if item.key == "model_name" then
          model_item = item
        end
      end

      assert.is_not_nil(model_item)
      assert.are.equal("gpt-4o", model_item.text)
      assert.are.equal(110, model_item.priority)
    end)

    it("should build request segment with cost and cache", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 200,
        input_price = 3.00,
        output_price = 15.00,
        cache_read_input_tokens = 400,
        cache_creation_input_tokens = 0,
      })

      local segments = usage.build_segments(request, nil)

      local request_segment = nil
      for _, segment in ipairs(segments) do
        if segment.key == "request" then
          request_segment = segment
        end
      end

      assert.is_not_nil(request_segment)

      -- Should have cost, cache, input tokens, output tokens
      local keys = {}
      for _, item in ipairs(request_segment.items) do
        keys[item.key] = item
      end

      assert.is_not_nil(keys["request_cost"])
      assert.has_match("%$", keys["request_cost"].text)

      assert.is_not_nil(keys["cache_percent"])
      assert.has_match("80%%", keys["cache_percent"].text)
      assert.is_not_nil(keys["cache_percent"].highlight)
      assert.are.equal("FlemmaUsageBarCacheGood", keys["cache_percent"].highlight.group)
    end)

    it("should not include cost items when pricing disabled", function()
      config_facade.init(require("flemma.config.schema"))
      config_facade.apply(config_facade.LAYERS.SETUP, {
        pricing = { enabled = false },
      })

      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })

      local segments = usage.build_segments(request, nil)

      local request_segment = nil
      for _, segment in ipairs(segments) do
        if segment.key == "request" then
          request_segment = segment
        end
      end

      -- Should not have cost item
      for _, item in ipairs(request_segment.items) do
        assert.is_not_equal("request_cost", item.key)
      end
    end)

    it("should build session segment with label", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })

      local session = session_module.Session.new()
      session:add_request({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 500,
        output_tokens = 300,
        thoughts_tokens = 100,
        input_price = 2.50,
        output_price = 10.00,
      })

      local segments = usage.build_segments(request, session)

      local session_segment = nil
      for _, segment in ipairs(segments) do
        if segment.key == "session" then
          session_segment = segment
        end
      end

      assert.is_not_nil(session_segment)
      assert.has_match("^Σ%d+$", session_segment.label)
    end)

    it("should return empty table when both request and session are nil", function()
      local segments = usage.build_segments(nil, nil)
      assert.are.equal(0, #segments)
    end)

    it("should return empty table when session has no requests and request is nil", function()
      local session = session_module.Session.new()
      local segments = usage.build_segments(nil, session)
      assert.are.equal(0, #segments)
    end)

    it("should include thinking tokens item when present", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "o1",
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 25,
        input_price = 15.00,
        output_price = 60.00,
        output_has_thoughts = true,
      })

      local segments = usage.build_segments(request, nil)

      local request_segment = nil
      for _, segment in ipairs(segments) do
        if segment.key == "request" then
          request_segment = segment
        end
      end

      local thinking_item = nil
      for _, item in ipairs(request_segment.items) do
        if item.key == "thinking_tokens" then
          thinking_item = item
        end
      end

      assert.is_not_nil(thinking_item)
      assert.has_match("25\xE2\x81\x82", thinking_item.text)
      assert.are.equal(50, thinking_item.priority)
    end)
  end)
end)

describe("flemma.usage driver", function()
  local usage
  local bar_mock

  before_each(function()
    package.loaded["flemma.ui.bar"] = nil
    package.loaded["flemma.usage"] = nil
    package.loaded["flemma.state"] = nil
    bar_mock = require("tests.utilities.bar_mock").install_as_flemma_ui_bar()
    usage = require("flemma.usage")
  end)

  describe("show", function()
    it("is a no-op when ui.usage.enabled is false", function()
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Override config.get so the enabled flag is false for this test.
      -- (The project's test-config override idiom is monkey-patching
      -- flemma.config.get within the spec; same pattern is used in
      -- state_management_spec.lua.)
      local config_mod = require("flemma.config")
      local orig_get = config_mod.get
      config_mod.get = function(b)
        local cfg = orig_get(b)
        local patched = vim.tbl_deep_extend("force", cfg, { ui = { usage = { enabled = false } } })
        return patched
      end

      usage.show(bufnr, nil)
      config_mod.get = orig_get
      assert.equals(0, #bar_mock._handles)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("creates a Bar at ui.usage.position with layout.PREFIX icon", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x" })
      vim.api.nvim_set_current_buf(bufnr)
      -- Provide a fake request whose build_segments produces a non-empty list
      local fake_request = {
        model = "test-model",
        provider = "test",
        thoughts_tokens = 0,
        cache_read_input_tokens = 0,
        get_total_input_tokens = function()
          return 100
        end,
        get_total_output_tokens = function()
          return 50
        end,
        get_total_cost = function()
          return 0.01
        end,
      }
      usage.show(bufnr, fake_request)
      assert.is_true(vim.wait(200, function()
        return #bar_mock._handles > 0
      end))
      assert.equals(1, #bar_mock._handles)
      local opts = bar_mock._handles[1].opts
      assert.equals(bufnr, opts.bufnr)
      assert.equals("top", opts.position)
      local layout = require("flemma.ui.bar.layout")
      assert.equals(layout.PREFIX, opts.icon)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("cleanup_buffer", function()
    it("dismisses active bar and stops timer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x" })
      vim.api.nvim_set_current_buf(bufnr)
      local fake_request = {
        model = "test-model",
        provider = "test",
        thoughts_tokens = 0,
        cache_read_input_tokens = 0,
        get_total_input_tokens = function()
          return 100
        end,
        get_total_output_tokens = function()
          return 50
        end,
        get_total_cost = function()
          return 0.01
        end,
      }
      usage.show(bufnr, fake_request)
      assert.is_true(vim.wait(200, function()
        return #bar_mock._handles > 0
      end))
      assert.is_false(bar_mock._handles[1]:is_dismissed())
      usage.cleanup_buffer(bufnr)
      assert.is_true(bar_mock._handles[1]:is_dismissed())
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("recall_last", function()
    it("warns when buffer has no filepath", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      local warned = false
      local orig = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      usage.recall_last()
      vim.notify = orig
      assert.is_true(warned)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
