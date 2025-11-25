describe("flemma.session", function()
  local session_module

  before_each(function()
    package.loaded["flemma.session"] = nil
    session_module = require("flemma.session")
  end)

  describe("Request", function()
    it("should create a request with all required fields", function()
      local request = session_module.Request.new({
        provider = "claude",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 10,
        input_price = 3.00,
        output_price = 15.00,
        filepath = "/home/user/project/chat.txt",
      })

      assert.are.equal("claude", request.provider)
      assert.are.equal("claude-sonnet-4-5", request.model)
      assert.are.equal(100, request.input_tokens)
      assert.are.equal(50, request.output_tokens)
      assert.are.equal(10, request.thoughts_tokens)
      assert.are.equal(3.00, request.input_price)
      assert.are.equal(15.00, request.output_price)
      assert.are.equal("/home/user/project/chat.txt", request.filepath)
      assert.is_nil(request.bufnr)
      assert.is_number(request.timestamp)
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

    it("should calculate output cost including thoughts tokens", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "o1",
        input_tokens = 100,
        output_tokens = 500000,
        thoughts_tokens = 500000,
        input_price = 15.00,
        output_price = 60.00,
      })

      -- (500000 + 500000) / 1000000 * 60.00 = 60.00
      assert.are.equal(60.00, request:get_output_cost())
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

    it("should get total output tokens including thoughts", function()
      local request = session_module.Request.new({
        provider = "claude",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 200,
        thoughts_tokens = 50,
        input_price = 3.00,
        output_price = 15.00,
      })

      assert.are.equal(250, request:get_total_output_tokens())
    end)

    it("should handle zero thoughts tokens", function()
      local request = session_module.Request.new({
        provider = "claude",
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
        provider = "claude",
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
        provider = "claude",
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
        provider = "claude",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 3.00,
        output_price = 15.00,
      })

      session:add_request({
        provider = "claude",
        model = "claude-sonnet-4-5",
        input_tokens = 200,
        output_tokens = 75,
        input_price = 3.00,
        output_price = 15.00,
      })

      assert.are.equal(300, session:get_total_input_tokens())
    end)

    it("should calculate total output tokens including thoughts", function()
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

      -- (50 + 25) + (75 + 30) = 180
      assert.are.equal(180, session:get_total_output_tokens())
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
        provider = "claude",
        model = "claude-sonnet-4-5",
        input_tokens = 1000000,
        output_tokens = 500000,
        thoughts_tokens = 0,
        input_price = 3.00,
        output_price = 15.00,
      })

      session:add_request({
        provider = "claude",
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

      -- First request with Claude pricing
      session:add_request({
        provider = "claude",
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
        provider = "claude",
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
        provider = "claude",
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

    it("should handle sessions with only thoughts tokens", function()
      local session = session_module.Session.new()

      session:add_request({
        provider = "openai",
        model = "o1",
        input_tokens = 1000000,
        output_tokens = 0,
        thoughts_tokens = 1000000,
        input_price = 15.00,
        output_price = 60.00,
      })

      assert.are.equal(1000000, session:get_total_output_tokens())
      assert.are.equal(1000000, session:get_total_thoughts_tokens())
      -- Output cost should be based on thoughts tokens
      assert.are.equal(60.00, session:get_total_output_cost())
    end)
  end)
end)
