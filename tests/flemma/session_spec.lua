describe("flemma.session", function()
  local session_module

  before_each(function()
    package.loaded["flemma.session"] = nil
    session_module = require("flemma.session")
  end)

  describe("Request", function()
    it("should create a request with all required fields", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 10,
        input_price = 3.00,
        output_price = 15.00,
        filepath = "/home/user/project/chat.txt",
      })

      assert.are.equal("anthropic", request.provider)
      assert.are.equal("claude-sonnet-4-5", request.model)
      assert.are.equal(100, request.input_tokens)
      assert.are.equal(50, request.output_tokens)
      assert.are.equal(10, request.thoughts_tokens)
      assert.are.equal(3.00, request.input_price)
      assert.are.equal(15.00, request.output_price)
      assert.are.equal("/home/user/project/chat.txt", request.filepath)
      assert.is_nil(request.bufnr)
      assert.is_nil(request.started_at)
      assert.is_number(request.completed_at)
    end)

    it("should store started_at and completed_at timestamps", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 3.00,
        output_price = 15.00,
        started_at = 1700000000,
        completed_at = 1700000010,
      })

      assert.are.equal(1700000000, request.started_at)
      assert.are.equal(1700000010, request.completed_at)
    end)

    it("should compute costs from raw pricing data", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 1000000,
        output_tokens = 500000,
        thoughts_tokens = 0,
        input_price = 3.00,
        output_price = 15.00,
      })

      -- Input: 1000000 / 1000000 * 3.00 = 3.00
      assert.are.equal(3.00, request:get_input_cost())
      -- Output: 500000 / 1000000 * 15.00 = 7.50
      assert.are.equal(7.50, request:get_output_cost())
      -- Total: 3.00 + 7.50 = 10.50
      assert.are.equal(10.50, request:get_total_cost())
    end)

    it("should compute cache-aware costs from raw pricing data", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 500000,
        output_tokens = 200000,
        input_price = 3.00,
        output_price = 15.00,
        cache_read_input_tokens = 300000,
        cache_creation_input_tokens = 100000,
        cache_read_multiplier = 0.1,
        cache_write_multiplier = 1.25,
      })

      -- Input base: 500000 / 1000000 * 3.00 = 1.50
      -- Cache read: 300000 / 1000000 * (3.00 * 0.1) = 0.09
      -- Cache write: 100000 / 1000000 * (3.00 * 1.25) = 0.375
      local expected_input = 1.50 + 0.09 + 0.375
      assert.is_true(math.abs(request:get_input_cost() - expected_input) < 0.0001)
    end)

    it("should calculate input cost correctly", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 1000000,
        output_tokens = 0,
        input_price = 2.50,
        output_price = 10.00,
      })

      assert.are.equal(2.50, request:get_input_cost())
    end)

    it("should calculate output cost for Vertex (thoughts separate from output)", function()
      local request = session_module.Request.new({
        provider = "vertex",
        model = "gemini-2.5-pro",
        input_tokens = 100,
        output_tokens = 500000,
        thoughts_tokens = 500000,
        input_price = 1.25,
        output_price = 10.00,
        output_has_thoughts = false, -- Vertex: thoughts are separate
      })

      -- Vertex: (500000 + 500000) / 1000000 * 10.00 = 10.00
      assert.are.equal(10.00, request:get_output_cost())
    end)

    it("should calculate output cost for OpenAI (thoughts included in output)", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "o1",
        input_tokens = 100,
        output_tokens = 500000, -- completion_tokens already includes reasoning_tokens
        thoughts_tokens = 300000, -- reasoning_tokens is a subset, tracked separately for display
        input_price = 15.00,
        output_price = 60.00,
        output_has_thoughts = true, -- OpenAI: thoughts already counted in output
      })

      -- OpenAI: 500000 / 1000000 * 60.00 = 30.00 (NOT adding thoughts_tokens again)
      assert.are.equal(30.00, request:get_output_cost())
    end)

    it("should calculate total cost correctly", function()
      local request = session_module.Request.new({
        provider = "vertex",
        model = "gemini-2.0-flash-thinking",
        input_tokens = 2000000,
        output_tokens = 1000000,
        thoughts_tokens = 0,
        input_price = 0.10,
        output_price = 0.40,
      })

      -- Input: 2000000 / 1000000 * 0.10 = 0.20
      -- Output: 1000000 / 1000000 * 0.40 = 0.40
      -- Total: 0.60
      local total_cost = request:get_total_cost()
      assert.is_true(math.abs(total_cost - 0.60) < 0.0001, "Expected ~0.60, got " .. total_cost)
    end)

    it("should get total output tokens for Vertex (thoughts separate)", function()
      local request = session_module.Request.new({
        provider = "vertex",
        model = "gemini-2.5-pro",
        input_tokens = 100,
        output_tokens = 200,
        thoughts_tokens = 50,
        input_price = 1.25,
        output_price = 10.00,
        output_has_thoughts = false, -- Vertex: thoughts are separate
      })

      -- Vertex: 200 + 50 = 250
      assert.are.equal(250, request:get_total_output_tokens())
    end)

    it("should get total output tokens for Anthropic (thoughts included)", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 200, -- already includes thinking tokens
        thoughts_tokens = 0, -- Anthropic doesn't report separate thinking token count
        input_price = 3.00,
        output_price = 15.00,
        output_has_thoughts = true, -- Anthropic: thoughts already counted in output
      })

      -- Anthropic: just output_tokens (200), not adding thoughts again
      assert.are.equal(200, request:get_total_output_tokens())
    end)

    it("should handle zero thoughts tokens", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 200,
        thoughts_tokens = 0,
        input_price = 3.00,
        output_price = 15.00,
      })

      assert.are.equal(200, request:get_total_output_tokens())
      -- Output cost should only include output_tokens
      local expected_output_cost = (200 / 1000000) * 15.00
      assert.are.equal(expected_output_cost, request:get_output_cost())
    end)

    it("should store bufnr for unnamed buffers", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 3.00,
        output_price = 15.00,
        bufnr = 5, -- Unnamed buffer
      })

      assert.is_nil(request.filepath)
      assert.are.equal(5, request.bufnr)
    end)
  end)

  describe("Session", function()
    it("should create an empty session", function()
      local session = session_module.Session.new()
      assert.are.equal(0, session:get_request_count())
    end)

    it("should add requests to the session", function()
      local session = session_module.Session.new()

      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 3.00,
        output_price = 15.00,
      })

      assert.are.equal(1, session:get_request_count())
    end)

    it("should calculate total input tokens across multiple requests", function()
      local session = session_module.Session.new()

      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 3.00,
        output_price = 15.00,
      })

      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 200,
        output_tokens = 75,
        input_price = 3.00,
        output_price = 15.00,
      })

      assert.are.equal(300, session:get_total_input_tokens())
    end)

    it("should calculate total output tokens for Vertex (thoughts separate)", function()
      local session = session_module.Session.new()

      session:add_request({
        provider = "vertex",
        model = "gemini-2.5-pro",
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 25,
        input_price = 1.25,
        output_price = 10.00,
        output_has_thoughts = false, -- Vertex: thoughts are separate
      })

      session:add_request({
        provider = "vertex",
        model = "gemini-2.5-pro",
        input_tokens = 200,
        output_tokens = 75,
        thoughts_tokens = 30,
        input_price = 1.25,
        output_price = 10.00,
        output_has_thoughts = false, -- Vertex: thoughts are separate
      })

      -- Vertex: (50 + 25) + (75 + 30) = 180
      assert.are.equal(180, session:get_total_output_tokens())
    end)

    it("should calculate total output tokens for OpenAI (thoughts included)", function()
      local session = session_module.Session.new()

      session:add_request({
        provider = "openai",
        model = "o1",
        input_tokens = 100,
        output_tokens = 500, -- completion_tokens already includes reasoning
        thoughts_tokens = 200, -- reasoning_tokens is a subset, for display only
        input_price = 15.00,
        output_price = 60.00,
        output_has_thoughts = true, -- OpenAI: thoughts already counted in output
      })

      session:add_request({
        provider = "openai",
        model = "o1",
        input_tokens = 200,
        output_tokens = 750, -- completion_tokens already includes reasoning
        thoughts_tokens = 300, -- reasoning_tokens is a subset, for display only
        input_price = 15.00,
        output_price = 60.00,
        output_has_thoughts = true, -- OpenAI: thoughts already counted in output
      })

      -- OpenAI: 500 + 750 = 1250 (NOT adding thoughts_tokens again)
      assert.are.equal(1250, session:get_total_output_tokens())
    end)

    it("should calculate total thoughts tokens", function()
      local session = session_module.Session.new()

      session:add_request({
        provider = "openai",
        model = "o1",
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 25,
        input_price = 15.00,
        output_price = 60.00,
      })

      session:add_request({
        provider = "openai",
        model = "o1",
        input_tokens = 200,
        output_tokens = 75,
        thoughts_tokens = 30,
        input_price = 15.00,
        output_price = 60.00,
      })

      assert.are.equal(55, session:get_total_thoughts_tokens())
    end)

    it("should calculate total costs correctly across multiple requests", function()
      local session = session_module.Session.new()

      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 1000000,
        output_tokens = 500000,
        thoughts_tokens = 0,
        input_price = 3.00,
        output_price = 15.00,
      })

      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 2000000,
        output_tokens = 1000000,
        thoughts_tokens = 0,
        input_price = 3.00,
        output_price = 15.00,
      })

      -- Request 1: Input: 3.00, Output: 7.50
      -- Request 2: Input: 6.00, Output: 15.00
      assert.are.equal(9.00, session:get_total_input_cost())
      assert.are.equal(22.50, session:get_total_output_cost())
      assert.are.equal(31.50, session:get_total_cost())
    end)

    it("should handle pricing changes between requests", function()
      local session = session_module.Session.new()

      -- First request with Anthropic pricing
      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 1000000,
        output_tokens = 1000000,
        thoughts_tokens = 0,
        input_price = 3.00,
        output_price = 15.00,
      })

      -- Second request with OpenAI pricing (simulating provider switch)
      session:add_request({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 1000000,
        output_tokens = 1000000,
        thoughts_tokens = 0,
        input_price = 2.50,
        output_price = 10.00,
      })

      -- Request 1: Input: 3.00, Output: 15.00
      -- Request 2: Input: 2.50, Output: 10.00
      assert.are.equal(5.50, session:get_total_input_cost())
      assert.are.equal(25.00, session:get_total_output_cost())
      assert.are.equal(30.50, session:get_total_cost())
    end)

    it("should get the latest request", function()
      local session = session_module.Session.new()

      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 3.00,
        output_price = 15.00,
      })

      session:add_request({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 200,
        output_tokens = 75,
        input_price = 2.50,
        output_price = 10.00,
      })

      local latest = session:get_latest_request()
      assert.are.equal("openai", latest.provider)
      assert.are.equal("gpt-4o", latest.model)
    end)

    it("should return nil for latest request when session is empty", function()
      local session = session_module.Session.new()
      assert.is_nil(session:get_latest_request())
    end)

    it("should reset the session", function()
      local session = session_module.Session.new()

      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 3.00,
        output_price = 15.00,
      })

      assert.are.equal(1, session:get_request_count())

      session:reset()
      assert.are.equal(0, session:get_request_count())
      assert.are.equal(0, session:get_total_input_tokens())
      assert.are.equal(0, session:get_total_output_tokens())
    end)

    it("should handle Vertex sessions with only thoughts tokens", function()
      local session = session_module.Session.new()

      -- For Vertex, thoughts_tokens is separate from output_tokens
      session:add_request({
        provider = "vertex",
        model = "gemini-2.5-pro",
        input_tokens = 1000000,
        output_tokens = 0,
        thoughts_tokens = 1000000,
        input_price = 1.25,
        output_price = 10.00,
        output_has_thoughts = false, -- Vertex: thoughts are separate
      })

      -- Vertex: 0 + 1000000 = 1000000 total output tokens
      assert.are.equal(1000000, session:get_total_output_tokens())
      assert.are.equal(1000000, session:get_total_thoughts_tokens())
      -- Output cost: 1000000 / 1000000 * 10.00 = 10.00
      assert.are.equal(10.00, session:get_total_output_cost())
    end)

    it("should handle OpenAI sessions where output_tokens is completion_tokens", function()
      local session = session_module.Session.new()

      -- For OpenAI, completion_tokens already includes reasoning_tokens
      -- So if output_tokens = 1000000 and thoughts_tokens = 800000,
      -- that means 200000 visible tokens + 800000 reasoning tokens = 1000000 total
      session:add_request({
        provider = "openai",
        model = "o1",
        input_tokens = 1000000,
        output_tokens = 1000000, -- completion_tokens (includes reasoning)
        thoughts_tokens = 800000, -- reasoning_tokens (subset of completion_tokens, for display)
        input_price = 15.00,
        output_price = 60.00,
        output_has_thoughts = true, -- OpenAI: thoughts already counted in output
      })

      -- OpenAI: just output_tokens, not adding thoughts again
      assert.are.equal(1000000, session:get_total_output_tokens())
      assert.are.equal(800000, session:get_total_thoughts_tokens())
      -- Output cost: 1000000 / 1000000 * 60.00 = 60.00 (NOT 108.00!)
      assert.are.equal(60.00, session:get_total_output_cost())
    end)

    it("should load requests from a list of raw option tables", function()
      local session = session_module.Session.new()

      -- Add a request that will be replaced
      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 999,
        output_tokens = 999,
        input_price = 3.00,
        output_price = 15.00,
      })
      assert.are.equal(1, session:get_request_count())

      -- Load replaces existing requests
      session:load({
        {
          provider = "anthropic",
          model = "claude-sonnet-4-5",
          input_tokens = 100,
          output_tokens = 50,
          input_price = 3.00,
          output_price = 15.00,
          started_at = 1700000000,
          completed_at = 1700000010,
          cache_read_input_tokens = 500,
          cache_creation_input_tokens = 200,
          cache_read_multiplier = 0.1,
          cache_write_multiplier = 1.25,
        },
        {
          provider = "openai",
          model = "gpt-4o",
          input_tokens = 200,
          output_tokens = 75,
          thoughts_tokens = 25,
          input_price = 2.50,
          output_price = 10.00,
          started_at = 1700000020,
          completed_at = 1700000030,
        },
      })

      assert.are.equal(2, session:get_request_count())
      assert.are.equal(300, session:get_total_input_tokens())

      -- Verify first request preserved all raw fields
      local first = session.requests[1]
      assert.are.equal("anthropic", first.provider)
      assert.are.equal(100, first.input_tokens)
      assert.are.equal(1700000000, first.started_at)
      assert.are.equal(1700000010, first.completed_at)
      assert.are.equal(500, first.cache_read_input_tokens)
      assert.are.equal(0.1, first.cache_read_multiplier)

      -- Verify second request
      local second = session.requests[2]
      assert.are.equal("openai", second.provider)
      assert.are.equal(25, second.thoughts_tokens)

      -- Verify costs are derived correctly from loaded data
      local latest = session:get_latest_request()
      assert.are.equal("gpt-4o", latest.model)
      assert.is_true(session:get_total_cost() > 0)
    end)

    it("should load an empty list to clear the session", function()
      local session = session_module.Session.new()

      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 3.00,
        output_price = 15.00,
      })
      assert.are.equal(1, session:get_request_count())

      session:load({})
      assert.are.equal(0, session:get_request_count())
    end)

    it("should survive a JSON round-trip without losing data", function()
      local session = session_module.Session.new()

      -- Use microsecond-precision floats to verify they survive JSON encoding
      local started_1 = 1700000000.123456
      local completed_1 = 1700000042.654321
      local started_2 = 1700000100.111222
      local completed_2 = 1700000110.999888

      -- Add a request with every field populated (no nils)
      session:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 1500,
        output_tokens = 800,
        thoughts_tokens = 200,
        input_price = 3.00,
        output_price = 15.00,
        filepath = "/home/user/project/chat.chat",
        started_at = started_1,
        completed_at = completed_1,
        output_has_thoughts = false,
        cache_read_input_tokens = 5000,
        cache_creation_input_tokens = 2000,
        cache_read_multiplier = 0.1,
        cache_write_multiplier = 1.25,
      })

      -- Add a request with optional fields left nil and output_has_thoughts = true
      session:add_request({
        provider = "openai",
        model = "o1",
        input_tokens = 900,
        output_tokens = 400,
        thoughts_tokens = 150,
        input_price = 15.00,
        output_price = 60.00,
        output_has_thoughts = true,
        started_at = started_2,
        completed_at = completed_2,
      })

      -- Snapshot costs before round-trip
      local cost_before = session:get_total_cost()
      local input_cost_before = session:get_total_input_cost()
      local output_cost_before = session:get_total_output_cost()

      -- JSON round-trip using vim.json (lua-cjson, preserves full precision)
      local json = vim.json.encode(session.requests)
      local decoded = vim.json.decode(json)
      session:load(decoded)

      -- Same number of requests
      assert.are.equal(2, session:get_request_count())

      -- First request: every field preserved
      local first = session.requests[1]
      assert.are.equal("anthropic", first.provider)
      assert.are.equal("claude-sonnet-4-5", first.model)
      assert.are.equal(1500, first.input_tokens)
      assert.are.equal(800, first.output_tokens)
      assert.are.equal(200, first.thoughts_tokens)
      assert.are.equal(3.00, first.input_price)
      assert.are.equal(15.00, first.output_price)
      assert.are.equal("/home/user/project/chat.chat", first.filepath)
      assert.are.equal(started_1, first.started_at)
      assert.are.equal(completed_1, first.completed_at)
      assert.are.equal(false, first.output_has_thoughts)
      assert.are.equal(5000, first.cache_read_input_tokens)
      assert.are.equal(2000, first.cache_creation_input_tokens)
      assert.are.equal(0.1, first.cache_read_multiplier)
      assert.are.equal(1.25, first.cache_write_multiplier)

      -- Second request: check key fields and that nil optionals survive
      local second = session.requests[2]
      assert.are.equal("openai", second.provider)
      assert.are.equal("o1", second.model)
      assert.are.equal(true, second.output_has_thoughts)
      assert.are.equal(150, second.thoughts_tokens)
      assert.is_nil(second.filepath)

      -- Costs match exactly after round-trip
      assert.are.equal(cost_before, session:get_total_cost())
      assert.are.equal(input_cost_before, session:get_total_input_cost())
      assert.are.equal(output_cost_before, session:get_total_output_cost())
    end)
  end)
end)
